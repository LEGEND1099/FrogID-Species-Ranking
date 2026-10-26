# MODEL-01: Shared outer and inner fold assignments
#
# Purpose:
# Build, verify and save the fixed fold assignment used by every model family
# so that all models and feature groups are compared on identical splits.
#
# Outer validation (docs/eda-10-modeling-handoff.md, section 7):
# - random:  3-fold class-stratified event-level CV;
# - spatial: 3-fold CV grouped by 0.5-degree cells (no cell split).
#
# Inner tuning split (section 8): within each outer development set, an
# 80/20 "fit"/"tune" split that follows the outer regime's grouping logic
# (stratified for random; whole 0.5-degree cells for spatial).
#
# Outputs:
#   data/processed/frog_modelling_folds.rds   (event-level; shared with team)
#   outputs/tables/model_fold_summary.csv
#   outputs/tables/model_fold_class_counts.csv
#   outputs/tables/model_inner_split_summary.csv
#
# Public tables contain aggregate counts only: no event IDs, cell IDs or
# coordinates.

source("R/modelling/modelling_helpers.R")

suppressPackageStartupMessages({
  library(readr)
  library(tidyr)
})

cohort <- load_modelling_cohort()
y <- cohort$scientificName
cell_id <- spatial_cell_id(cohort$decimalLongitude, cohort$decimalLatitude)


# -------------------------------------------------------------------------
# 1. Outer folds
# -------------------------------------------------------------------------

random_fold <- assign_stratified_folds(
  y,
  k = n_outer_folds,
  seed = modelling_seed
)

spatial_fold <- assign_groups_balanced(
  group = cell_id,
  y = y,
  shares = rep(1 / n_outer_folds, n_outer_folds)
)

folds <- tibble(
  eventID = cohort$eventID,
  scientificName = y,
  cell_id_05 = cell_id,
  random_fold = random_fold,
  spatial_fold = spatial_fold
)


# -------------------------------------------------------------------------
# 2. Inner fit/tune splits inside each outer development set
# -------------------------------------------------------------------------

for (k in seq_len(n_outer_folds)) {

  # Random regime: class-stratified split of the development rows.
  role <- rep("assess", nrow(folds))
  dev <- which(folds$random_fold != k)
  role[dev] <- assign_stratified_split(
    y[dev],
    tune_share = inner_tune_share,
    seed = modelling_seed + 100L + k
  )
  folds[[paste0("random_inner_", k)]] <- role

  # Spatial regime: whole development cells go to fit or tune.
  role <- rep("assess", nrow(folds))
  dev <- which(folds$spatial_fold != k)
  part <- assign_groups_balanced(
    group = cell_id[dev],
    y = y[dev],
    shares = c(1 - inner_tune_share, inner_tune_share)
  )
  role[dev] <- c("fit", "tune")[part]
  folds[[paste0("spatial_inner_", k)]] <- role
}


# -------------------------------------------------------------------------
# 3. Verification
# -------------------------------------------------------------------------

all_classes <- levels(y)

classes_present <- function(rows) {
  all(all_classes %in% as.character(y[rows]))
}

for (regime in c("random", "spatial")) {

  outer <- folds[[paste0(regime, "_fold")]]
  stopifnot(all(outer %in% seq_len(n_outer_folds)))

  for (k in seq_len(n_outer_folds)) {

    inner <- folds[[paste0(regime, "_inner_", k)]]

    stopifnot(
      # Every class in every outer assessment and development set.
      classes_present(outer == k),
      classes_present(outer != k),
      # Inner roles partition exactly the outer development set.
      identical(inner == "assess", outer == k),
      all(inner[outer != k] %in% c("fit", "tune")),
      # Every class in both inner parts.
      classes_present(inner == "fit"),
      classes_present(inner == "tune")
    )
  }
}

# No 0.5-degree cell may span outer spatial folds or inner spatial parts.
stopifnot(
  all(tapply(folds$spatial_fold, folds$cell_id_05, n_distinct) == 1L)
)

