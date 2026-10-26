# MODEL-02: M0 species-prevalence baseline
#
# Purpose:
# No-context reference model. Within each outer fold, every assessment event
# receives the same ranking: species ordered by their prevalence in that
# fold's development data (inner fit + tune). Assessment-fold prevalence is
# never used.
#
# Any contextual model must beat this baseline to show that season,
# environment or geography add ranking information beyond class frequency.
# Note that M0 always predicts the most common development-fold species, so
# its Macro-F1 is low by construction while Top-k can look high: the five
# most frequent species account for about 72% of events.
#
# Outputs:
#   outputs/tables/model_prevalence_fold_metrics.csv
#   outputs/tables/model_prevalence_summary.csv
#   outputs/tables/model_prevalence_class_metrics.csv
#   data/interim/modelling/oof_prevalence_M0.rds   (event-level; ignored)

source("R/modelling/modelling_helpers.R")

suppressPackageStartupMessages({
  library(readr)
})

model_name <- "prevalence"
feature_set <- "M0"

cohort <- load_modelling_cohort()
folds <- load_modelling_folds(cohort)

y <- cohort$scientificName
class_levels <- levels(y)


# -------------------------------------------------------------------------
# Fit and evaluate within each outer fold
# -------------------------------------------------------------------------

fold_metrics <- list()
class_metrics <- list()
predictions <- list()

for (regime in c("random", "spatial")) {

  outer <- folds[[paste0(regime, "_fold")]]
  regime_predictions <- list()

  for (k in seq_len(n_outer_folds)) {

    development <- outer != k
    assessment <- outer == k

    # "Fit": development-fold class shares only.
    prevalence <- as.numeric(table(y[development])) / sum(development)
    names(prevalence) <- class_levels

    prob <- matrix(
      prevalence,
      nrow = sum(assessment),
      ncol = length(class_levels),
      byrow = TRUE,
      dimnames = list(NULL, class_levels)
    )

    result <- evaluate_predictions(prob, y[assessment])

    fold_metrics[[length(fold_metrics) + 1L]] <- tibble(
      model = model_name,
      feature_set = feature_set,
      regime = regime,
      fold = k,
      top_ranked_species = class_levels[which.max(prevalence)]
    ) |>
      bind_cols(result$overall)

    class_metrics[[length(class_metrics) + 1L]] <- tibble(
      model = model_name,
      feature_set = feature_set,
      regime = regime,
      fold = k
    ) |>
      bind_cols(result$by_class)

    regime_predictions[[k]] <- list(
      row = which(assessment),
      prob = prob
    )
  }

  # Reassemble out-of-fold predictions in cohort row order.
  rows <- unlist(lapply(regime_predictions, `[[`, "row"))
  prob <- do.call(rbind, lapply(regime_predictions, `[[`, "prob"))
  prob <- prob[order(rows), , drop = FALSE]

  predictions[[regime]] <- list(
    eventID = cohort$eventID,
    truth = y,
    fold = outer,
    prob = prob
  )
}

fold_metrics <- bind_rows(fold_metrics)
class_metrics <- bind_rows(class_metrics)
summary_metrics <- summarise_fold_metrics(fold_metrics)


# -------------------------------------------------------------------------
# Sanity checks
# -------------------------------------------------------------------------

stopifnot(
  nrow(fold_metrics) == 2L * n_outer_folds,
  # A constant ranking predicts a single class in every fold.
  all(fold_metrics$classes_predicted == 1L),
  # Every event is predicted exactly once per regime.
  all(vapply(predictions, function(p) nrow(p$prob), integer(1)) == nrow(cohort))
)


# -------------------------------------------------------------------------
# Save
# -------------------------------------------------------------------------

write_csv(
  fold_metrics,
  file.path(modelling_paths$tables, "model_prevalence_fold_metrics.csv"),
  na = "NA"
)

write_csv(
  summary_metrics,
  file.path(modelling_paths$tables, "model_prevalence_summary.csv"),
  na = "NA"
)

write_csv(
  class_metrics,
  file.path(modelling_paths$tables, "model_prevalence_class_metrics.csv"),
  na = "NA"
)

save_oof_predictions(predictions, model_name, feature_set)


# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("MODEL-02 M0 PREVALENCE BASELINE\n")
cat("============================================================\n\n")

cat("Fold-level metrics:\n")
print(
  fold_metrics |>
    select(regime, fold, n, top_ranked_species, macro_f1, accuracy,
           balanced_accuracy, top3_accuracy, top5_accuracy, mrr, log_loss),
  width = Inf
)

cat("\nMean (SD) across outer folds:\n")
print(summary_metrics, width = Inf)

cat("\nMODEL-02 PASSED\n")
