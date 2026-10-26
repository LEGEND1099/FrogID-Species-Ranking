# MODEL-05: PCA + k-Nearest Neighbours (kNN)
#
# Run from repository root:
#   Rscript R/modelling/05_pca_knn.R M4 --benchmark  # quick timing probe (no outputs)
#   Rscript R/modelling/05_pca_knn.R M4              # core, random + spatial CV
#   Rscript R/modelling/05_pca_knn.R M3              # optional no-coordinate contrast
#
# Dataset, target levels, feature definitions, outer folds and inner fit/tune
# roles are provided by R/modelling/modelling_helpers.R. No fold recreation.
#
# Inside EACH outer fold:
#  1. Fit environmental standardisation + PCA, and scale seasonal/coordinate
#     features, using ONLY inner FIT observations.
#  2. Retain >=95% of environmental variance; tune nPC and k by inner TUNE
#     Macro-F1, using exact FNN kd-tree nearest-neighbour search.
#  3. Refit preprocessing on the FULL outer DEVELOPMENT observations, keeping
#     the tuned PC count (or more PCs if needed to retain >=95% of variance).
#  4. Predict once on the untouched outer ASSESSMENT observations.
#
# Euclidean distance uses whitened retained PCs (divide by fitted PC SD),
# plus individually standardised seasonal/coordinate features. This prevents
# high-variance PCs from dominating distance and is fixed before assessment.
# Natural observed class frequencies; NO resampling or class weights.
# Predictions use simple neighbour votes with uniform Dirichlet smoothing
# (0.1 pseudo-count per species) to avoid zero-valued probabilities. All 18
# class columns are present in the same order as other models. Log loss is
# descriptive only: these estimates are not separately calibrated.
#
# Outputs (only on successful completion of all six outer jobs):
#   outputs/tables/model_pca_knn_{fold_metrics,summary,class_metrics,tuning,selected}.csv
#   data/interim/modelling/pca_knn_results_<M>.rds     (Git-ignored)
#   data/interim/modelling/oof_pca_knn_<M>.rds         (Git-ignored)

source("R/modelling/modelling_helpers.R")
suppressPackageStartupMessages({
  library(readr)
  if (!requireNamespace("FNN", quietly = TRUE)) {
    stop("Package FNN is required. Run: renv::install('FNN')", call. = FALSE)
  }
})

model_name <- "pca_knn"
args <- commandArgs(trailingOnly = TRUE)
benchmark <- "--benchmark" %in% args
sets <- args[args != "--benchmark"]
if (length(sets) > 1L || (length(sets) == 1L && !sets[1] %in% c("M3", "M4"))) {
  stop("Usage: Rscript R/modelling/05_pca_knn.R [M3|M4] [--benchmark]", call. = FALSE)
}
feature_set <- if (length(sets)) sets[1] else "M4"

# Bounded, predeclared tuning search. The max-k search is reused for all k.
k_grid <- c(7L, 21L, 51L)
pc_offsets <- c(0L, 2L)   # from inner-fit 95%-variance count
smoothing <- 0.1
regimes <- c("random", "spatial")

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)
y <- cohort$scientificName
class_levels <- levels(y)
n_classes <- length(class_levels)
features <- feature_sets[[feature_set]]
env_cols <- intersect(features, environmental_features)
extra_cols <- setdiff(features, env_cols)
stopifnot(n_classes == 18L, length(env_cols) == 22L,
          length(extra_cols) == if (feature_set == "M4") 6L else 4L)

elapsed <- function(t0) as.numeric(difftime(Sys.time(), t0, units = "secs"))

# All learned preprocessing uses ONLY the supplied training indices.
fit_preprocessing <- function(train_rows) {
  env <- as.matrix(cohort[train_rows, env_cols, drop = FALSE])
  if (any(!is.finite(env)) || any(apply(env, 2L, sd) <= 0)) {
    stop("Nonfinite/constant environmental predictor in training rows")
  }
  pca <- stats::prcomp(env, center = TRUE, scale. = TRUE, retx = FALSE)
  variance <- cumsum(pca$sdev^2) / sum(pca$sdev^2)
  n95 <- which(variance >= 0.95)[1L]
  extra <- as.matrix(cohort[train_rows, extra_cols, drop = FALSE])
  extra_mean <- colMeans(extra)
  extra_sd <- apply(extra, 2L, sd)
  if (any(!is.finite(extra_sd)) || any(extra_sd <= 0)) {
    stop("Nonfinite/constant additional predictor in training rows")
  }
  list(pca = pca, variance = variance, n95 = n95,
       extra_mean = extra_mean, extra_sd = extra_sd)
}

