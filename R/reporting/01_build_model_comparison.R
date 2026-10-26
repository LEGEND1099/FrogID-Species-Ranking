# REPORT-01: Aggregate saved results for STAT5003 Assignment 2.
# Usage from the FrogID-A2-Integration repository root:
#   Rscript R/reporting/01_build_model_comparison.R
#
# INPUTS:  outputs/tables/model_*_fold_metrics.csv
#          outputs/tables/model_*_class_metrics.csv
# OUTPUTS: outputs/tables/report_*.csv, outputs/figures/report_*.png
#
# This script NEVER fits models, changes folds, or loads event-level data.
# It discovers new model outputs automatically (including future RF/XGBoost).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
})

if (!file.exists("renv.lock") || !dir.exists("outputs/tables")) {
  stop("Run this script from the FrogID-A2-Integration repository root.", call. = FALSE)
}

input_dir <- "outputs/tables"
figure_dir <- "outputs/figures"
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

metric_names <- c("macro_f1", "accuracy", "balanced_accuracy",
                  "top3_accuracy", "top5_accuracy", "mrr", "log_loss")
needed <- c("model", "feature_set", "regime", "fold", "n", metric_names,
            "classes_predicted")

label_model <- function(model) {
  labels <- c(prevalence = "Prevalence baseline",
              elastic_net = "Elastic-net",
              pca_lda = "PCA-LDA",
              pca_knn = "PCA-kNN",
              random_forest = "Random Forest",
              rf = "Random Forest",
              xgboost = "XGBoost",
              xgb = "XGBoost")
  ifelse(model %in% names(labels), unname(labels[model]), model)
}

fold_files <- list.files(input_dir,
                         pattern = "^model_.+_fold_metrics\\.csv$",
                         full.names = TRUE)
if (!length(fold_files)) stop("No saved fold metrics found", call. = FALSE)

read_valid_fold <- function(path) {
  x <- read_csv(path, show_col_types = FALSE, progress = FALSE)
  missing <- setdiff(needed, names(x))
  if (length(missing)) stop(basename(path), " missing: ",
                            paste(missing, collapse = ", "), call. = FALSE)
  x <- x %>% select(all_of(needed), any_of("runtime_seconds"))
  if (anyNA(x[, needed]) || any(!is.finite(as.matrix(x[, metric_names])))) {
    stop("Missing/non-finite metrics: ", basename(path), call. = FALSE)
  }
  x
}

all_folds <- bind_rows(lapply(fold_files, read_valid_fold)) %>%
  arrange(model, feature_set, regime, fold)

# Invariants for apples-to-apples comparisons: exact frozen outer sizes,
# exactly one assessment per regime/fold, and 3 folds per model/set/regime.
expected_n <- tibble(
  regime = rep(c("random", "spatial"), each = 3),
  fold = rep(1:3, times = 2),
  expected_n = c(80872, 80868, 80860, 87738, 78585, 76277)
)
if (anyDuplicated(all_folds[c("model", "feature_set", "regime", "fold")])) {
  stop("Duplicate model/feature/regime/fold rows", call. = FALSE)
}
checked <- left_join(all_folds, expected_n, by = c("regime", "fold"))
if (anyNA(checked$expected_n) || any(checked$n != checked$expected_n)) {
  stop("Fold sizes do not match the committed frozen folds", call. = FALSE)
}
fold_counts <- all_folds %>% count(model, feature_set, regime)
if (any(fold_counts$n != 3L)) {
  stop("Incomplete three-fold result group; not safe to compare", call. = FALSE)
}
if (any(all_folds$macro_f1 < 0 | all_folds$macro_f1 > 1 |
        all_folds$accuracy < 0 | all_folds$accuracy > 1)) {
  stop("Invalid metric values", call. = FALSE)
}

summarise_metric <- function(x) {
  x %>% group_by(model, feature_set, regime) %>%
    summarise(
      folds = n(),
      across(all_of(metric_names), list(mean = mean, sd = sd),
             .names = "{.col}_{.fn}"),
      .groups = "drop"
    ) %>% arrange(model, feature_set, regime)
}
summary <- summarise_metric(all_folds)

m4 <- summary %>% filter(feature_set == "M4", regime == "spatial") %>%
  arrange(desc(macro_f1_mean)) %>%
  mutate(rank = row_number(), model_label = label_model(model)) %>%
  select(rank, model, model_label, feature_set, regime, folds,
         macro_f1_mean, macro_f1_sd, accuracy_mean,
         balanced_accuracy_mean, top3_accuracy_mean,
         top5_accuracy_mean, mrr_mean, log_loss_mean)

if (!nrow(m4)) stop("No M4 spatial model results yet", call. = FALSE)

# Paired M4-minus-M3 fold-level improvement by model and validation regime.
# A fold paired contrast is preferable to subtracting rounded summary means.
paired <- all_folds %>% filter(feature_set %in% c("M3", "M4")) %>%
  select(model, regime, fold, feature_set, macro_f1) %>%
  pivot_wider(names_from = feature_set, values_from = macro_f1) %>%
  filter(!is.na(M3), !is.na(M4)) %>%
  mutate(delta_macro_f1 = M4 - M3)
paired_summary <- paired %>% group_by(model, regime) %>%
  summarise(folds = n(),
            delta_macro_f1_mean = mean(delta_macro_f1),
            delta_macro_f1_sd = sd(delta_macro_f1),
            folds_m4_better = sum(delta_macro_f1 > 0),
            .groups = "drop") %>% arrange(model, regime)

# Species-level metrics are optional for future model families, but once a
# class table exists it must have exactly 18 species per result fold.
class_files <- list.files(input_dir,
                          pattern = "^model_.+_class_metrics\\.csv$",
                          full.names = TRUE)
