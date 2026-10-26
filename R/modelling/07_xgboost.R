# MODEL-07: Multiclass XGBoost gradient-boosted trees (M3/M4)
#
# Run from the repository root (after renv::install('xgboost')):
#   Rscript R/modelling/07_xgboost.R M4 --smoke      # small API check
#   Rscript R/modelling/07_xgboost.R M4 --benchmark  # no saved results
#   Rscript R/modelling/07_xgboost.R M4
#   Rscript R/modelling/07_xgboost.R M3
#
# 18-class, complete-case cohort; uses the same frozen random/spatial outer
# folds, matched inner fit/tune roles and common evaluation function as the
# other four classifiers. No resampling, class weights, target leakage or
# feature preprocessing estimated from assessment observations.
#
# Each inner candidate stops on TUNE multinomial LOG LOSS (continuous and
# stable). Candidate configurations are selected using TUNE MACRO-F1, the
# predeclared primary metric; number of boosting rounds is selected entirely
# within the same inner split. The selected model is then REFIT on the FULL
# outer development set for exactly the selected number of rounds. Assessment
# observations and labels are used once, only after all choices are frozen.
#
# Tuned grid: depth 3/6 x eta .07/.15 x min_child_weight 2/8 (8 candidates).
# Fixed regularisation: subsample=.85, colsample_bytree=.85, lambda=1.
# Up to 300 rounds, early stopping after 25 consecutive non-improvements.
# Evaluation is intentionally under the natural (unweighted) class mix.
#
# Outputs:
#   outputs/tables/model_xgboost_{fold_metrics,summary,class_metrics,
#       tuning,selected,feature_importance}.csv
#   data/interim/modelling/xgboost_results_<M>.rds      (ignored)
#   data/interim/modelling/oof_xgboost_<M>.rds          (ignored)
#
# Tested against XGBoost 3.x API conventions; model metadata can live in
# XGBoost-internal rather than R-level attributes. Accessor converts stored
# 0-based best_iteration to a 1-based count of boosting rounds.
# Platform: xgboost >=3.0 R API uses evals= and xgb.train(); the old
# watchlist= argument is deprecated. Tested syntax should be checked locally
# with Rscript -e 'invisible(parse(file="R/modelling/07_xgboost.R"))'.

source("R/modelling/modelling_helpers.R")
suppressPackageStartupMessages({
  library(readr)
  if (!requireNamespace("xgboost", quietly = TRUE)) {
    stop("Install xgboost in renv: renv::install('xgboost', prompt=FALSE)",
         call. = FALSE)
  }
})

if (utils::packageVersion("xgboost") < "3.0.0") {
  stop("This script uses the xgboost >=3.0 R interface (evals=).",
       call. = FALSE)
}

model_name <- "xgboost"
args <- commandArgs(trailingOnly = TRUE)
benchmark <- "--benchmark" %in% args
smoke <- "--smoke" %in% args
if (benchmark && smoke) stop("Choose only one of --smoke and --benchmark")
sets <- args[!(args %in% c("--benchmark", "--smoke"))]
if (length(sets) > 1L ||
    (length(sets) == 1L && !(sets[[1L]] %in% c("M3", "M4")))) {
  stop("Usage: Rscript R/modelling/07_xgboost.R [M3|M4] [--smoke|--benchmark]",
       call. = FALSE)
}
feature_set <- if (length(sets)) sets[[1L]] else "M4"

max_rounds <- 300L
early_stop <- 25L
# A bounded, genuine three-parameter grid. No assessment results used
# to set or adapt this grid.
tuning_grid <- expand.grid(
  max_depth = c(3L, 6L),
  eta = c(0.07, 0.15),
  min_child_weight = c(2, 8),
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)

requested_threads <- suppressWarnings(as.integer(Sys.getenv("XGB_THREADS", "4")))
xgb_threads <- if (is.na(requested_threads) || requested_threads < 1L) {
  4L
} else requested_threads

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)
y <- cohort$scientificName
class_levels <- levels(y)
n_classes <- length(class_levels)
features <- feature_sets[[feature_set]]
regimes <- c("random", "spatial")

stopifnot(nrow(cohort) == 242600L, n_classes == 18L,
          length(features) == if (feature_set == "M4") 28L else 26L,
          !anyNA(cohort[features]))

# No scaling or PCA for trees. Feature names/order are fixed for each set.
x_all <- as.matrix(cohort[, features, drop = FALSE])
storage.mode(x_all) <- "double"
stopifnot(all(is.finite(x_all)))

