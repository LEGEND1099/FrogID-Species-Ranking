# MODEL-06: Probability Random Forest using ranger
#
# From the repository root (R 4.6.1 with renv):
#   Rscript R/modelling/06_random_forest.R M4 --benchmark
#   Rscript R/modelling/06_random_forest.R M4
#   Rscript R/modelling/06_random_forest.R M3  # optional coordinate contrast
#
# Uses the 242,600-record/18-class modelling cohort and saved frozen folds.
# For each regime x fold, candidates are fit ONLY on inner FIT rows;
# hyperparameters are selected on inner TUNE Macro-F1; the selected model
# is refit on FULL outer DEVELOPMENT and evaluated ONCE on outer ASSESSMENT.
#
# No automatic feature scaling/PCA is necessary for a tree-based model;
# no weighting, duplication, or synthetic resampling. Spatial folds keep
# 0.5-degree cells intact, but neighbouring cells may still be dependent.
# Latitude/longitude only appear in M4, not M3. Trees output class
# probabilities, suitable for the project's common ranking evaluator.
#
# Fixed forest size: 200 trees in tuning and final refits, deliberately
# bounded for reproducibility and the assignment computation budget.
# Tuned grid: mtry = 5 or 10; min.node.size = 5 or 20 (four candidates).
# The three seeds/outer folds and inner roles come from shared helpers.
#
# Git-trackable aggregate outputs:
#   outputs/tables/model_random_forest_{fold_metrics,summary,
#      class_metrics,tuning,selected,feature_importance}.csv
# Git-ignored event-level and complete intermediate results:
#   data/interim/modelling/oof_random_forest_<M>.rds
#   data/interim/modelling/random_forest_results_<M>.rds
#
# The impurity feature-importance ranking is DESCRIPTIVE and biased toward
# predictors with many possible splits; correlated BIO variables may share
# signal. Do not interpret as causal effect or unbiased feature attribution.

source("R/modelling/modelling_helpers.R")
suppressPackageStartupMessages({
  library(readr)
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop("Package ranger not installed. Run: renv::install('ranger', prompt=FALSE)",
         call. = FALSE)
  }
})

model_name <- "random_forest"
args <- commandArgs(trailingOnly = TRUE)
benchmark <- "--benchmark" %in% args
sets <- args[args != "--benchmark"]
if (length(sets) > 1L || (length(sets) == 1L && !sets[[1L]] %in% c("M3", "M4"))) {
  stop("Usage: Rscript R/modelling/06_random_forest.R [M3|M4] [--benchmark]",
       call. = FALSE)
}
feature_set <- if (length(sets)) sets[[1L]] else "M4"

n_trees <- 200L
mtry_grid <- c(5L, 10L)
node_grid <- c(5L, 20L)
tuning_grid <- expand.grid(
  mtry = mtry_grid,
  min_node_size = node_grid,
  KEEP.OUT.ATTRS = FALSE,
  stringsAsFactors = FALSE
)
regimes <- c("random", "spatial")

requested_threads <- suppressWarnings(as.integer(Sys.getenv("RF_THREADS", "4")))
rf_threads <- if (is.na(requested_threads) || requested_threads < 1L) 4L else requested_threads

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)
y <- cohort$scientificName
class_levels <- levels(y)
features <- feature_sets[[feature_set]]
stopifnot(nrow(cohort) == 242600L, length(class_levels) == 18L,
          length(features) == if (feature_set == "M4") 28L else 26L,
          !anyNA(cohort[features]))

elapsed <- function(started) as.numeric(difftime(Sys.time(), started, units = "secs"))

# The fixed integer seed is distinct for each regime, outer fold and
# candidate. Repeatability with the same ranger build/thread settings is
# expected; small differences may occur across platforms/implementations.
job_seed <- function(regime, k, candidate = 0L) {
  as.integer(modelling_seed + (if (regime == "random") 100L else 200L) +
               10L * k + candidate)
}

fit_rf <- function(train_rows, mtry, min_node_size, seed, trees = n_trees,
                   importance = "none") {
  stopifnot(length(train_rows) > 0L, all(table(y[train_rows]) > 0L))
  x <- as.data.frame(cohort[train_rows, features, drop = FALSE])
  ranger::ranger(
    x = x,
    y = y[train_rows],
    probability = TRUE,
    num.trees = as.integer(trees),
    mtry = as.integer(mtry),
    min.node.size = as.integer(min_node_size),
    splitrule = "gini",
    importance = importance,
    sample.fraction = 1,
    replace = TRUE,
    num.threads = rf_threads,
    seed = as.integer(seed),
    write.forest = TRUE,
    oob.error = FALSE,
    verbose = FALSE
  )
}

