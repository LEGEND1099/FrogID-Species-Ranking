# MODEL-04: PCA + Linear Discriminant Analysis (LDA)
#
# Run from the repository root:
#   Rscript R/modelling/04_pca_lda.R         # M4, random and spatial (core)
#   Rscript R/modelling/04_pca_lda.R M3      # optional environment-only comparison
#
# Uses the shared 242,600-event cohort, 18 classes, frozen outer folds,
# frozen inner fit/tune roles, and the same evaluator as elastic-net.
# No data/fold regeneration; no sampling, weighting, or leakage.
#
# Pipeline per outer fold:
#  1. Fit environmental scaling and PCA on INNER FIT rows only.
#  2. Tune number of PCs (>=95% inner-fit environmental variance) on
#     INNER TUNE macro-F1. Retain all season and optional coordinate inputs.
#  3. Refit preprocessing and LDA on FULL OUTER DEVELOPMENT rows.
#  4. Predict the untouched OUTER ASSESSMENT fold exactly once.
#
# Model files (ignored by Git):
#   data/interim/modelling/oof_pca_lda_<M>.rds
#   data/interim/modelling/pca_lda_results_<M>.rds
# Aggregate outputs (Git-trackable):
#   outputs/tables/model_pca_lda_{fold_metrics,summary,class_metrics,tuning,selected}.csv

source("R/modelling/modelling_helpers.R")

suppressPackageStartupMessages({
  library(readr)
  if (!requireNamespace("MASS", quietly = TRUE)) {
    stop("MASS is required for PCA-LDA; install MASS before proceeding.")
  }
})

model_name <- "pca_lda"
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) == 1L && !args[1] %in% c("M3", "M4"))) {
  stop("Usage: Rscript R/modelling/04_pca_lda.R [M3|M4]", call. = FALSE)
}
feature_set <- if (length(args)) args[1] else "M4"
regimes <- c("random", "spatial")

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)
y <- cohort$scientificName
class_levels <- levels(y)
features <- feature_sets[[feature_set]]

# PCA handles 21 climate variables plus elevation (22 predictors).
# Non-environmental predictors (cyclic season; optionally lat/lon) are
# appended separately after training-only standardisation.
env_cols <- intersect(features, environmental_features)
extra_cols <- setdiff(features, env_cols)
stopifnot(length(env_cols) == 22L,
          length(extra_cols) == if (feature_set == "M4") 6L else 4L)

# Fit all preprocessing using TRAINING ROWS ONLY.
fit_preprocessing <- function(train_rows) {
  x_env <- as.matrix(cohort[train_rows, env_cols, drop = FALSE])
  if (anyNA(x_env) || any(!is.finite(x_env))) stop("Invalid environmental training data")
  if (any(apply(x_env, 2L, sd) <= 0)) stop("Constant environmental predictor in training data")

  pca <- stats::prcomp(x_env, center = TRUE, scale. = TRUE, retx = FALSE)
  explained <- cumsum(pca$sdev^2) / sum(pca$sdev^2)
  n95 <- which(explained >= 0.95)[1L]

  x_extra <- as.matrix(cohort[train_rows, extra_cols, drop = FALSE])
  extra_mean <- colMeans(x_extra)
  extra_sd <- apply(x_extra, 2L, sd)
  if (any(!is.finite(extra_sd)) || any(extra_sd <= 0)) {
    stop("Constant/nonfinite extra predictor in training data")
  }

  list(pca = pca, explained = explained, n95 = n95,
       extra_mean = extra_mean, extra_sd = extra_sd)
}

# Apply a fitted transform to any rows. Does not learn from these rows.
transform_rows <- function(prep, rows, n_pcs) {
  pcs <- predict(prep$pca,
                 newdata = as.matrix(cohort[rows, env_cols, drop = FALSE]))[
                   , seq_len(n_pcs), drop = FALSE]
  extra <- scale(as.matrix(cohort[rows, extra_cols, drop = FALSE]),
                 center = prep$extra_mean, scale = prep$extra_sd)
  design <- cbind(pcs, extra)
  if (any(!is.finite(design))) stop("Nonfinite transformed inputs")
  design
}

predict_probabilities <- function(fit, design) {
  prob <- as.matrix(predict(fit, newdata = design)$posterior)
  if (!identical(colnames(prob), class_levels) ||
      any(!is.finite(prob)) || any(prob < 0) || any(prob > 1 + 1e-8) ||
      any(abs(rowSums(prob) - 1) > 1e-6)) {
    stop("LDA returned invalid probabilities or inconsistent class order")
  }
  prob
}

fold_metrics <- list()
class_metrics <- list()
tuning_results <- list()
selected_results <- list()
predictions <- list()