elapsed <- function(t0) as.numeric(difftime(Sys.time(), t0, units = "secs"))
job_seed <- function(regime, fold, candidate = 0L) {
  offset <- if (regime == "random") 1100L else 2100L
  as.integer(modelling_seed + offset + 20L * fold + candidate)
}

make_dmatrix <- function(rows, with_labels = TRUE) {
  xx <- x_all[rows, , drop = FALSE]
  if (with_labels) {
    xgboost::xgb.DMatrix(data = xx, label = as.integer(y[rows]) - 1L)
  } else {
    xgboost::xgb.DMatrix(data = xx)
  }
}

make_params <- function(depth, eta, child, seed) {
  list(
    objective = "multi:softprob",
    num_class = as.integer(n_classes),
    eval_metric = "mlogloss",
    tree_method = "hist",
    max_bin = 256L,
    max_depth = as.integer(depth),
    eta = as.numeric(eta),
    min_child_weight = as.numeric(child),
    subsample = 0.85,
    colsample_bytree = 0.85,
    lambda = 1,
    nthread = xgb_threads,
    seed = as.integer(seed),
    verbosity = 0L
  )
}

# XGBoost 3.x keeps early-stopping metadata as either R attributes
# (best_iteration: 1-based) or native booster attributes (0-based).
# Some Windows builds do not return the corresponding R attributes.
get_early_stop_details <- function(model, max_allowed) {
  rounds <- suppressWarnings(as.integer(attr(model, "best_iteration", exact = TRUE)))
  if (length(rounds) != 1L || is.na(rounds)) {
    internal <- xgboost::xgb.attr(model, "best_iteration")
    if (!is.null(internal) && length(internal) == 1L) {
      rounds <- suppressWarnings(as.integer(internal)) + 1L
    }
  }

  score <- suppressWarnings(as.numeric(attr(model, "best_score", exact = TRUE)))
  if (length(score) != 1L || !is.finite(score)) {
    internal <- xgboost::xgb.attr(model, "best_score")
    if (!is.null(internal) && length(internal) == 1L) {
      score <- suppressWarnings(as.numeric(internal))
    }
  }

  # If needed, use the recorded validation loss rather than invent a round.
  if (length(rounds) != 1L || is.na(rounds) ||
      length(score) != 1L || !is.finite(score)) {
    log <- attr(model, "evaluation_log", exact = TRUE)
    if (is.null(log)) {
      log <- tryCatch(model$evaluation_log, error = function(e) NULL)
    }
    if (!is.null(log) && "tune_mlogloss" %in% names(log) &&
        length(log$tune_mlogloss) > 0L && all(is.finite(log$tune_mlogloss))) {
      log_best <- which.min(log$tune_mlogloss)
      if (length(rounds) != 1L || is.na(rounds)) rounds <- as.integer(log_best)
      if (length(score) != 1L || !is.finite(score)) {
        score <- as.numeric(log$tune_mlogloss[[rounds]])
      }
    }
  }

  if (length(rounds) != 1L || is.na(rounds) ||
      rounds < 1L || rounds > max_allowed ||
      length(score) != 1L || !is.finite(score)) {
    stop("XGBoost early-stopping metadata unavailable/invalid; ",
         "please share xgb.attributes(model) and evaluation_log diagnostics.",
         call. = FALSE)
  }
  list(best_iteration = as.integer(rounds), best_score = as.numeric(score))
}

# Version 3.x multi:softprob returns an n x 18 matrix; reject other shapes
# instead of accidentally reshaping or permuting species probabilities.
# Explicitly pass the selected 1-based round count for early-stop candidates.
predict_probs <- function(model, dmat, expected_rows, best_rounds = NULL) {
  if (is.null(best_rounds)) {
    raw <- predict(model, dmat)
  } else {
    raw <- predict(model, dmat,
                   iterationrange = c(1L, as.integer(best_rounds)))
  }
  if (!is.matrix(raw) || nrow(raw) != expected_rows ||
      ncol(raw) != n_classes) {
    stop("Unexpected xgboost multi:softprob prediction shape: ",
         paste(dim(raw), collapse = " x "), call. = FALSE)
  }
  prob <- as.matrix(raw)
  colnames(prob) <- class_levels
  if (any(!is.finite(prob)) || any(prob < -1e-8) ||
      any(prob > 1 + 1e-8) ||
      max(abs(rowSums(prob) - 1)) > 1e-5) {
    stop("Invalid xgboost prediction probabilities", call. = FALSE)
  }
  prob
}

