# MODEL-03: Elastic-net multinomial logistic regression (M1-M4)
#
# Purpose:
# Stage A feature-group progression and Stage B benchmark entry for the
# regularised linear model (docs/eda-10-modeling-handoff.md, sections 4-5).
#
# For each feature set x validation regime x outer fold:
#   1. fit a glmnet multinomial path on the inner "fit" rows for each alpha;
#   2. score every (alpha, lambda) on the inner "tune" rows by Macro-F1;
#   3. refit the selected configuration on the full outer development set;
#   4. predict the untouched outer assessment fold once.
#
# Preprocessing:
# - predictors are standardised inside every fit by glmnet
#   (standardize = TRUE), using only that fit's training rows; coefficients
#   are returned on the original scale;
# - the correlated BIO block, including BIO5/BIO6/BIO7, is retained and
#   handled by the elastic-net penalty rather than by deletion;
# - type.multinomial = "grouped" keeps or drops each predictor jointly for
#   all 18 classes, so selection is interpretable per predictor;
# - natural class distribution; no weighting or resampling.
#
# Usage (from repository root):
#   Rscript R/modelling/03_elastic_net.R            # M1 M2 M3 M4
#   Rscript R/modelling/03_elastic_net.R M1         # one feature set
#   EN_WORKERS=8 Rscript R/modelling/03_elastic_net.R M2 M3 M4
#
# All requested feature sets share one job queue (feature set x regime x
# fold). EN_WORKERS sets the number of parallel workers (default: cores - 2,
# capped at the number of jobs). Progress lines are printed as jobs run.
#
# Outputs (rebuilt from every completed feature set):
#   outputs/tables/model_elastic_net_fold_metrics.csv
#   outputs/tables/model_elastic_net_summary.csv
#   outputs/tables/model_elastic_net_class_metrics.csv
#   outputs/tables/model_elastic_net_tuning.csv
#   outputs/tables/model_elastic_net_selected.csv
#   outputs/tables/model_elastic_net_feature_importance.csv
#   data/interim/modelling/oof_elastic_net_<M>.rds          (ignored)
#   data/interim/modelling/elastic_net_results_<M>.rds      (ignored)

source("R/modelling/modelling_helpers.R")

suppressPackageStartupMessages({
  library(readr)
  library(glmnet)
  library(parallel)
})

model_name <- "elastic_net"

# Predeclared tuning grid.
alpha_grid <- c(0, 0.5, 1)
n_lambda <- 30L
lambda_min_ratio <- 1e-4

# Solver iteration limit. The glmnet default (1e5) fails to converge for
# M2-M4 below lambda ~ 0.01 and silently truncates the path ("solutions for
# larger lambdas returned"), which censored tuning in the first run. 1e6
# converges along the full path in a 20k-row check.
glmnet_maxit <- 1e6

contextual_sets <- c("M1", "M2", "M3", "M4")
args <- commandArgs(trailingOnly = TRUE)
run_sets <- if (length(args)) args else contextual_sets

if (!all(run_sets %in% contextual_sets)) {
  stop("Feature sets must be among: ", paste(contextual_sets, collapse = ", "),
       call. = FALSE)
}

jobs <- expand.grid(
  fold = seq_len(n_outer_folds),
  regime = c("random", "spatial"),
  feature_set = run_sets,
  stringsAsFactors = FALSE
)[, c("feature_set", "regime", "fold")]

requested_workers <- suppressWarnings(as.integer(Sys.getenv("EN_WORKERS")))
n_workers <- if (!is.na(requested_workers) && requested_workers > 0L) {
  requested_workers
} else {
  max(1L, detectCores() - 2L)
}
n_workers <- min(n_workers, nrow(jobs))

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)

y <- cohort$scientificName
class_levels <- levels(y)
x_all <- as.matrix(cohort[certified_predictors])


# -------------------------------------------------------------------------
# Model helpers
# -------------------------------------------------------------------------