class_needed <- c("model", "feature_set", "regime", "fold",
                  "scientificName", "support", "predicted_n",
                  "precision", "recall", "f1")
all_classes <- tibble()
if (length(class_files)) {
  class_parts <- lapply(class_files, function(path) {
    x <- read_csv(path, show_col_types = FALSE, progress = FALSE)
    if (!all(class_needed %in% names(x))) {
      stop("Invalid class-metrics schema: ", basename(path), call. = FALSE)
    }
    x %>% select(all_of(class_needed))
  })
  all_classes <- bind_rows(class_parts)
  nclass <- all_classes %>% count(model, feature_set, regime, fold)
  if (any(nclass$n != 18L) ||
      anyDuplicated(all_classes[class_needed[1:5]])) {
    stop("Class metrics must contain exactly 18 unique species per fold", call. = FALSE)
  }
}

species_spatial <- if (nrow(all_classes)) {
  all_classes %>% filter(feature_set == "M4", regime == "spatial") %>%
    group_by(model, scientificName) %>%
    summarise(folds = n(), mean_f1 = mean(f1),
              sd_f1 = sd(f1), mean_recall = mean(recall),
              mean_precision = mean(precision),
              total_support = sum(support), .groups = "drop") %>%
    arrange(model, mean_f1)
} else tibble()

write_csv(all_folds, file.path(input_dir, "report_all_fold_metrics.csv"))
write_csv(summary, file.path(input_dir, "report_model_summary.csv"))
write_csv(m4, file.path(input_dir, "report_m4_spatial_leaderboard.csv"))
write_csv(paired, file.path(input_dir, "report_m3_m4_fold_deltas.csv"))
write_csv(paired_summary, file.path(input_dir, "report_m3_m4_effect.csv"))
if (nrow(species_spatial)) {
  write_csv(species_spatial,
            file.path(input_dir, "report_m4_spatial_species.csv"))
}

save_figure <- function(plot, filename, width = 9, height = 5.2) {
  ggsave(filename = file.path(figure_dir, filename), plot = plot,
         width = width, height = height, units = "in", dpi = 180,
         bg = "white")
}

# Main model comparison: mean Macro-F1 with SD error bars by regime.
plot_data <- summary %>% filter(feature_set == "M4", model != "prevalence") %>%
  mutate(model_label = label_model(model),
         regime = factor(regime, levels = c("random", "spatial"),
                         labels = c("Random CV", "Spatial CV")))
if (nrow(plot_data)) {
  p <- ggplot(plot_data,
              aes(x = reorder(model_label, macro_f1_mean),
                  y = macro_f1_mean)) +
    geom_col(fill = "#2463a6", width = 0.65) +
    geom_errorbar(aes(ymin = pmax(0, macro_f1_mean - macro_f1_sd),
                      ymax = macro_f1_mean + macro_f1_sd), width = 0.2) +
    coord_flip() + facet_wrap(~regime, nrow = 1) +
    scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
    labs(title = "M4 classifier comparison", subtitle = "Macro-F1; bars are fold means, whiskers are fold SD (n=3)",
         x = NULL, y = "Macro-F1") + theme_minimal(base_size = 12)
  save_figure(p, "report_m4_macro_f1.png")
}

if (nrow(paired_summary)) {
  p <- paired_summary %>%
    mutate(model_label = label_model(model),
           regime = ifelse(regime == "random", "Random CV", "Spatial CV")) %>%
    ggplot(aes(x = model_label, y = delta_macro_f1_mean, fill = regime)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_col(position = position_dodge(width = 0.7), width = 0.65) +
    labs(title = "Effect of adding coordinates (M4 minus M3)",
         subtitle = "Mean paired difference in Macro-F1 across 3 identical folds",
         x = NULL, y = "Change in Macro-F1", fill = "Validation") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 20, hjust = 1))
  save_figure(p, "report_m3_m4_effect.png")
}

if (nrow(species_spatial)) {
  # Automatically update the plot as the winning M4 spatial model changes.
  leader <- m4$model[1]
  species_plot <- species_spatial %>% filter(model == leader)
  if (nrow(species_plot)) {
    p <- ggplot(species_plot,
                aes(x = reorder(scientificName, mean_f1), y = mean_f1)) +
      geom_col(fill = "#248b83", width = 0.7) + coord_flip() +
      scale_y_continuous(limits = c(0, 1)) +
      labs(title = paste("Spatial performance by species:", label_model(leader)),
           subtitle = "Unweighted mean species F1 across 3 spatial assessment folds",
           x = NULL, y = "Mean species F1") +
      theme_minimal(base_size = 11)
    save_figure(p, "report_leader_species_f1.png", width = 9, height = 6.2)
  }
}

expected_models <- c("elastic_net", "pca_lda", "pca_knn", "random_forest", "xgboost")
missing_models <- setdiff(expected_models, unique(m4$model))
cat("\nREPORT-01 PASSED: model result aggregation complete\n")
cat("Model families with M4 spatial results: ",
    paste(m4$model, collapse = ", "), "\n", sep = "")
if (length(missing_models)) {
  cat("Still pending (or check naming): ",
      paste(missing_models, collapse = ", "), "\n", sep = "")
}
cat("M4 spatial leaderboard (provisional until all models complete):\n")
print(m4 %>% select(rank, model_label, macro_f1_mean,
                    macro_f1_sd, accuracy_mean, top3_accuracy_mean),
      width = Inf)
cat("Tables saved under outputs/tables/report_*.csv\n")
cat("Figures saved under outputs/figures/report_*.png\n")