# Fit one candidate using only the inner FIT and inner TUNE partitions.
fit_candidate <- function(d_fit, d_tune, depth, eta, child, seed) {
  xgboost::xgb.train(
    params = make_params(depth, eta, child, seed),
    data = d_fit,
    nrounds = max_rounds,
    evals = list(tune = d_tune),
    early_stopping_rounds = early_stop,
    maximize = FALSE,
    verbose = 0L
  )
}

# Lightweight smoke test of the 3.x API, early stopping, probabilities and
# feature importance. Stratified small inner partitions; NO assessment access.
if (smoke) {
  inner <- folds[["random_inner_1"]]
  fit_rows <- unlist(lapply(class_levels, function(cl) {
    head(which(inner == "fit" & y == cl), 250L)
  }), use.names = FALSE)
  tune_rows <- unlist(lapply(class_levels, function(cl) {
    head(which(inner == "tune" & y == cl), 60L)
  }), use.names = FALSE)
  stopifnot(length(fit_rows) >= 18L * 150L,
            length(tune_rows) >= 18L * 40L)
  t0 <- Sys.time()
  dfit <- make_dmatrix(fit_rows)
  dtune <- make_dmatrix(tune_rows)
  model <- xgboost::xgb.train(
    params = make_params(3L, 0.15, 2, job_seed("random", 1L, 1L)),
    data = dfit, nrounds = 40L,
    evals = list(tune = dtune), early_stopping_rounds = 8L,
    maximize = FALSE, verbose = 0L
  )
  details <- get_early_stop_details(model, 40L)
  best <- details$best_iteration
  score <- details$best_score
  prob <- predict_probs(model, dtune, length(tune_rows), best)
  metrics <- evaluate_predictions(prob, y[tune_rows])$overall
  importance <- xgboost::xgb.importance(model = model)
  stopifnot(nrow(importance) > 0L, is.finite(metrics$macro_f1))
  cat("\nXGBOOST SMOKE TEST PASSED\n")
  cat("xgboost version:", as.character(utils::packageVersion("xgboost")), "\n")
  cat("Fit / tune rows:", length(fit_rows), "/", length(tune_rows), "\n")
  cat("Best round:", best, "\n")
  cat("Inner macro-F1:", round(metrics$macro_f1, 4), "\n")
  cat("Elapsed seconds:", round(elapsed(t0), 2), "\n")
  cat("No model outputs written.\n")
  quit(save = "no", status = 0L)
}

# First run a small API/performance probe on the entire inner FIT partition,
# without using assessment rows. This mode saves nothing.
if (benchmark) {
  fit_rows <- which(folds[["random_inner_1"]] == "fit")
  tune_rows <- head(which(folds[["random_inner_1"]] == "tune"), 1500L)
  t0 <- Sys.time()
  dfit <- make_dmatrix(fit_rows)
  dtune <- make_dmatrix(tune_rows)
  params <- make_params(3L, 0.15, 2, job_seed("random", 1L, 1L))
  model <- xgboost::xgb.train(
    params = params, data = dfit, nrounds = 25L,
    evals = list(tune = dtune), verbose = 0L
  )
  prob <- predict_probs(model, dtune, length(tune_rows))
  stopifnot(identical(colnames(prob), class_levels))
  cat("\nXGBOOST BENCHMARK PASSED\n")
  cat("Installed xgboost:", as.character(utils::packageVersion("xgboost")), "\n")
  cat("Feature set:", feature_set, "\n")
  cat("Inner fit events:", length(fit_rows), "\n")
  cat("Inner tune queries:", length(tune_rows), "\n")
  cat("Benchmark rounds: 25 (full search maximum: 300)\n")
  cat("Candidates per fold:", nrow(tuning_grid), "\n")
  cat("Benchmark seconds:", round(elapsed(t0), 2), "\n")
  cat("Threads:", xgb_threads, "\n")
  cat("No model outputs written.\n")
  quit(save = "no", status = 0L)
}

fold_metrics <- list()
class_metrics <- list()
tuning_results <- list()
selected_results <- list()
importance_results <- list()
predictions <- list()

