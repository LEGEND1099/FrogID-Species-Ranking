# =========================================================================
# EDA-05: Environmental predictors
#
# Purpose:
# Describe the distributions, redundancy and species-related structure of the
# 22 certified environmental predictors before any preprocessing or modelling
# decision is made.
#
# Questions:
#   1. What are the predictor distributions and scale differences?
#   2. Which environmental variables are strongly correlated?
#   3. Which variables show the largest descriptive between-species separation?
#   4. How strongly are environmental predictors associated with geography?
#   5. How concentrated is environmental variation into principal components?
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs are aggregate summaries and figures only.
#
# No classifier is fitted. No variable is removed, imputed or selected for a
# later model in this script.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA05"

ENV_FEATURES <- c(
  paste0("BIO", 1:19),
  "elevation",
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

if (!file.exists(INPUT)) {
  stop("Missing input: ", INPUT, call. = FALSE)
}

dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

frogs <- as.data.frame(readRDS(INPUT))

required <- c(
  "eventID",
  "scientificName",
  "decimalLatitude",
  "decimalLongitude",
  ENV_FEATURES
)

stopifnot(
  nrow(frogs) == 247406L,
  all(required %in% names(frogs)),
  length(unique(frogs$scientificName)) == 18L,
  length(ENV_FEATURES) == 22L,
  length(unique(frogs$eventID)) == nrow(frogs)
)

complete_environment <- complete.cases(frogs[ENV_FEATURES])

stopifnot(
  sum(!complete_environment) == 4806L
)

complete_frogs <- frogs[complete_environment, , drop = FALSE]

# Reproducibility diagnostic for the near-exact WorldClim identity
# BIO7 ~= BIO5 - BIO6. This records the observed numerical discrepancy without
# making a model-specific feature-removal decision in EDA.
bio567_max_abs_dependency_error <- max(
  abs(
    complete_frogs$BIO7 -
      (
        complete_frogs$BIO5 -
          complete_frogs$BIO6
      )
  )
)

species_order <- names(
  sort(table(complete_frogs$scientificName), decreasing = TRUE)
)

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

safe_skewness <- function(x) {

  s <- sd(x)

  if (!is.finite(s) || s == 0) {
    return(NA_real_)
  }

  mean((x - mean(x))^3) / s^3
}

eta_squared_species <- function(data, feature) {

  x <- data[[feature]]
  overall_mean <- mean(x)

  species_stats <- data %>%
    group_by(scientificName) %>%
    summarise(
      n = n(),
      group_mean = mean(.data[[feature]]),
      .groups = "drop"
    )

  ss_between <- sum(
    species_stats$n *
      (species_stats$group_mean - overall_mean)^2
  )

  ss_total <- sum(
    (x - overall_mean)^2
  )

  if (ss_total == 0) {
    return(NA_real_)
  }

  ss_between / ss_total
}

# -------------------------------------------------------------------------
# 1. Univariate environmental summaries
# -------------------------------------------------------------------------

univariate_rows <- lapply(
  ENV_FEATURES,
  function(feature) {

    x_all <- frogs[[feature]]
    x <- complete_frogs[[feature]]

    q <- quantile(
      x,
      probs = c(0.25, 0.5, 0.75),
      names = FALSE
    )

    iqr_value <- q[3] - q[1]

    lower_flag <- q[1] - 1.5 * iqr_value
    upper_flag <- q[3] + 1.5 * iqr_value

    data.frame(
      feature = feature,
      rows = nrow(frogs),
      missing_n = sum(is.na(x_all)),
      missing_percent = 100 * mean(is.na(x_all)),
      distinct_complete_values = length(unique(x)),
      minimum = min(x),
      q25 = q[1],
      median = q[2],
      q75 = q[3],
      maximum = max(x),
      mean = mean(x),
      sd = sd(x),
      iqr = iqr_value,
      skewness = safe_skewness(x),
      iqr_flagged_n =
        sum(x < lower_flag | x > upper_flag),
      iqr_flagged_percent =
        100 * mean(x < lower_flag | x > upper_flag),
      stringsAsFactors = FALSE
    )
  }
)

environmental_univariate_summary <- bind_rows(
  univariate_rows
)

# -------------------------------------------------------------------------
# 2. Predictor-predictor correlation
# -------------------------------------------------------------------------

environment_matrix <- as.matrix(
  complete_frogs[ENV_FEATURES]
)

spearman_cor <- cor(
  environment_matrix,
  method = "spearman"
)

cor_index <- which(
  upper.tri(spearman_cor),
  arr.ind = TRUE
)

environmental_correlation_pairs <- data.frame(
  feature_a = rownames(spearman_cor)[cor_index[, 1]],
  feature_b = colnames(spearman_cor)[cor_index[, 2]],
  spearman_rho = spearman_cor[cor_index],
  stringsAsFactors = FALSE
)

environmental_correlation_pairs$absolute_spearman_rho <-
  abs(environmental_correlation_pairs$spearman_rho)

environmental_correlation_pairs <-
  environmental_correlation_pairs %>%
  arrange(desc(absolute_spearman_rho))

# -------------------------------------------------------------------------
# 3. Environmental association with latitude / longitude
# -------------------------------------------------------------------------

geographic_correlation <- bind_rows(
  lapply(
    ENV_FEATURES,
    function(feature) {
      data.frame(
        feature = feature,
        spearman_latitude = cor(
          complete_frogs[[feature]],
          complete_frogs$decimalLatitude,
          method = "spearman"
        ),
        spearman_longitude = cor(
          complete_frogs[[feature]],
          complete_frogs$decimalLongitude,
          method = "spearman"
        ),
        stringsAsFactors = FALSE
      )
    }
  )
)

geographic_correlation$max_absolute_coordinate_correlation <-
  pmax(
    abs(geographic_correlation$spearman_latitude),
    abs(geographic_correlation$spearman_longitude)
  )

geographic_correlation <-
  geographic_correlation %>%
  arrange(desc(max_absolute_coordinate_correlation))

# -------------------------------------------------------------------------
# 4. Species-level environmental summaries and descriptive separation
# -------------------------------------------------------------------------

species_environmental_summary <- bind_rows(
  lapply(
    species_order,
    function(sp) {

      d <- complete_frogs[
        complete_frogs$scientificName == sp,
        ,
        drop = FALSE
      ]

      bind_rows(
        lapply(
          ENV_FEATURES,
          function(feature) {

            x <- d[[feature]]
            q <- quantile(
              x,
              probs = c(0.25, 0.5, 0.75),
              names = FALSE
            )

            data.frame(
              scientificName = sp,
              feature = feature,
              events = length(x),
              q25 = q[1],
              median = q[2],
              q75 = q[3],
              iqr = q[3] - q[1],
              stringsAsFactors = FALSE
            )
          }
        )
      )
    }
  )
)

species_separation_summary <- bind_rows(
  lapply(
    ENV_FEATURES,
    function(feature) {
      data.frame(
        feature = feature,
        eta_squared_species =
          eta_squared_species(
            complete_frogs,
            feature
          ),
        stringsAsFactors = FALSE
      )
    }
  )
) %>%
  arrange(desc(eta_squared_species))

# The top four variables are selected only for an EDA visualisation.
# This is not model feature selection.
selected_species_plot_features <-
  head(
    species_separation_summary$feature,
    4
  )

# -------------------------------------------------------------------------
# 5. PCA of the complete environmental block
#
# PCA is intentionally centred and scaled because the 22 predictors have
# different units. This is an EDA representation only and does not decide
# whether later models should be standardised.
# -------------------------------------------------------------------------

pca_fit <- prcomp(
  environment_matrix,
  center = TRUE,
  scale. = TRUE
)

pca_variance <- pca_fit$sdev^2
pca_variance_share <- pca_variance / sum(pca_variance)
pca_cumulative <- cumsum(pca_variance_share)

environmental_pca_variance <- data.frame(
  component = paste0("PC", seq_along(pca_variance)),
  variance = pca_variance,
  variance_share = pca_variance_share,
  cumulative_variance_share = pca_cumulative,
  stringsAsFactors = FALSE
)

environmental_pca_loadings <- data.frame(
  feature = rownames(pca_fit$rotation),
  pca_fit$rotation,
  row.names = NULL,
  check.names = FALSE
)

pca_scores <- as.data.frame(
  pca_fit$x[, 1:3, drop = FALSE]
)

pca_scores$scientificName <-
  complete_frogs$scientificName

pca_scores$decimalLatitude <-
  complete_frogs$decimalLatitude

pca_scores$decimalLongitude <-
  complete_frogs$decimalLongitude

pca_geographic_correlation <- data.frame(
  component = c("PC1", "PC2", "PC3"),
  spearman_latitude = vapply(
    pca_scores[c("PC1", "PC2", "PC3")],
    function(x) {
      cor(
        x,
        pca_scores$decimalLatitude,
        method = "spearman"
      )
    },
    numeric(1)
  ),
  spearman_longitude = vapply(
    pca_scores[c("PC1", "PC2", "PC3")],
    function(x) {
      cor(
        x,
        pca_scores$decimalLongitude,
        method = "spearman"
      )
    },
    numeric(1)
  ),
  stringsAsFactors = FALSE
)

pca_species_summary <- pca_scores %>%
  group_by(scientificName) %>%
  summarise(
    events = n(),
    pc1_q25 = unname(quantile(PC1, 0.25)),
    pc1_median = median(PC1),
    pc1_q75 = unname(quantile(PC1, 0.75)),
    pc2_q25 = unname(quantile(PC2, 0.25)),
    pc2_median = median(PC2),
    pc2_q75 = unname(quantile(PC2, 0.75)),
    .groups = "drop"
  ) %>%
  arrange(
    match(scientificName, species_order)
  )

components_for <- function(threshold) {
  which(pca_cumulative >= threshold)[1]
}

environmental_summary <- data.frame(
  measure = c(
    "events",
    "complete_environmental_events",
    "incomplete_environmental_events",
    "environmental_predictors",
    "predictor_sd_minimum",
    "predictor_sd_maximum",
    "predictor_sd_max_to_min_ratio",
    "correlation_pairs_abs_rho_ge_0_8",
    "correlation_pairs_abs_rho_ge_0_9",
    "maximum_absolute_pairwise_spearman",
    "maximum_absolute_environment_coordinate_spearman",
    "bio7_max_abs_difference_from_bio5_minus_bio6",
    "pc1_variance_percent",
    "pc2_variance_percent",
    "pc1_pc2_cumulative_variance_percent",
    "components_for_80_percent_variance",
    "components_for_90_percent_variance",
    "components_for_95_percent_variance"
  ),
  value = c(
    nrow(frogs),
    nrow(complete_frogs),
    sum(!complete_environment),
    length(ENV_FEATURES),
    min(environmental_univariate_summary$sd),
    max(environmental_univariate_summary$sd),
    max(environmental_univariate_summary$sd) /
      min(environmental_univariate_summary$sd),
    sum(
      environmental_correlation_pairs$absolute_spearman_rho >= 0.8
    ),
    sum(
      environmental_correlation_pairs$absolute_spearman_rho >= 0.9
    ),
    max(
      environmental_correlation_pairs$absolute_spearman_rho
    ),
    max(
      geographic_correlation$max_absolute_coordinate_correlation
    ),
    bio567_max_abs_dependency_error,
    100 * pca_variance_share[1],
    100 * pca_variance_share[2],
    100 * sum(pca_variance_share[1:2]),
    components_for(0.80),
    components_for(0.90),
    components_for(0.95)
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# 6. Figures
# -------------------------------------------------------------------------

# Figure 1: univariate distributions on native scales.
# Use a faceted ggplot histogram so each predictor retains its native scale
# without the rendering artefacts observed in the original base-R panel.
environment_distribution_plot_data <- stack(
  complete_frogs[ENV_FEATURES]
)

names(environment_distribution_plot_data) <- c(
  "value",
  "feature"
)

environment_distribution_plot_data$feature <- factor(
  environment_distribution_plot_data$feature,
  levels = ENV_FEATURES
)

p_environment_distributions <- ggplot(
  environment_distribution_plot_data,
  aes(x = value)
) +
  geom_histogram(
    bins = 40
  ) +
  facet_wrap(
    ~ feature,
    scales = "free",
    ncol = 5
  ) +
  labs(
    title = "Environmental predictor distributions",
    subtitle = "Complete environmental rows; each predictor shown on its native scale",
    x = "Predictor value",
    y = "Events"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 8),
    axis.text = element_text(size = 6),
    axis.title = element_text(size = 8)
  )

ggsave(
  file.path(
    FIG_DIR,
    "eda05_environmental_distributions.png"
  ),
  p_environment_distributions,
  width = 12,
  height = 9.5,
  dpi = 180
)

# Figure 2: Spearman correlation heatmap.
cor_plot <- expand.grid(
  feature_a = ENV_FEATURES,
  feature_b = ENV_FEATURES,
  stringsAsFactors = FALSE
)

cor_plot$spearman_rho <- mapply(
  function(a, b) {
    spearman_cor[a, b]
  },
  cor_plot$feature_a,
  cor_plot$feature_b
)

cor_plot$feature_a <- factor(
  cor_plot$feature_a,
  levels = ENV_FEATURES
)

cor_plot$feature_b <- factor(
  cor_plot$feature_b,
  levels = rev(ENV_FEATURES)
)

p_cor <- ggplot(
  cor_plot,
  aes(
    x = feature_a,
    y = feature_b,
    fill = spearman_rho
  )
) +
  geom_tile() +
  scale_fill_gradient2(
    limits = c(-1, 1),
    midpoint = 0,
    name = "Spearman\nrho"
  ) +
  labs(
    title = "Environmental predictor correlation",
    subtitle = "Spearman correlations using complete environmental rows",
    x = NULL,
    y = NULL
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(
      angle = 60,
      hjust = 1,
      size = 7
    ),
    axis.text.y = element_text(
      size = 7
    )
  )

ggsave(
  file.path(
    FIG_DIR,
    "eda05_environmental_correlation.png"
  ),
  p_cor,
  width = 10,
  height = 9,
  dpi = 180
)

# Figure 3: species median and IQR for the four variables with the largest
# descriptive between-species variance share.
species_plot_data <-
  species_environmental_summary %>%
  filter(
    feature %in% selected_species_plot_features
  )

species_plot_data$scientificName <- factor(
  species_plot_data$scientificName,
  levels = rev(species_order)
)

species_plot_data$feature <- factor(
  species_plot_data$feature,
  levels = selected_species_plot_features
)

p_species_environment <- ggplot(
  species_plot_data,
  aes(
    x = median,
    y = scientificName
  )
) +
  geom_segment(
    aes(
      x = q25,
      xend = q75,
      yend = scientificName
    ),
    linewidth = 0.6
  ) +
  geom_point(
    size = 1.8
  ) +
  facet_wrap(
    ~ feature,
    scales = "free_x",
    ncol = 2
  ) +
  labs(
    title = "Species environmental summaries",
    subtitle = paste0(
      "Median and IQR; four variables with largest descriptive ",
      "between-species variance share"
    ),
    x = "Predictor value",
    y = NULL
  ) +
  theme_minimal() +
  theme(
    axis.text.y = element_text(size = 6.5)
  )

ggsave(
  file.path(
    FIG_DIR,
    "eda05_species_environmental_summary.png"
  ),
  p_species_environment,
  width = 10,
  height = 9,
  dpi = 180
)

# Figure 4: PCA species summaries.
p_pca <- ggplot(
  pca_species_summary,
  aes(
    x = pc1_median,
    y = pc2_median,
    label = scientificName
  )
) +
  geom_segment(
    aes(
      x = pc1_q25,
      xend = pc1_q75,
      yend = pc2_median
    ),
    linewidth = 0.5
  ) +
  geom_segment(
    aes(
      x = pc1_median,
      xend = pc1_median,
      y = pc2_q25,
      yend = pc2_q75
    ),
    linewidth = 0.5
  ) +
  geom_point(
    size = 2
  ) +
  geom_text(
    nudge_y = 0.12,
    size = 2.4,
    check_overlap = TRUE
  ) +
  labs(
    title = "Species positions in environmental PCA space",
    subtitle = "Points are species medians; segments show PC1 and PC2 IQRs",
    x = sprintf(
      "PC1 (%.1f%% variance)",
      100 * pca_variance_share[1]
    ),
    y = sprintf(
      "PC2 (%.1f%% variance)",
      100 * pca_variance_share[2]
    )
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda05_pca_species_summary.png"
  ),
  p_pca,
  width = 9,
  height = 7,
  dpi = 180
)

# -------------------------------------------------------------------------
# 7. Write aggregate outputs
# -------------------------------------------------------------------------

write.csv(
  environmental_univariate_summary,
  file.path(
    TABLE_DIR,
    "eda05_environmental_univariate_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  environmental_correlation_pairs,
  file.path(
    TABLE_DIR,
    "eda05_environmental_correlation_pairs.csv"
  ),
  row.names = FALSE
)

write.csv(
  geographic_correlation,
  file.path(
    TABLE_DIR,
    "eda05_environment_geographic_correlation.csv"
  ),
  row.names = FALSE
)

write.csv(
  species_environmental_summary,
  file.path(
    TABLE_DIR,
    "eda05_species_environmental_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  species_separation_summary,
  file.path(
    TABLE_DIR,
    "eda05_species_separation_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  environmental_pca_variance,
  file.path(
    TABLE_DIR,
    "eda05_pca_variance.csv"
  ),
  row.names = FALSE
)

write.csv(
  environmental_pca_loadings,
  file.path(
    TABLE_DIR,
    "eda05_pca_loadings.csv"
  ),
  row.names = FALSE
)

write.csv(
  pca_geographic_correlation,
  file.path(
    TABLE_DIR,
    "eda05_pca_geographic_correlation.csv"
  ),
  row.names = FALSE
)

write.csv(
  pca_species_summary,
  file.path(
    TABLE_DIR,
    "eda05_pca_species_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  environmental_summary,
  file.path(
    TABLE_DIR,
    "eda05_environmental_summary.csv"
  ),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# 8. Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-05 ENVIRONMENTAL PREDICTORS\n")
cat("============================================================\n")

cat("\nEnvironmental univariate summary:\n")
print(
  environmental_univariate_summary,
  row.names = FALSE,
  digits = 4
)

cat("\nStrongest environmental correlations:\n")
print(
  head(
    environmental_correlation_pairs,
    20
  ),
  row.names = FALSE,
  digits = 4
)

cat("\nEnvironmental variables most associated with coordinates:\n")
print(
  head(
    geographic_correlation,
    10
  ),
  row.names = FALSE,
  digits = 4
)

cat("\nLargest descriptive between-species variance shares:\n")
print(
  head(
    species_separation_summary,
    10
  ),
  row.names = FALSE,
  digits = 4
)

cat("\nPCA variance summary:\n")
print(
  head(
    environmental_pca_variance,
    10
  ),
  row.names = FALSE,
  digits = 4
)

cat("\nPCA geographic correlations:\n")
print(
  pca_geographic_correlation,
  row.names = FALSE,
  digits = 4
)

cat("\nCompact environmental summary:\n")
print(
  environmental_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nBIO5/BIO6/BIO7 dependency diagnostic:\n")
cat(sprintf(
  "max |BIO7 - (BIO5 - BIO6)| = %.10g\n",
  bio567_max_abs_dependency_error
))

cat("\nEDA-05 COMPLETE\n")
cat(
  paste0(
    "No classifier was fitted and no environmental variable was removed, ",
    "imputed or selected for modelling.\n"
  )
)