# Timestamped progress line; written to stderr so it appears immediately
# from parallel workers.
log_progress <- function(...) {
  message(format(Sys.time(), "%H:%M:%S"), " | ", ...)
}

elapsed_minutes <- function(started) {
  sprintf("%.1f min", as.numeric(difftime(Sys.time(), started, units = "mins")))
}

# glmnet fit that records, rather than prints, convergence warnings.
fit_glmnet <- function(x, y, alpha, lambda = NULL) {

  warnings_seen <- character(0)

  fit <- withCallingHandlers(
    glmnet(
      x, y,
      family = "multinomial",
      type.multinomial = "grouped",
      alpha = alpha,
      lambda = lambda,
      nlambda = n_lambda,
      lambda.min.ratio = lambda_min_ratio,
      standardize = TRUE,
      control = list(maxit = glmnet_maxit)
    ),
    warning = function(w) {
      warnings_seen <<- c(warnings_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  list(fit = fit, warnings = warnings_seen)
}

# Predictors with any nonzero coefficient, per lambda on the path.
nonzero_features <- function(fit) {
  beta <- Reduce(`+`, lapply(fit$beta, abs))
  as.integer(colSums(beta > 0))
}

response_matrix <- function(prob_array_slice) {
  stopifnot(identical(colnames(prob_array_slice), class_levels))
  prob_array_slice
}


# -------------------------------------------------------------------------
# One feature set x regime x outer fold
# -------------------------------------------------------------------------

run_job <- function(feature_set, regime, k) {

  started <- Sys.time()
  job_label <- paste0(feature_set, " ", regime, " fold ", k)
  log_progress(job_label, ": started")

  features <- feature_sets[[feature_set]]
  x <- x_all[, features, drop = FALSE]

  outer <- folds[[paste0(regime, "_fold")]]
  inner <- folds[[paste0(regime, "_inner_", k)]]

  fit_rows <- which(inner == "fit")
  tune_rows <- which(inner == "tune")
  dev_rows <- which(outer != k)
  assess_rows <- which(outer == k)

  # --- 1-2. Tune alpha and lambda on the inner split ----------------------

  tuning <- list()
  paths <- list()
  warnings_seen <- character(0)

  for (alpha in alpha_grid) {

    path <- fit_glmnet(x[fit_rows, , drop = FALSE], y[fit_rows], alpha)
    warnings_seen <- c(warnings_seen, path$warnings)

    lambdas <- path$fit$lambda
    paths[[as.character(alpha)]] <- lambdas
    n_nonzero <- nonzero_features(path$fit)

    prob_path <- predict(
      path$fit,
      newx = x[tune_rows, , drop = FALSE],
      type = "response"
    )

    for (l in seq_along(lambdas)) {

      metrics <- evaluate_predictions(
        response_matrix(prob_path[, , l]),
        y[tune_rows]
      )$overall

      tuning[[length(tuning) + 1L]] <- tibble(
        alpha = alpha,
        lambda_index = l,
        lambda = lambdas[l],
        path_length = length(lambdas),
        nonzero_features = n_nonzero[l],
        tune_macro_f1 = metrics$macro_f1,
        tune_accuracy = metrics$accuracy,
        tune_mrr = metrics$mrr,
        tune_log_loss = metrics$log_loss
      )
    }

    rm(prob_path)

    log_progress(
      job_label, ": tuned alpha = ", alpha,
      " (", length(lambdas), " lambdas, ", elapsed_minutes(started), ")"
    )
  }

  tuning <- bind_rows(tuning)

  # Highest tune Macro-F1; ties go to the stronger penalty.
  selected <- tuning |>
    arrange(desc(tune_macro_f1), desc(lambda), desc(alpha)) |>
    slice(1)

  # --- 3. Refit on the full outer development set --------------------------
  # Refit along the same path down to the selected lambda (warm starts),
  # as glmnet recommends against fitting a single lambda value.

  path_lambdas <- paths[[as.character(selected$alpha)]]
  refit <- fit_glmnet(
    x[dev_rows, , drop = FALSE],
    y[dev_rows],
    alpha = selected$alpha,
    lambda = path_lambdas[seq_len(selected$lambda_index)]
  )
  warnings_seen <- c(warnings_seen, refit$warnings)

  # --- 4. Predict the outer assessment fold once ---------------------------

  prob <- response_matrix(
    predict(
      refit$fit,
      newx = x[assess_rows, , drop = FALSE],
      s = selected$lambda,
      type = "response"
    )[, , 1]
  )

  result <- evaluate_predictions(prob, y[assess_rows])

  log_progress(
    job_label, ": finished in ", elapsed_minutes(started),
    " | selected alpha = ", selected$alpha,
    " | assessment Macro-F1 = ", round(result$overall$macro_f1, 4)
  )

  # Standardised coefficient magnitude per predictor: original-scale
  # coefficients x development-set SD, then the L2 norm across classes.
  beta <- sapply(
    coef(refit$fit, s = selected$lambda),
    function(b) as.numeric(b[-1, 1])
  )
  rownames(beta) <- features
  standardised <- beta * apply(x[dev_rows, , drop = FALSE], 2, sd)

  importance <- tibble(
    model = model_name,
    feature_set = feature_set,
    regime = regime,
    fold = k,
    feature = features,
    standardised_coef_norm = sqrt(rowSums(standardised^2)),
    selected = rowSums(beta != 0) > 0
  )

  job_id <- tibble(
    model = model_name,
    feature_set = feature_set,
    regime = regime,
    fold = k
  )

  list(
    fold_metrics = bind_cols(job_id, result$overall),
    class_metrics = bind_cols(job_id, result$by_class),
    tuning = bind_cols(job_id, tuning),
    selected = bind_cols(
      job_id,
      selected |>
        select(alpha, lambda, lambda_index, path_length,
               nonzero_features, tune_macro_f1),
      tibble(
        n_features = length(features),
        selected_at_path_end = selected$lambda_index == selected$path_length,
        fit_events = length(fit_rows),
        tune_events = length(tune_rows),
        development_events = length(dev_rows),
        assessment_events = length(assess_rows),
        convergence_warnings = length(warnings_seen),
        # FALSE if the refit path stopped before the selected lambda, in which
        # case predict() would silently use a more regularised solution.
        refit_reached_selected =
          min(refit$fit$lambda) <= selected$lambda * (1 + 1e-8),
        warning_messages = paste(unique(warnings_seen), collapse = " || "),
        runtime_seconds = as.numeric(difftime(Sys.time(), started, units = "secs"))
      )
    ),
    importance = importance,
    assess_rows = assess_rows,
    prob = prob
  )
}


# -------------------------------------------------------------------------
# Run requested feature sets
# -------------------------------------------------------------------------

run_started <- Sys.time()
log_progress(
  "Elastic net: ", paste(run_sets, collapse = ", "), " | ",
  nrow(jobs), " jobs on ", n_workers, " workers"
)

job_results <- mclapply(
  seq_len(nrow(jobs)),
  function(i) run_job(jobs$feature_set[i], jobs$regime[i], jobs$fold[i]),
  mc.cores = n_workers,
  mc.preschedule = FALSE
)

job_failed <- vapply(
  job_results,
  function(r) is.null(r) || inherits(r, "try-error"),
  logical(1)
)

failed_sets <- character(0)

for (feature_set in run_sets) {

  set_index <- which(jobs$feature_set == feature_set)

  # A feature set is saved only if all six of its jobs succeeded.
  if (any(job_failed[set_index])) {
    failed_sets <- c(failed_sets, feature_set)
    log_progress(feature_set, ": FAILED, not saved")
    for (i in set_index[job_failed[set_index]]) {
      message("  ", jobs$regime[i], " fold ", jobs$fold[i], ": ",
              paste(as.character(job_results[[i]]), collapse = " "))
    }
    next
  }

  results <- job_results[set_index]
  set_jobs <- jobs[set_index, ]

  # Out-of-fold probabilities in cohort row order, one matrix per regime.
  predictions <- list()

  for (regime in c("random", "spatial")) {
    regime_results <- results[set_jobs$regime == regime]
    rows <- unlist(lapply(regime_results, `[[`, "assess_rows"))
    prob <- do.call(rbind, lapply(regime_results, `[[`, "prob"))

    stopifnot(identical(sort(rows), seq_len(nrow(cohort))))

    predictions[[regime]] <- list(
      eventID = cohort$eventID,
      truth = y,
      fold = folds[[paste0(regime, "_fold")]],
      prob = prob[order(rows), , drop = FALSE]
    )
  }

  save_oof_predictions(predictions, model_name, feature_set)

  feature_set_results <- lapply(
    c("fold_metrics", "class_metrics", "tuning", "selected", "importance"),
    function(part) bind_rows(lapply(results, `[[`, part))
  )
  names(feature_set_results) <- c(
    "fold_metrics", "class_metrics", "tuning", "selected", "importance"
  )

  saveRDS(
    feature_set_results,
    file.path(
      modelling_paths$model_outputs,
      paste0("elastic_net_results_", feature_set, ".rds")
    )
  )

  log_progress(feature_set, ": saved")
  print(
    feature_set_results$selected |>
      select(regime, fold, alpha, lambda, nonzero_features,
             tune_macro_f1, convergence_warnings, runtime_seconds),
    width = Inf
  )
}


# -------------------------------------------------------------------------
# Rebuild public tables from every completed feature set
# -------------------------------------------------------------------------

result_files <- file.path(
  modelling_paths$model_outputs,
  paste0("elastic_net_results_", contextual_sets, ".rds")
)
result_files <- result_files[file.exists(result_files)]

all_results <- lapply(result_files, readRDS)

combine_part <- function(part) {
  bind_rows(lapply(all_results, `[[`, part))
}

fold_metrics <- combine_part("fold_metrics")
summary_metrics <- summarise_fold_metrics(fold_metrics)

importance_summary <- combine_part("importance") |>
  group_by(model, feature_set, regime, feature) |>
  summarise(
    folds = n(),
    mean_standardised_coef_norm = mean(standardised_coef_norm),
    folds_selected = sum(selected),
    .groups = "drop"
  ) |>
  arrange(feature_set, regime, desc(mean_standardised_coef_norm))

tables <- list(
  fold_metrics = fold_metrics,
  summary = summary_metrics,
  class_metrics = combine_part("class_metrics"),
  tuning = combine_part("tuning"),
  selected = combine_part("selected"),
  feature_importance = importance_summary
)

for (name in names(tables)) {
  write_csv(
    tables[[name]],
    file.path(modelling_paths$tables, paste0("model_elastic_net_", name, ".csv")),
    na = "NA"
  )
}


# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("MODEL-03 ELASTIC-NET MULTINOMIAL\n")
cat("============================================================\n\n")

cat("Completed feature sets:",
    paste(sort(unique(fold_metrics$feature_set)), collapse = ", "), "\n\n")

cat("Mean (SD) across outer folds:\n")
print(
  summary_metrics |>
    select(feature_set, regime, macro_f1_mean, macro_f1_sd, accuracy_mean,
           balanced_accuracy_mean, top3_accuracy_mean, top5_accuracy_mean,
           mrr_mean),
  width = Inf
)

cat("\nTotal run time:", elapsed_minutes(run_started), "\n")

if (length(failed_sets)) {
  stop(
    "Feature set(s) failed and were not saved: ",
    paste(failed_sets, collapse = ", "),
    call. = FALSE
  )
}

cat("\nMODEL-03 PASSED\n")