transform_rows <- function(prep, rows, n_pcs) {
  if (n_pcs < 1L || n_pcs > ncol(prep$pca$rotation) ||
      any(prep$pca$sdev[seq_len(n_pcs)] < 1e-8)) {
    stop("Invalid PCA dimension or nearly zero retained PC variance")
  }
  env <- as.matrix(cohort[rows, env_cols, drop = FALSE])
  pcs <- predict(prep$pca, newdata = env)[, seq_len(n_pcs), drop = FALSE]
  # Whitening with training-PC standard deviations, NOT query statistics.
  pcs <- sweep(pcs, 2L, prep$pca$sdev[seq_len(n_pcs)], "/")
  extra <- scale(as.matrix(cohort[rows, extra_cols, drop = FALSE]),
                 center = prep$extra_mean, scale = prep$extra_sd)
  x <- cbind(pcs, extra)
  storage.mode(x) <- "double"
  if (any(!is.finite(x))) stop("Nonfinite preprocessed inputs")
  x
}

# For fixed neighbours, accumulate votes only once up to max(k_grid).
# Returns a named list of n_query x 18 probability matrices.
probability_grid <- function(neighbour_index, train_labels, ks) {
  stopifnot(is.matrix(neighbour_index),
            max(ks) <= ncol(neighbour_index),
            all(neighbour_index >= 1L),
            all(neighbour_index <= length(train_labels)))
  n <- nrow(neighbour_index)
  votes <- matrix(0L, nrow = n, ncol = n_classes,
                  dimnames = list(NULL, class_levels))
  row_index <- seq_len(n)
  output <- list()
  for (j in seq_len(max(ks))) {
    locations <- cbind(row_index, train_labels[neighbour_index[, j]])
    votes[locations] <- votes[locations] + 1L
    if (j %in% ks) {
      probs <- (votes + smoothing) / (j + n_classes * smoothing)
      colnames(probs) <- class_levels
      stopifnot(all(is.finite(probs)), all(probs > 0),
                max(abs(rowSums(probs) - 1)) < 1e-10)
      output[[as.character(j)]] <- probs
    }
  }
  output
}

find_neighbours <- function(train_x, query_x, k) {
  stopifnot(is.matrix(train_x), is.matrix(query_x),
            ncol(train_x) == ncol(query_x),
            nrow(train_x) > k)
  FNN::knnx.index(data = train_x, query = query_x,
                  k = k, algorithm = "kd_tree")
}

# The benchmark uses *only inner fit and tune* rows of random fold 1.
# It measures a genuine full-size training index with 300 held-out queries,
# creates no result files, and never accesses outer assessment rows.
if (benchmark) {
  k <- 1L
  inner <- folds[[paste0("random_inner_", k)]]
  fit_rows <- which(inner == "fit")
  tune_rows <- head(which(inner == "tune"), 300L)
  t0 <- Sys.time()
  prep <- fit_preprocessing(fit_rows)
  npc <- min(ncol(prep$pca$rotation), prep$n95 + max(pc_offsets))
  train_x <- transform_rows(prep, fit_rows, npc)
  tune_x <- transform_rows(prep, tune_rows, npc)
  t_search <- Sys.time()
  neighbours <- find_neighbours(train_x, tune_x, max(k_grid))
  stopifnot(nrow(neighbours) == length(tune_rows))
  cat("PCA-kNN benchmark PASSED\n")
  cat("Feature set:", feature_set, "\n")
  cat("Inner fit rows:", length(fit_rows), "\n")
  cat("Inner tune queries:", length(tune_rows), "\n")
  cat("PCA dimensions:", npc, "\n")
  cat("Max k:", max(k_grid), "\n")
  cat("Search seconds:", round(elapsed(t_search), 2), "\n")
  cat("Total seconds:", round(elapsed(t0), 2), "\n")
  cat("No model outputs written.\n")
  quit(save = "no", status = 0L)
}