predict_prob <- function(forest, rows) {
  x <- as.data.frame(cohort[rows, features, drop = FALSE])
  prob <- as.matrix(
    predict(forest, data = x, type = "response",
            num.threads = rf_threads, verbose = FALSE)$predictions
  )
  if (!setequal(colnames(prob), class_levels)) {
    stop("Random-forest prediction classes do not match the 18-species vocabulary")
  }
  prob <- prob[, class_levels, drop = FALSE]
  if (!is.matrix(prob) || nrow(prob) != length(rows) ||
      any(!is.finite(prob)) || any(prob < -1e-12) ||
      any(prob > 1 + 1e-12) || max(abs(rowSums(prob) - 1)) > 1e-6) {
    stop("Random-forest prediction matrix contains invalid class probabilities")
  }
  prob
}

# Diagnose API compatibility, real full-sized training, and prediction time.
# Benchmark mode writes NOTHING and never evaluates an outer assessment fold.
if (benchmark) {
  k <- 1L
  regime <- "random"
  inner <- folds[["random_inner_1"]]
  fit_rows <- which(inner == "fit")
  tune_rows <- which(inner == "tune")
  query_rows <- head(tune_rows, 1500L)
  t0 <- Sys.time()
  forest <- fit_rf(
    train_rows = fit_rows, mtry = mtry_grid[[1L]],
    min_node_size = node_grid[[1L]],
    seed = job_seed(regime, k, 1L), trees = 40L
  )
  fit_seconds <- elapsed(t0)
  prob <- predict_prob(forest, query_rows)
  stopifnot(identical(colnames(prob), class_levels),
            nrow(prob) == length(query_rows))
  cat("\nRANDOM FOREST BENCHMARK PASSED\n")
  cat("Feature set:", feature_set, "\n")
  cat("Inner fit events:", length(fit_rows), "\n")
  cat("Inner tuning queries:", length(query_rows), "\n")
  cat("Trees in benchmark: 40 (full experiment: 200)\n")
  cat("Forest fitting seconds:", round(fit_seconds, 2), "\n")
  cat("Benchmark total seconds:", round(elapsed(t0), 2), "\n")
  cat("Threads:", rf_threads, "\n")
  cat("No model results written.\n")
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

    stopifnot(
      length(fit_rows) > 0L, length(tune_rows) > 0L,
      identical(which(inner == "assess"), assess_rows),
      identical(sort(c(fit_rows, tune_rows)), dev_rows),
      length(intersect(fit_rows, assess_rows)) == 0L,
      all(table(y[fit_rows]) > 0),
      all(table(y[dev_rows]) > 0)
    )

    message(sprintf("RF %s %s fold %d: tuning %d candidates started (%d threads)",
                    feature_set, regime, k, nrow(tuning_grid), rf_threads))

    candidates <- vector("list", nrow(tuning_grid))
    for (i in seq_len(nrow(tuning_grid))) {
      mtry_i <- as.integer(tuning_grid$mtry[[i]])
      node_i <- as.integer(tuning_grid$min_node_size[[i]])
      forest <- fit_rf(fit_rows, mtry_i, node_i,
                       seed = job_seed(regime, k, i))
      prob_tune <- predict_prob(forest, tune_rows)
      tune_eval <- evaluate_predictions(prob_tune, y[tune_rows])$overall
      candidates[[i]] <- tibble(
        mtry = mtry_i, min_node_size = node_i,
        num_trees = n_trees,
        tune_macro_f1 = tune_eval$macro_f1,
        tune_accuracy = tune_eval$accuracy,
        tune_mrr = tune_eval$mrr,
        tune_log_loss = tune_eval$log_loss
      )
      rm(forest, prob_tune)
      gc(verbose = FALSE)
      message(sprintf("RF %s %s fold %d: candidate %d/%d (mtry=%d, node=%d) inner Macro-F1=%.4f (%.1f s)",
                      feature_set, regime, k, i, nrow(tuning_grid), mtry_i,
                      node_i, tune_eval$macro_f1, elapsed(t0)))
    }

    tuning <- bind_rows(candidates)
    # Selection is based ONLY on the inner TUNE set.
    # Deterministic ties: smaller mtry, then larger minimum node size.
    best <- tuning |>
      arrange(desc(tune_macro_f1), mtry, desc(min_node_size)) |>
      slice(1L)

    # Refit on full outer development; assessment labels stay unseen.
    final_seed <- job_seed(regime, k, 9L)
    final_forest <- fit_rf(
      train_rows = dev_rows,
      mtry = best$mtry,
      min_node_size = best$min_node_size,
      seed = final_seed,
      importance = "impurity"
    )
    prob <- predict_prob(final_forest, assess_rows)
    assessment <- evaluate_predictions(prob, y[assess_rows])
    runtime <- elapsed(t0)

    id <- tibble(model = model_name, feature_set = feature_set,
                 regime = regime, fold = k)
    fold_metrics[[length(fold_metrics) + 1L]] <- bind_cols(
      id, assessment$overall, tibble(runtime_seconds = runtime)
    )
    class_metrics[[length(class_metrics) + 1L]] <- bind_cols(id, assessment$by_class)
    tuning_results[[length(tuning_results) + 1L]] <- bind_cols(id, tuning)
    selected_results[[length(selected_results) + 1L]] <- bind_cols(
      id,
      tibble(
        mtry_selected = as.integer(best$mtry),
        min_node_size_selected = as.integer(best$min_node_size),
        num_trees = n_trees,
        tune_macro_f1 = best$tune_macro_f1,
        fit_events = length(fit_rows), tune_events = length(tune_rows),
        development_events = length(dev_rows),
        assessment_events = length(assess_rows),
        seed = final_seed, threads = rf_threads,
        runtime_seconds = runtime
      )
    )

    imp <- final_forest$variable.importance
    stopifnot(length(imp) == length(features), setequal(names(imp), features))
    importance_results[[length(importance_results) + 1L]] <- bind_cols(
      id,
      tibble(feature = features,
             impurity_importance = as.numeric(imp[features]))
    )

    regime_predictions[[k]] <- list(row = assess_rows, prob = prob)
    message(sprintf("RF %s %s fold %d: mtry=%d node=%d, assessment Macro-F1=%.4f, top-3=%.4f (%.1f s)",
                    feature_set, regime, k, best$mtry,
                    best$min_node_size, assessment$overall$macro_f1,
                    assessment$overall$top3_accuracy, runtime))
    rm(final_forest, prob, tuning, best)
    gc(verbose = FALSE)
  }

  rows <- unlist(lapply(regime_predictions, `[[`, "row"), use.names = FALSE)
  all_probs <- do.call(rbind, lapply(regime_predictions, `[[`, "prob"))
  stopifnot(identical(sort(rows), seq_len(nrow(cohort))))
  all_probs <- all_probs[order(rows), , drop = FALSE]
  stopifnot(nrow(all_probs) == nrow(cohort),
            identical(colnames(all_probs), class_levels))
  predictions[[regime]] <- list(
    eventID = cohort$eventID,
    truth = y,
    fold = outer,
    prob = all_probs
  )
}