for (k in seq_len(n_outer_folds)) {
  inner <- folds[[paste0("spatial_inner_", k)]]
  dev <- inner != "assess"
  stopifnot(
    all(tapply(inner[dev], folds$cell_id_05[dev], n_distinct) == 1L)
  )
}


# -------------------------------------------------------------------------
# 4. Aggregate summaries
# -------------------------------------------------------------------------

outer_long <- folds |>
  select(scientificName, cell_id_05, random_fold, spatial_fold) |>
  pivot_longer(
    c(random_fold, spatial_fold),
    names_to = "regime",
    values_to = "fold"
  ) |>
  mutate(regime = sub("_fold$", "", regime))

fold_class_counts <- outer_long |>
  count(regime, fold, scientificName, name = "assessment_events") |>
  complete(regime, fold, scientificName, fill = list(assessment_events = 0L)) |>
  group_by(regime, scientificName) |>
  mutate(
    class_total = sum(assessment_events),
    development_events = class_total - assessment_events,
    assessment_share_percent = 100 * assessment_events / class_total
  ) |>
  ungroup() |>
  select(-class_total) |>
  arrange(regime, fold, scientificName)

fold_summary <- outer_long |>
  group_by(regime, fold) |>
  summarise(
    assessment_events = n(),
    assessment_cells = n_distinct(cell_id_05),
    .groups = "drop"
  ) |>
  mutate(
    development_events = nrow(folds) - assessment_events,
    assessment_share_percent = 100 * assessment_events / nrow(folds)
  ) |>
  left_join(
    fold_class_counts |>
      group_by(regime, fold) |>
      summarise(
        assessment_classes = sum(assessment_events > 0L),
        min_class_assessment_events = min(assessment_events),
        min_class_development_events = min(development_events),
        min_class_assessment_share_percent = min(assessment_share_percent),
        max_class_assessment_share_percent = max(assessment_share_percent),
        .groups = "drop"
      ),
    by = c("regime", "fold")
  )

inner_split_summary <- bind_rows(lapply(
  c("random", "spatial"),
  function(regime) {
    bind_rows(lapply(seq_len(n_outer_folds), function(k) {
      role <- folds[[paste0(regime, "_inner_", k)]]
      tibble(
        regime = regime,
        outer_fold = k,
        fit_events = sum(role == "fit"),
        tune_events = sum(role == "tune"),
        tune_share_percent =
          100 * sum(role == "tune") / sum(role != "assess"),
        min_class_fit_events =
          min(table(y[role == "fit"])),
        min_class_tune_events =
          min(table(y[role == "tune"]))
      )
    }))
  }
))


# -------------------------------------------------------------------------
# 5. Save
# -------------------------------------------------------------------------

attr(folds, "created_by") <- "R/modelling/01_build_folds.R"
attr(folds, "seed") <- modelling_seed
attr(folds, "spatial_cell_degrees") <- spatial_cell_degrees
attr(folds, "inner_tune_share") <- inner_tune_share

saveRDS(folds, modelling_paths$folds)

dir.create(modelling_paths$tables, recursive = TRUE, showWarnings = FALSE)

write_csv(fold_summary, "outputs/tables/model_fold_summary.csv", na = "NA")
write_csv(fold_class_counts, "outputs/tables/model_fold_class_counts.csv", na = "NA")
write_csv(inner_split_summary, "outputs/tables/model_inner_split_summary.csv", na = "NA")


# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("MODEL-01 FOLD ASSIGNMENT\n")
cat("============================================================\n\n")

cat("Cohort:", nrow(folds), "complete-case events;",
    nlevels(y), "classes;",
    n_distinct(folds$cell_id_05), "occupied 0.5-degree cells\n\n")

cat("Outer folds:\n")
print(fold_summary, width = Inf)

cat("\nInner fit/tune splits:\n")
print(inner_split_summary, width = Inf)

cat("\nMODEL-01 PASSED\n")
cat("All 18 classes present in every outer and inner partition;",
    "no 0.5-degree cell is split.\n")
cat("Saved:", modelling_paths$folds, "\n")
