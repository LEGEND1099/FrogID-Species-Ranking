# REPORT-02: Audit class-level equity on the frozen M4 spatial folds.
# Run from FrogID-A2-Integration root:
#   Rscript R/reporting/02_audit_species_equity.R
# READ ONLY: never trains or modifies model/fold outputs.
# Outputs: outputs/tables/report_species_equity_*.csv
#          outputs/figures/report_species_equity_heatmap.png

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

root <- "outputs/tables"
if (!file.exists("renv.lock") || !dir.exists(root)) {
  stop("Run from the FrogID-A2-Integration project root.", call. = FALSE)
}

wanted_models <- c("elastic_net", "pca_lda", "pca_knn",
                   "random_forest", "xgboost")

paths <- file.path(root, paste0("model_", wanted_models, "_class_metrics.csv"))
missing <- paths[!file.exists(paths)]
if (length(missing)) stop("Missing model class tables: ", paste(missing, collapse = ", "))
classes <- bind_rows(lapply(paths, function(p) {
  x <- read_csv(p, show_col_types = FALSE, progress = FALSE)
  required <- c("model","feature_set","regime","fold","scientificName",
                "support","predicted_n","precision","recall","f1")
  if (!all(required %in% names(x))) {
    stop("Invalid class table schema: ", p)
  }
  x[, required]
}))

sp <- classes %>%
  filter(feature_set == "M4", regime == "spatial",
         model %in% wanted_models)

# Every model must have exactly the same 18-class, 3-fold assessment.
counts <- sp %>% count(model, fold)
if (nrow(counts) != 15L || any(counts$n != 18L) ||
    anyNA(sp[, c("support", "predicted_n", "precision", "recall", "f1")])) {
  stop("Incomplete or invalid 3-fold/18-species M4 spatial data.", call. = FALSE)
}
if (anyDuplicated(sp[c("model", "fold", "scientificName")])) {
  stop("Duplicate species/fold records.", call. = FALSE)
}

# Rarity is defined ONCE using true assessment support (never model scores).
# These are the bottom third (6 of 18 species), not the worst-performing classes.
supports <- sp %>%
  filter(model == "xgboost") %>%
  group_by(scientificName) %>%
  summarise(total_support = sum(support), .groups = "drop") %>%
  arrange(total_support, scientificName)
if (nrow(supports) != 18L) stop("Expected exactly 18 target species.")
rare_species <- head(supports$scientificName, 6L)

# Check assessment support is identical for the five classifiers.
support_comparison <- sp %>%
  group_by(model, scientificName) %>%
  summarise(total_support = sum(support), .groups = "drop") %>%
  left_join(supports, by = "scientificName", suffix = c("_model", "_reference"))
if (any(support_comparison$total_support_model !=
        support_comparison$total_support_reference)) {
  stop("The five models do not share the same species support.")
}

species <- sp %>%
  group_by(model, scientificName) %>%
  summarise(
    mean_f1 = mean(f1),
    mean_recall = mean(recall),
    mean_precision = mean(precision),
    worst_fold_f1 = min(f1),
    zero_f1_folds = sum(f1 == 0),
    total_support = sum(support),
    total_predicted = sum(predicted_n),
    .groups = "drop"
  ) %>%
  mutate(rare_six = scientificName %in% rare_species)

scorecard <- species %>%
  group_by(model) %>%
  summarise(
    macro_f1 = mean(mean_f1),
    balanced_accuracy = mean(mean_recall),
    rare_six_mean_f1 = mean(mean_f1[rare_six]),
    rare_six_mean_recall = mean(mean_recall[rare_six]),
    worst_six_mean_f1 = mean(head(sort(mean_f1), 6L)),
    minimum_species_f1 = min(mean_f1),
    species_with_zero_f1 = sum(mean_f1 == 0),
    species_f1_below_0_10 = sum(mean_f1 < 0.10),
    species_never_predicted = sum(total_predicted == 0),
    total_zero_f1_fold_species = sum(zero_f1_folds),
    .groups = "drop"
  ) %>%
  arrange(desc(macro_f1))

# A direct, paired comparison of our two leading models, by species.
pair <- species %>%
  filter(model %in% c("xgboost", "random_forest")) %>%
  select(model, scientificName, total_support, rare_six, mean_f1,
         mean_recall) %>%
  pivot_wider(names_from = model, values_from = c(mean_f1, mean_recall)) %>%
  mutate(
    f1_xgb_minus_rf = mean_f1_xgboost - mean_f1_random_forest,
    recall_xgb_minus_rf = mean_recall_xgboost - mean_recall_random_forest
  ) %>%
  arrange(f1_xgb_minus_rf)

