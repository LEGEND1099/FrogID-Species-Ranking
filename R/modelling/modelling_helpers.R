# Shared modelling helpers
#
# Purpose:
# Single source of truth for the modelling cohort, feature groups (M0-M4),
# 0.5-degree spatial cells and fold-assignment utilities used by every
# model family. Source this file from the repository root.
#
# Decisions implemented here follow docs/eda-10-modeling-handoff.md
# (origin/eda) and the Stage 1 submission:
# - common complete-case cohort of 242,600 primary events;
# - cyclic seasonal encoding only (no raw month/day_of_year, no year);
# - EPBC, QC, privacy and observer fields never enter a predictor matrix.

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# -------------------------------------------------------------------------
# Paths and constants
# -------------------------------------------------------------------------

modelling_paths <- list(
  primary = "data/processed/frog_primary_multiclass.rds",
  folds = "data/processed/frog_modelling_folds.rds",
  model_outputs = "data/interim/modelling",
  tables = "outputs/tables",
  figures = "outputs/figures"
)

modelling_seed <- 5003L
n_outer_folds <- 3L
inner_tune_share <- 0.2
spatial_cell_degrees <- 0.5

expected_primary_rows <- 247406L
expected_cohort_rows <- 242600L
expected_classes <- 18L


# -------------------------------------------------------------------------
# Feature groups
# -------------------------------------------------------------------------

geographic_features <- c(
  "decimalLatitude",
  "decimalLongitude"
)

seasonal_features <- c(
  "month_sin",
  "month_cos",
  "day_of_year_sin",
  "day_of_year_cos"
)