for (regime in regimes) {
  outer <- folds[[paste0(regime, "_fold")]]
  regime_predictions <- list()

  for (k in seq_len(n_outer_folds)) {
    started <- Sys.time()
    inner <- folds[[paste0(regime, "_inner_", k)]]
    fit_rows <- which(inner == "fit")
    tune_rows <- which(inner == "tune")
    dev_rows <- which(outer != k)
    assess_rows <- which(outer == k)

    stopifnot(length(fit_rows) > 0L, length(tune_rows) > 0L,
              length(assess_rows) > 0L,
              identical(which(inner == "assess"), assess_rows),
              length(intersect(fit_rows, assess_rows)) == 0L)

    message(sprintf("PCA-LDA %s %s fold %d: fit/tune started",
                    feature_set, regime, k))

    # One inner-fit PCA, three modest predeclared candidate dimensions.
    inner_prep <- fit_preprocessing(fit_rows)
    nmax <- ncol(inner_prep$pca$rotation)
    candidate_pcs <- sort(unique(pmin(nmax,
                                      inner_prep$n95 + c(0L, 2L, 4L))))
    # Build once with the maximum PCs; use prefixes for each candidate.
    train_all <- transform_rows(inner_prep, fit_rows, max(candidate_pcs))
    tune_all <- transform_rows(inner_prep, tune_rows, max(candidate_pcs))

    candidates <- list()
    for (n_pc in candidate_pcs) {
      use_cols <- c(seq_len(n_pc),
                    ncol(train_all) - length(extra_cols) + seq_along(extra_cols))
      model <- MASS::lda(x = train_all[, use_cols, drop = FALSE],
                         grouping = y[fit_rows], tol = 1e-4)
      tune_prob <- predict_probabilities(model,
                                         tune_all[, use_cols, drop = FALSE])
      metrics <- evaluate_predictions(tune_prob, y[tune_rows])$overall
      candidates[[length(candidates) + 1L]] <- tibble(
        n_pcs = n_pc,
        variance_explained = inner_prep$explained[n_pc],
        tune_macro_f1 = metrics$macro_f1,
        tune_accuracy = metrics$accuracy,
        tune_mrr = metrics$mrr
      )
    }
    tuning <- bind_rows(candidates)
    # Highest tuning Macro-F1; ties favour fewer PCs.
    best <- tuning |>
      arrange(desc(tune_macro_f1), n_pcs) |>
      slice(1L)

    # Outer refit: ONLY the full development portion is used.
    dev_prep <- fit_preprocessing(dev_rows)
    # At least 95% of environmental variance is preserved in both fits.
    final_n_pcs <- max(as.integer(best$n_pcs), dev_prep$n95)
    train_final <- transform_rows(dev_prep, dev_rows, final_n_pcs)
    assess_final <- transform_rows(dev_prep, assess_rows, final_n_pcs)
    final_fit <- MASS::lda(x = train_final,
                           grouping = y[dev_rows], tol = 1e-4)
    prob <- predict_probabilities(final_fit, assess_final)
    result <- evaluate_predictions(prob, y[assess_rows])
    runtime <- as.numeric(difftime(Sys.time(), started, units = "secs"))

    id <- tibble(model = model_name, feature_set = feature_set,
                 regime = regime, fold = k)
    fold_metrics[[length(fold_metrics) + 1L]] <- bind_cols(
      id, result$overall, tibble(runtime_seconds = runtime))
    class_metrics[[length(class_metrics) + 1L]] <- bind_cols(
      id, result$by_class)
    tuning_results[[length(tuning_results) + 1L]] <- bind_cols(id, tuning)
    selected_results[[length(selected_results) + 1L]] <- bind_cols(
      id, tibble(n_pcs_tuned = best$n_pcs,
                 n_pcs_refit = final_n_pcs,
                 variance_explained_inner = best$variance_explained,
                 variance_explained_refit = dev_prep$explained[final_n_pcs],
                 tune_macro_f1 = best$tune_macro_f1,
                 fit_events = length(fit_rows),
                 tune_events = length(tune_rows),
                 development_events = length(dev_rows),
                 assessment_events = length(assess_rows),
                 runtime_seconds = runtime))
    regime_predictions[[k]] <- list(row = assess_rows, prob = prob)

    message(sprintf("PCA-LDA %s %s fold %d: PCs %d, macro-F1 %.4f, %.1f s",
                    feature_set, regime, k, final_n_pcs,
                    result$overall$macro_f1, runtime))
    rm(inner_prep, train_all, tune_all, dev_prep, train_final,
       assess_final, final_fit, prob)
    gc(verbose = FALSE)
  }

  # Reassemble in original cohort order; every row predicted exactly once.
  rows <- unlist(lapply(regime_predictions, `[[`, "row"))
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

# Only save after all six fold jobs succeed.
results <- list(
  fold_metrics = bind_rows(fold_metrics),
  class_metrics = bind_rows(class_metrics),
  tuning = bind_rows(tuning_results),
  selected = bind_rows(selected_results)
)
stopifnot(nrow(results$fold_metrics) == 2L * n_outer_folds,
          nrow(results$class_metrics) == 2L * n_outer_folds * length(class_levels))

save_oof_predictions(predictions, model_name, feature_set)
saveRDS(results, file.path(modelling_paths$model_outputs,
                           paste0("pca_lda_results_", feature_set, ".rds")))

# Rebuild summary files from successfully completed feature sets.
existing_sets <- c("M3", "M4")
result_paths <- file.path(modelling_paths$model_outputs,
                         paste0("pca_lda_results_", existing_sets, ".rds"))
result_paths <- result_paths[file.exists(result_paths)]
all_results <- lapply(result_paths, readRDS)
combine <- function(name) bind_rows(lapply(all_results, `[[`, name))
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
                             paste0("model_pca_lda_", name, ".csv")), na = "NA")
}

cat("\nMODEL-04 PCA-LDA PASSED\n")
cat("Completed feature sets:",
    paste(sort(unique(combined_folds$feature_set)), collapse = ", "), "\n")
print(output_tables$summary |>
        select(model, feature_set, regime, macro_f1_mean, macro_f1_sd,
               accuracy_mean, top3_accuracy_mean, mrr_mean), width = Inf)