# Top-3 recall for each species: can the correct species enter the shortlist?
# Calculated from saved out-of-fold probabilities; no training.
top3_parts <- list()
for (model in wanted_models) {
  path <- file.path("data/interim/modelling", paste0("oof_", model, "_M4.rds"))
  if (!file.exists(path)) {
    warning("No OOF RDS for top-3 species audit: ", path)
    next
  }
  obj <- readRDS(path)
  d <- obj$spatial
  if (is.null(d) || is.null(d$prob) || is.null(d$truth)) {
    warning("Unexpected OOF format: ", path)
    next
  }
  p <- as.matrix(d$prob)
  truth <- as.character(d$truth)
  idx <- match(truth, colnames(p))
  if (length(truth) != nrow(p) || anyNA(idx) || ncol(p) != 18L) {
    stop("Invalid OOF truth/probability alignment: ", path)
  }
  p_true <- p[cbind(seq_len(nrow(p)), idx)]
  # Match project evaluator's tie rule (earlier column wins).
  ranks <- 1L + rowSums(p > p_true) +
    rowSums(p == p_true & col(p) < idx)
  top3_parts[[model]] <- tibble(
    model = model,
    scientificName = truth,
    in_top3 = ranks <= 3L
  ) %>%
    group_by(model, scientificName) %>%
    summarise(top3_recall = mean(in_top3), .groups = "drop")
  rm(obj, d, p, truth, idx, p_true, ranks)
  gc(verbose = FALSE)
}
top3_by_species <- bind_rows(top3_parts)
if (nrow(top3_by_species)) {
  species <- species %>%
    left_join(top3_by_species, by = c("model", "scientificName"))
  top3_summary <- species %>%
    group_by(model) %>%
    summarise(
      rare_six_top3_recall = mean(top3_recall[rare_six]),
      worst_species_top3_recall = min(top3_recall),
      .groups = "drop"
    )
  scorecard <- left_join(scorecard, top3_summary, by = "model")
}

write_csv(supports %>% mutate(rare_six = scientificName %in% rare_species),
          file.path(root, "report_species_equity_prevalence.csv"))
write_csv(species, file.path(root, "report_species_equity_by_species.csv"))
write_csv(scorecard, file.path(root, "report_species_equity_scorecard.csv"))
write_csv(pair, file.path(root, "report_species_equity_rf_vs_xgb.csv"))

# Visual comparison: all 18 species and all five classifiers.
labels <- c(
  elastic_net = "Elastic-net", pca_lda = "PCA-LDA",
  pca_knn = "PCA-kNN", random_forest = "Random Forest", xgboost = "XGBoost"
)
plot_data <- species %>%
  mutate(
    model_label = factor(labels[model], levels = labels[wanted_models]),
    species_label = factor(scientificName, levels = rev(supports$scientificName))
  )
p <- ggplot(plot_data, aes(x = model_label, y = species_label, fill = mean_f1)) +
  geom_tile(colour = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.2f", mean_f1)), size = 2.7) +
  scale_fill_gradient(low = "#eef3f9", high = "#17578d",
                      limits = c(0, 1), name = "Mean F1") +
  labs(
    title = "Spatial F1 by species and classifier",
    subtitle = "18 equal-weighted species; ordered by occurrence count, rarest at top",
    x = NULL, y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.text.x = element_text(angle = 15, hjust = 1))
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)
ggsave("outputs/figures/report_species_equity_heatmap.png", p,
       width = 11, height = 8, dpi = 170, bg = "white")

cat("\nSPECIES EQUITY AUDIT PASSED\n\n")
cat("Six least-common species (defined from true labels):\n")
print(supports %>% filter(scientificName %in% rare_species),
      n = 6, width = Inf)
cat("\nModel equity scorecard (all values 0-1 except counts):\n")
print(scorecard, width = Inf)
cat("\nXGBoost vs RF by species; negative means RF has higher F1:\n")
print(pair %>% select(scientificName, rare_six, total_support,
                      mean_f1_random_forest, mean_f1_xgboost,
                      f1_xgb_minus_rf), n = 18, width = Inf)
cat("\nSaved report_species_equity_*.csv and the heatmap.\n")