climate_features <- c(
  paste0("BIO", 1:19),
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

environmental_features <- c(climate_features, "elevation")

# Certified 30-column whitelist from data preparation, in stored order.
certified_predictors <- c(
  geographic_features,
  "month",
  "day_of_year",
  seasonal_features,
  paste0("BIO", 1:19),
  "elevation",
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

feature_sets <- list(
  M0 = character(0),
  M1 = seasonal_features,
  M2 = c(seasonal_features, climate_features),
  M3 = c(seasonal_features, climate_features, "elevation"),
  M4 = c(seasonal_features, climate_features, "elevation", geographic_features)
)

stopifnot(
  length(feature_sets$M1) == 4L,
  length(feature_sets$M2) == 25L,
  length(feature_sets$M3) == 26L,
  length(feature_sets$M4) == 28L,
  all(unlist(feature_sets) %in% certified_predictors)
)


# -------------------------------------------------------------------------
# Modelling cohort
# -------------------------------------------------------------------------

# Returns the common complete-case cohort as a plain data frame with the
# target as a factor whose levels are the sorted 18-species vocabulary.
load_modelling_cohort <- function(path = modelling_paths$primary) {

  if (!file.exists(path)) {
    stop(
      "Missing processed input: ", path,
      "\nRun the certified data-preparation pipeline first.",
      call. = FALSE
    )
  }

  primary <- readRDS(path)

  stopifnot(
    nrow(primary) == expected_primary_rows,
    identical(attr(primary, "predictor_columns"), certified_predictors),
    !anyNA(primary$eventID),
    !anyDuplicated(primary$eventID),
    !anyNA(primary$scientificName)
  )

  complete <- complete.cases(as.data.frame(primary)[environmental_features])

  cohort <- as.data.frame(primary)[
    complete,
    c("eventID", "scientificName", "eventDate", certified_predictors)
  ]
  rownames(cohort) <- NULL

  species_levels <- sort(unique(as.character(cohort$scientificName)))
  cohort$scientificName <- factor(
    as.character(cohort$scientificName),
    levels = species_levels
  )

  stopifnot(
    nrow(cohort) == expected_cohort_rows,
    nlevels(cohort$scientificName) == expected_classes,
    !anyNA(cohort[certified_predictors])
  )

  cohort
}

# 0.5-degree cell identifier, matching the EDA-09 grid definition.
spatial_cell_id <- function(longitude,
                            latitude,
                            size = spatial_cell_degrees) {
  paste(
    floor(longitude / size),
    floor(latitude / size),
    sep = "_"
  )
}


# -------------------------------------------------------------------------
# Fold-assignment utilities
# -------------------------------------------------------------------------

# Class-stratified random assignment of rows to k folds.
assign_stratified_folds <- function(y, k, seed) {

  set.seed(seed)
  fold <- integer(length(y))

  for (class_level in levels(y)) {
    idx <- which(y == class_level)
    fold[idx] <- sample(rep_len(seq_len(k), length(idx)))
  }

  fold
}

# Class-stratified random split into "fit" and "tune" rows.
assign_stratified_split <- function(y, tune_share, seed) {

  set.seed(seed)
  role <- character(length(y))

  for (class_level in levels(droplevels(y))) {
    idx <- which(y == class_level)
    n_tune <- round(tune_share * length(idx))
    shuffled <- idx[sample.int(length(idx))]
    role[shuffled] <- "fit"
    role[shuffled[seq_len(n_tune)]] <- "tune"
  }

  role
}

# Deterministic greedy assignment of whole groups (spatial cells) to parts
# with target shares. Groups are placed largest first; each goes to the part
# that most reduces the squared deviation from its target, measured per class
# as a share of that class's total (so rare species count as much as common
# ones) plus one term for the overall event total. No group is ever split.
assign_groups_balanced <- function(group, y, shares) {

  counts <- unclass(table(group, droplevels(y)))
  class_total <- colSums(counts)
  n_total <- sum(counts)
  n_parts <- length(shares)

  target <- outer(shares, class_total)
  target_events <- shares * n_total

  current <- matrix(0, n_parts, ncol(counts))
  part_of_group <- integer(nrow(counts))

  group_order <- order(-rowSums(counts), rownames(counts))

  for (g in group_order) {

    v <- counts[g, ]

    cost_change <- vapply(seq_len(n_parts), function(p) {
      before <- (current[p, ] - target[p, ]) / class_total
      after <- (current[p, ] + v - target[p, ]) / class_total
      events_before <- (sum(current[p, ]) - target_events[p]) / n_total
      events_after <- (sum(current[p, ]) + sum(v) - target_events[p]) / n_total
      sum(after^2) - sum(before^2) + events_after^2 - events_before^2
    }, numeric(1))

    p <- which.min(cost_change)
    current[p, ] <- current[p, ] + v
    part_of_group[g] <- p
  }

  part_of_group[match(group, rownames(counts))]
}

# Loads the shared fold assignment and confirms it is row-aligned with the
# modelling cohort, so fold columns can be indexed directly.
load_modelling_folds <- function(cohort, path = modelling_paths$folds) {

  if (!file.exists(path)) {
    stop(
      "Missing fold assignment: ", path,
      "\nRun R/modelling/01_build_folds.R first.",
      call. = FALSE
    )
  }

  folds <- readRDS(path)

  stopifnot(
    identical(folds$eventID, cohort$eventID),
    identical(
      as.character(folds$scientificName),
      as.character(cohort$scientificName)
    )
  )

  folds
}


# -------------------------------------------------------------------------
# Evaluation metrics
# -------------------------------------------------------------------------
#
# Every model must supply an n x 18 probability (or score) matrix whose
# columns are named and ordered as levels(cohort$scientificName).
#
# Ranking convention: classes are ordered by decreasing score; exact ties are
# broken by column order, the same rule used for the top-1 prediction
# (max.col ties.method = "first"), so Top-1 accuracy, Top-k and MRR agree.
#
# Per-class F1 is 0 when a class is never predicted or has no correct
# prediction (precision undefined), matching the usual zero-division rule.

true_class_rank <- function(prob, truth_index) {

  p_true <- prob[cbind(seq_len(nrow(prob)), truth_index)]
  higher <- rowSums(prob > p_true)
  tied_before <- rowSums(prob == p_true & col(prob) < truth_index)

  1L + higher + tied_before
}

evaluate_predictions <- function(prob, truth) {

  class_levels <- levels(truth)

  stopifnot(
    is.matrix(prob),
    nrow(prob) == length(truth),
    identical(colnames(prob), class_levels),
    !anyNA(prob)
  )

  truth_index <- as.integer(truth)
  predicted_index <- max.col(prob, ties.method = "first")
  rank <- true_class_rank(prob, truth_index)

  confusion <- table(
    truth = factor(truth_index, levels = seq_along(class_levels)),
    predicted = factor(predicted_index, levels = seq_along(class_levels))
  )

  true_positive <- diag(confusion)
  support <- rowSums(confusion)
  predicted_n <- colSums(confusion)

  recall <- ifelse(support > 0, true_positive / support, NA_real_)
  precision <- ifelse(predicted_n > 0, true_positive / predicted_n, 0)
  f1 <- ifelse(
    precision + recall > 0,
    2 * precision * recall / (precision + recall),
    0
  )

  # Log loss uses the probability given to the true class, clipped away
  # from 0; it is meaningful only for genuine probability outputs.
  p_true <- prob[cbind(seq_along(truth_index), truth_index)]
  log_loss <- -mean(log(pmax(p_true, 1e-15)))

  overall <- tibble(
    n = length(truth),
    macro_f1 = mean(f1),
    accuracy = mean(predicted_index == truth_index),
    balanced_accuracy = mean(recall, na.rm = TRUE),
    top3_accuracy = mean(rank <= 3L),
    top5_accuracy = mean(rank <= 5L),
    mrr = mean(1 / rank),
    log_loss = log_loss,
    classes_predicted = sum(predicted_n > 0)
  )

  by_class <- tibble(
    scientificName = class_levels,
    support = as.integer(support),
    predicted_n = as.integer(predicted_n),
    precision = precision,
    recall = recall,
    f1 = f1
  )

  list(overall = overall, by_class = by_class)
}

# Mean and SD across outer folds for every metric column.
summarise_fold_metrics <- function(fold_metrics) {

  metric_columns <- c(
    "macro_f1", "accuracy", "balanced_accuracy",
    "top3_accuracy", "top5_accuracy", "mrr", "log_loss"
  )

  fold_metrics |>
    group_by(model, feature_set, regime) |>
    summarise(
      folds = n(),
      across(
        all_of(metric_columns),
        list(mean = mean, sd = sd),
        .names = "{.col}_{.fn}"
      ),
      .groups = "drop"
    )
}

# Out-of-fold predictions are event-level and stay in ignored
# data/interim/modelling/; only aggregate metrics are written to outputs/.
save_oof_predictions <- function(predictions, model, feature_set) {

  dir.create(modelling_paths$model_outputs, recursive = TRUE, showWarnings = FALSE)

  path <- file.path(
    modelling_paths$model_outputs,
    paste0("oof_", model, "_", feature_set, ".rds")
  )

  saveRDS(predictions, path)
  invisible(path)
}