for (regime in regimes) {
  outer <- folds[[paste0(regime, "_fold")]]
  regime_predictions <- vector("list", n_outer_folds)

  for (k in seq_len(n_outer_folds)) {
    t0 <- Sys.time()
    inner <- folds[[paste0(regime, "_inner_", k)]]
    fit_rows <- which(inner == "fit")
    tune_rows <- which(inner == "tune")
    dev_rows <- which(outer != k)
    assess_rows <- which(outer == k)

    stopifnot(length(fit_rows) > 0L, length(tune_rows) > 0L,
              identical(which(inner == "assess"), assess_rows),
              identical(sort(c(fit_rows, tune_rows)), dev_rows),
              length(intersect(fit_rows, assess_rows)) == 0L,
              all(table(y[fit_rows]) > 0L),
              all(table(y[dev_rows]) > 0L))

    message(sprintf("XGB %s %s fold %d: tuning %d candidates (%d threads)",
                    feature_set, regime, k, nrow(tuning_grid), xgb_threads))

    d_fit <- make_dmatrix(fit_rows)
    d_tune <- make_dmatrix(tune_rows)
    candidate_results <- vector("list", nrow(tuning_grid))

    for (i in seq_len(nrow(tuning_grid))) {
      depth_i <- as.integer(tuning_grid$max_depth[[i]])
      eta_i <- as.numeric(tuning_grid$eta[[i]])
      child_i <- as.numeric(tuning_grid$min_child_weight[[i]])
      candidate_started <- Sys.time()

      candidate_model <- fit_candidate(
        d_fit, d_tune, depth_i, eta_i, child_i,
        job_seed(regime, k, i)
      )
      details <- get_early_stop_details(candidate_model, max_rounds)
      best_round <- details$best_iteration
      prob_tune <- predict_probs(candidate_model, d_tune,
                                 length(tune_rows), best_round)
      score <- evaluate_predictions(prob_tune, y[tune_rows])$overall
      candidate_results[[i]] <- tibble(
        max_depth = depth_i,
        eta = eta_i,
        min_child_weight = child_i,
        subsample = 0.85,
        colsample_bytree = 0.85,
        reg_lambda = 1,
        best_iteration = best_round,
        stopped_early = best_round < max_rounds,
        best_tune_mlogloss = details$best_score,
        tune_macro_f1 = score$macro_f1,
        tune_accuracy = score$accuracy,
        tune_mrr = score$mrr,
        tune_log_loss = score$log_loss,
        fit_seconds = elapsed(candidate_started)
      )
      message(sprintf(
        "XGB %s %s fold %d: %d/%d depth=%d eta=%.2f child=%.0f rounds=%d tune Macro-F1=%.4f (%.1f s)",
        feature_set, regime, k, i, nrow(tuning_grid),
        depth_i, eta_i, child_i, best_round,
        score$macro_f1, elapsed(t0)
      ))
      rm(candidate_model, prob_tune, details)
      gc(verbose = FALSE)
    }

    tuning <- bind_rows(candidate_results)
    # Choose by inner Macro-F1 ONLY. Deterministic ties favour shorter and
    # simpler trees, then fewer rounds.
    best <- tuning |>
      arrange(desc(tune_macro_f1), max_depth, best_iteration, eta,
              desc(min_child_weight)) |>
      slice(1L)

    # Refit selected settings on all DEVELOPMENT observations, including the
    # former inner-tune observations. No assessment labels or early stopping.
    d_dev <- make_dmatrix(dev_rows)
    d_assess <- make_dmatrix(assess_rows, with_labels = FALSE)
    final_seed <- job_seed(regime, k, 19L)
    final_model <- xgboost::xgb.train(
      params = make_params(best$max_depth, best$eta,
                           best$min_child_weight, final_seed),
      data = d_dev,
      nrounds = as.integer(best$best_iteration),
      verbose = 0L
    )

    prob <- predict_probs(final_model, d_assess, length(assess_rows))
    assessment <- evaluate_predictions(prob, y[assess_rows])
    runtime <- elapsed(t0)

    id <- tibble(model = model_name, feature_set = feature_set,
                 regime = regime, fold = k)
    fold_metrics[[length(fold_metrics) + 1L]] <- bind_cols(
      id, assessment$overall, tibble(runtime_seconds = runtime)
    )
    class_metrics[[length(class_metrics) + 1L]] <- bind_cols(
      id, assessment$by_class
    )
    tuning_results[[length(tuning_results) + 1L]] <- bind_cols(id, tuning)
    selected_results[[length(selected_results) + 1L]] <- bind_cols(
      id,
      best |>
        select(max_depth, eta, min_child_weight, subsample,
               colsample_bytree, reg_lambda, best_iteration,
               tune_macro_f1, best_tune_mlogloss, stopped_early),
      tibble(fit_events = length(fit_rows),
             tune_events = length(tune_rows),
             development_events = length(dev_rows),
             assessment_events = length(assess_rows),
             seed = final_seed, threads = xgb_threads,
             runtime_seconds = runtime)
    )

    raw_imp <- xgboost::xgb.importance(model = final_model)
    imp <- tibble(feature = features, gain = 0)
    if (nrow(raw_imp)) {
      idx <- match(raw_imp$Feature, imp$feature)
      if (anyNA(idx)) stop("Importance contains unrecognised predictor")
      imp$gain[idx] <- raw_imp$Gain
    }
    importance_results[[length(importance_results) + 1L]] <- bind_cols(id, imp)

    regime_predictions[[k]] <- list(row = assess_rows, prob = prob)
    message(sprintf(
      "XGB %s %s fold %d: depth=%d eta=%.2f child=%.0f rounds=%d, assessment Macro-F1=%.4f, top3=%.4f (%.1f s)",
      feature_set, regime, k, best$max_depth, best$eta,
      best$min_child_weight, best$best_iteration,
      assessment$overall$macro_f1, assessment$overall$top3_accuracy,
      runtime
    ))

    rm(d_fit, d_tune, d_dev, d_assess, final_model, prob, tuning, best)
    gc(verbose = FALSE)
  }

  rows <- unlist(lapply(regime_predictions, `[[`, "row"), use.names = FALSE)
  all_probs <- do.call(rbind, lapply(regime_predictions, `[[`, "prob"))
  stopifnot(identical(sort(rows), seq_len(nrow(cohort))))
  all_probs <- all_probs[order(rows), , drop = FALSE]
  stopifnot(nrow(all_probs) == nrow(cohort),
            identical(colnames(all_probs), class_levels),
            max(abs(rowSums(all_probs) - 1)) < 1e-5)

  predictions[[regime]] <- list(
    eventID = cohort$eventID,
    truth = y,
    fold = outer,
    prob = all_probs
  )
}