# Persist only after all outer jobs successfully finish.
results <- list(
  fold_metrics = bind_rows(fold_metrics),
  class_metrics = bind_rows(class_metrics),
  tuning = bind_rows(tuning_results),
  selected = bind_rows(selected_results),
  importance = bind_rows(importance_results)
)
stopifnot(
  nrow(results$fold_metrics) == 2L * n_outer_folds,
  nrow(results$class_metrics) == 2L * n_outer_folds * length(class_levels),
  nrow(results$tuning) == 2L * n_outer_folds * nrow(tuning_grid),
  nrow(results$selected) == 2L * n_outer_folds
)

dir.create(modelling_paths$model_outputs, recursive = TRUE, showWarnings = FALSE)
dir.create(modelling_paths$tables, recursive = TRUE, showWarnings = FALSE)
save_oof_predictions(predictions, model_name, feature_set)
saveRDS(results, file.path(modelling_paths$model_outputs,
                           paste0("random_forest_results_", feature_set, ".rds")))

# Collect successfully completed feature sets (M3 and/or M4), without
# destroying earlier results when another set is run.
completed_sets <- c("M3", "M4")
result_paths <- file.path(modelling_paths$model_outputs,
                         paste0("random_forest_results_", completed_sets, ".rds"))
result_paths <- result_paths[file.exists(result_paths)]
all_results <- lapply(result_paths, readRDS)
combine <- function(component) bind_rows(lapply(all_results, `[[`, component))
combined_folds <- combine("fold_metrics")
importance_summary <- combine("importance") |>
  group_by(model, feature_set, regime, feature) |>
  summarise(
    folds = n(),
    mean_impurity_importance = mean(impurity_importance),
    sd_impurity_importance = if (n() > 1L) sd(impurity_importance) else NA_real_,
    .groups = "drop"
  ) |>
  arrange(feature_set, regime, desc(mean_impurity_importance))

output_tables <- list(
  fold_metrics = combined_folds,
  summary = summarise_fold_metrics(combined_folds),
  class_metrics = combine("class_metrics"),
  tuning = combine("tuning"),
  selected = combine("selected"),
  feature_importance = importance_summary
)
for (name in names(output_tables)) {
  readr::write_csv(
    output_tables[[name]],
    file.path(modelling_paths$tables,
              paste0("model_random_forest_", name, ".csv")),
    na = "NA"
  )
}

cat("\nMODEL-06 RANDOM FOREST PASSED\n")
cat("Completed feature sets:",
    paste(sort(unique(combined_folds$feature_set)), collapse = ", "), "\n")
print(output_tables$summary |>
        select(model, feature_set, regime, macro_f1_mean, macro_f1_sd,
               accuracy_mean, top3_accuracy_mean, mrr_mean), width = Inf)