fold_metrics <- list()
class_metrics <- list()
tuning_results <- list()
selected_results <- list()
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
    stopifnot(identical(which(inner == "assess"), assess_rows),
              all(inner[dev_rows] %in% c("fit", "tune")),
              length(fit_rows) > max(k_grid), length(tune_rows) > 0L,
              length(intersect(fit_rows, assess_rows)) == 0L)
    message(sprintf("PCA-kNN %s %s fold %d: tuning started", feature_set, regime, k))

    prep <- fit_preprocessing(fit_rows)
    npc_candidates <- sort(unique(pmin(ncol(prep$pca$rotation),
                                       prep$n95 + pc_offsets)))
    tuning <- list()
    for (npc in npc_candidates) {
      x_fit <- transform_rows(prep, fit_rows, npc)
      x_tune <- transform_rows(prep, tune_rows, npc)
      neigh <- find_neighbours(x_fit, x_tune, max(k_grid))
      probs <- probability_grid(neigh, as.integer(y[fit_rows]), k_grid)
      for (kn in k_grid) {
        metrics <- evaluate_predictions(probs[[as.character(kn)]],
                                         y[tune_rows])$overall
        tuning[[length(tuning) + 1L]] <- tibble(
          n_pcs = as.integer(npc), k = as.integer(kn),
          variance_explained = prep$variance[npc],
          tune_macro_f1 = metrics$macro_f1,
          tune_accuracy = metrics$accuracy,
          tune_mrr = metrics$mrr
        )
      }
      rm(x_fit, x_tune, neigh, probs)
      gc(verbose = FALSE)
      message(sprintf("PCA-kNN %s %s fold %d: tuned %d PCs (%.1f s)",
                      feature_set, regime, k, npc, elapsed(t0)))
    }
    tuning <- bind_rows(tuning)
    best <- tuning |>
      arrange(desc(tune_macro_f1), n_pcs, k) |>
      slice(1L)

    # Refit PCA, scaling and neighbourhood representation on development ONLY.
    dev_prep <- fit_preprocessing(dev_rows)
    final_npc <- max(as.integer(best$n_pcs), dev_prep$n95)
    final_k <- as.integer(best$k)
    x_dev <- transform_rows(dev_prep, dev_rows, final_npc)
    x_assess <- transform_rows(dev_prep, assess_rows, final_npc)
    final_neigh <- find_neighbours(x_dev, x_assess, final_k)
    prob <- probability_grid(final_neigh, as.integer(y[dev_rows]), final_k)[[as.character(final_k)]]
    result <- evaluate_predictions(prob, y[assess_rows])
    runtime <- elapsed(t0)

    id <- tibble(model = model_name, feature_set = feature_set,
                 regime = regime, fold = k)
    fold_metrics[[length(fold_metrics) + 1L]] <- bind_cols(
      id, result$overall, tibble(runtime_seconds = runtime))
    class_metrics[[length(class_metrics) + 1L]] <- bind_cols(id, result$by_class)
    tuning_results[[length(tuning_results) + 1L]] <- bind_cols(id, tuning)
    selected_results[[length(selected_results) + 1L]] <- bind_cols(
      id, tibble(n_pcs_tuned = as.integer(best$n_pcs),
                 n_pcs_refit = final_npc, k_selected = final_k,
                 variance_explained_inner = best$variance_explained,
                 variance_explained_refit = dev_prep$variance[final_npc],
                 tune_macro_f1 = best$tune_macro_f1,
                 fit_events = length(fit_rows), tune_events = length(tune_rows),
                 development_events = length(dev_rows),
                 assessment_events = length(assess_rows),
                 runtime_seconds = runtime))
    regime_predictions[[k]] <- list(row = assess_rows, prob = prob)
    message(sprintf("PCA-kNN %s %s fold %d: %d PCs, k=%d, assessment Macro-F1=%.4f (%.1f s)",
                    feature_set, regime, k, final_npc, final_k,
                    result$overall$macro_f1, runtime))
    rm(prep, tuning, best, dev_prep, x_dev, x_assess, final_neigh, prob)
    gc(verbose = FALSE)
  }

  rows <- unlist(lapply(regime_predictions, `[[`, "row"))
  probs <- do.call(rbind, lapply(regime_predictions, `[[`, "prob"))
  stopifnot(identical(sort(rows), seq_len(nrow(cohort))))
  probs <- probs[order(rows), , drop = FALSE]
  stopifnot(nrow(probs) == nrow(cohort),
            identical(colnames(probs), class_levels),
            all(is.finite(probs)),
            max(abs(rowSums(probs) - 1)) < 1e-10)
  predictions[[regime]] <- list(eventID = cohort$eventID, truth = y,
                                fold = outer, prob = probs)
}

# Persist only if every fold completed. Save out-of-fold arrays locally.
results <- list(fold_metrics = bind_rows(fold_metrics),
                class_metrics = bind_rows(class_metrics),
                tuning = bind_rows(tuning_results),
                selected = bind_rows(selected_results))
stopifnot(nrow(results$fold_metrics) == 2L * n_outer_folds,
          nrow(results$class_metrics) == 2L * n_outer_folds * n_classes)
save_oof_predictions(predictions, model_name, feature_set)
saveRDS(results, file.path(modelling_paths$model_outputs,
                           paste0("pca_knn_results_", feature_set, ".rds")))

# As with elastic-net and PCA-LDA, assemble CSVs from completed feature sets.
existing_sets <- c("M3", "M4")
result_paths <- file.path(modelling_paths$model_outputs,
                         paste0("pca_knn_results_", existing_sets, ".rds"))
result_paths <- result_paths[file.exists(result_paths)]
all_results <- lapply(result_paths, readRDS)
combine <- function(part) bind_rows(lapply(all_results, `[[`, part))
combined_folds <- combine("fold_metrics")
output_tables <- list(
  fold_metrics = combined_folds,
  summary = summarise_fold_metrics(combined_folds),
  class_metrics = combine("class_metrics"),
  tuning = combine("tuning"),
  selected = combine("selected")
)
for (name in names(output_tables)) {
  readr::write_csv(output_tables[[name]],
                   file.path(modelling_paths$tables,
                             paste0("model_pca_knn_", name, ".csv")),
                   na = "NA")
}
cat("\nMODEL-05 PCA-kNN PASSED\n")
cat("Completed feature sets:",
    paste(sort(unique(combined_folds$feature_set)), collapse = ", "), "\n")
print(output_tables$summary |>
        select(model, feature_set, regime, macro_f1_mean, macro_f1_sd,
               accuracy_mean, top3_accuracy_mean, mrr_mean), width = Inf)