results <- list(
  fold_metrics = bind_rows(fold_metrics),
  class_metrics = bind_rows(class_metrics),
  tuning = bind_rows(tuning_results),
  selected = bind_rows(selected_results),
  importance = bind_rows(importance_results)
)
stopifnot(nrow(results$fold_metrics) == 2L * n_outer_folds,
          nrow(results$class_metrics) == 2L * n_outer_folds * n_classes,
          nrow(results$tuning) == 2L * n_outer_folds * nrow(tuning_grid),
          nrow(results$selected) == 2L * n_outer_folds)

dir.create(modelling_paths$model_outputs, recursive = TRUE, showWarnings = FALSE)
dir.create(modelling_paths$tables, recursive = TRUE, showWarnings = FALSE)
save_oof_predictions(predictions, model_name, feature_set)
saveRDS(results, file.path(modelling_paths$model_outputs,
                           paste0("xgboost_results_", feature_set, ".rds")))

completed_sets <- c("M3", "M4")
result_paths <- file.path(modelling_paths$model_outputs,
                         paste0("xgboost_results_", completed_sets, ".rds"))
result_paths <- result_paths[file.exists(result_paths)]
all_results <- lapply(result_paths, readRDS)
combine <- function(part) bind_rows(lapply(all_results, `[[`, part))
combined_folds <- combine("fold_metrics")
importance_summary <- combine("importance") |>
  group_by(model, feature_set, regime, feature) |>
  summarise(
    folds = n(),
    mean_gain = mean(gain),
    .groups = "drop"
  ) |>
  arrange(feature_set, regime, desc(mean_gain))
output_tables <- list(
  fold_metrics = combined_folds,
  summary = summarise_fold_metrics(combined_folds),
  class_metrics = combine("class_metrics"),
  tuning = combine("tuning"),
  selected = combine("selected"),
  feature_importance = importance_summary
)
for (name in names(output_tables)) {
  readr::write_csv(output_tables[[name]],
                   file.path(modelling_paths$tables,
                             paste0("model_xgboost_", name, ".csv")),
                   na = "NA")
}

cat("\nMODEL-07 XGBOOST PASSED\n")
cat("Completed feature sets:",
    paste(sort(unique(combined_folds$feature_set)), collapse = ", "), "\n")
print(output_tables$summary |>
        select(model, feature_set, regime, macro_f1_mean, macro_f1_sd,
               accuracy_mean, top3_accuracy_mean, mrr_mean), width = Inf)
