# =========================================================================
# EDA-09b: Integrated ecological versus geographic structure
#
# Purpose:
# Connect findings from EDA-04, EDA-05, EDA-07 and EDA-09 to address the
# project's central methodological question:
#
#   Are observed species patterns associated only with geography, or does
#   environmental context retain descriptive structure beyond geographic
#   separation?
#
# Two integrated analyses are performed:
#
#   A. Species-pair co-occurrence vs geographic footprint overlap.
#   B. Environmental distance vs species-composition difference among
#      0.5-degree cells, including within geographic-distance bands.
#
# This script is exploratory only. It fits no classifier, reports no predictive
# performance and uses no inferential p-values. Cell-pair observations are not
# independent, so correlations are interpreted descriptively.
#
# Inputs:
#   data/processed/frog_primary_multiclass.rds
#   outputs/tables/eda04_pairwise_cell_overlap.csv
#   outputs/tables/eda07_cooccurrence_pairs.csv
#
# Outputs:
#   outputs/tables/eda09b_cooccurrence_geography_pairs.csv
#   outputs/tables/eda09b_cooccurrence_geography_summary.csv
#   outputs/tables/eda09b_static_environment_pca_variance.csv
#   outputs/tables/eda09b_environment_composition_distance_summary.csv
#   outputs/tables/eda09b_environment_quartile_summary.csv
#   outputs/tables/eda09b_integrated_context_summary.csv
#   outputs/figures/EDA09B/eda09b_cooccurrence_vs_geography.png
#   outputs/figures/EDA09B/eda09b_environment_vs_composition.png
#
# Privacy:
# Exact coordinates are used only in memory to assign coarse 0.5-degree cells.
# No event IDs, exact coordinates or cell IDs are written to output.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

PRIMARY_FILE <- "data/processed/frog_primary_multiclass.rds"
GEOGRAPHY_FILE <- "outputs/tables/eda04_pairwise_cell_overlap.csv"
COOCCURRENCE_FILE <- "outputs/tables/eda07_cooccurrence_pairs.csv"

TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA09B"

GRID_SIZE <- 0.5
STABLE_CELL_MIN_EVENTS <- 20L

STATIC_ENV_FEATURES <- c(
  paste0("BIO", 1:19),
  "elevation"
)

required_files <- c(
  PRIMARY_FILE,
  GEOGRAPHY_FILE,
  COOCCURRENCE_FILE
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files)) {
  stop(
    "Missing EDA-09b input(s): ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

frogs <- as.data.frame(
  readRDS(PRIMARY_FILE)
)

geo_pairs <- read.csv(
  GEOGRAPHY_FILE,
  stringsAsFactors = FALSE
)

cooccurrence <- read.csv(
  COOCCURRENCE_FILE,
  stringsAsFactors = FALSE
)

required_primary <- c(
  "eventID",
  "scientificName",
  "decimalLatitude",
  "decimalLongitude",
  STATIC_ENV_FEATURES
)

required_geo <- c(
  "grid_size_degrees",
  "species_a",
  "species_b",
  "jaccard_overlap",
  "overlap_coefficient"
)

required_cooccurrence <- c(
  "species_a",
  "species_b",
  "cooccurring_events",
  "events_with_a",
  "events_with_b",
  "jaccard"
)

stopifnot(
  nrow(frogs) == 247406L,
  all(required_primary %in% names(frogs)),
  all(required_geo %in% names(geo_pairs)),
  all(required_cooccurrence %in% names(cooccurrence)),
  length(unique(frogs$scientificName)) == 18L,
  length(STATIC_ENV_FEATURES) == 20L,
  length(unique(frogs$eventID)) == nrow(frogs)
)

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

canonicalise_pairs <- function(data) {

  first <- ifelse(
    data$species_a <= data$species_b,
    data$species_a,
    data$species_b
  )

  second <- ifelse(
    data$species_a <= data$species_b,
    data$species_b,
    data$species_a
  )

  data$pair_species_1 <- first
  data$pair_species_2 <- second

  data
}

safe_spearman <- function(x, y) {

  keep <- is.finite(x) & is.finite(y)

  x <- x[keep]
  y <- y[keep]

  if (
    length(x) < 3L ||
      sd(x) == 0 ||
      sd(y) == 0
  ) {
    return(NA_real_)
  }

  suppressWarnings(
    cor(
      x,
      y,
      method = "spearman"
    )
  )
}

# Descriptive partial Spearman correlation:
# rank x and y, residualise each against ranked z, then correlate residuals.
# No p-value is used because cell-pair observations are non-independent.
partial_spearman <- function(x, y, z) {

  keep <-
    is.finite(x) &
    is.finite(y) &
    is.finite(z)

  x <- x[keep]
  y <- y[keep]
  z <- z[keep]

  if (
    length(x) < 4L ||
      sd(x) == 0 ||
      sd(y) == 0 ||
      sd(z) == 0
  ) {
    return(NA_real_)
  }

  rx <- rank(
    x,
    ties.method = "average"
  )

  ry <- rank(
    y,
    ties.method = "average"
  )

  rz <- rank(
    z,
    ties.method = "average"
  )

  x_residual <- residuals(
    lm(
      rx ~ rz
    )
  )

  y_residual <- residuals(
    lm(
      ry ~ rz
    )
  )

  cor(
    x_residual,
    y_residual
  )
}

haversine_km <- function(lon1, lat1, lon2, lat2) {

  radius_km <- 6371.0088
  to_rad <- pi / 180

  lon1 <- lon1 * to_rad
  lat1 <- lat1 * to_rad
  lon2 <- lon2 * to_rad
  lat2 <- lat2 * to_rad

  dlon <- lon2 - lon1
  dlat <- lat2 - lat1

  a <-
    sin(dlat / 2)^2 +
    cos(lat1) *
      cos(lat2) *
      sin(dlon / 2)^2

  2 *
    radius_km *
    asin(
      pmin(
        1,
        sqrt(a)
      )
    )
}

summarise_pair_relationships <- function(pair_data,
                                         cohort_label) {

  pair_data %>%
    group_by(distance_bin) %>%
    summarise(
      cohort = cohort_label,
      cell_pairs = n(),
      median_geographic_distance_km =
        median(geographic_distance_km),
      median_environmental_distance =
        median(environmental_distance),
      median_composition_tvd =
        median(composition_tvd),
      q25_composition_tvd =
        unname(
          quantile(
            composition_tvd,
            0.25
          )
        ),
      q75_composition_tvd =
        unname(
          quantile(
            composition_tvd,
            0.75
          )
        ),
      spearman_environment_vs_composition =
        safe_spearman(
          environmental_distance,
          composition_tvd
        ),
      spearman_geography_vs_composition =
        safe_spearman(
          geographic_distance_km,
          composition_tvd
        ),
      spearman_geography_vs_environment =
        safe_spearman(
          geographic_distance_km,
          environmental_distance
        ),
      .groups = "drop"
    ) %>%
    select(
      cohort,
      everything()
    )
}

# -------------------------------------------------------------------------
# A. Multi-species co-occurrence versus geographic footprint overlap
# -------------------------------------------------------------------------

stopifnot(
  nrow(cooccurrence) == 153L
)

cooccurrence_canonical <-
  canonicalise_pairs(cooccurrence) %>%
  transmute(
    pair_species_1,
    pair_species_2,
    cooccurring_events,
    events_with_species_1 = ifelse(
      species_a == pair_species_1,
      events_with_a,
      events_with_b
    ),
    events_with_species_2 = ifelse(
      species_b == pair_species_2,
      events_with_b,
      events_with_a
    ),
    cooccurrence_jaccard = jaccard
  )

stopifnot(
  !anyDuplicated(
    paste(
      cooccurrence_canonical$pair_species_1,
      cooccurrence_canonical$pair_species_2,
      sep = "||"
    )
  )
)

geo_canonical <- canonicalise_pairs(
  geo_pairs
)

geo_05 <- geo_canonical %>%
  filter(
    grid_size_degrees == 0.5
  ) %>%
  transmute(
    pair_species_1,
    pair_species_2,
    geographic_jaccard_05deg =
      jaccard_overlap,
    geographic_overlap_coefficient_05deg =
      overlap_coefficient
  )

geo_10 <- geo_canonical %>%
  filter(
    grid_size_degrees == 1
  ) %>%
  transmute(
    pair_species_1,
    pair_species_2,
    geographic_jaccard_1deg =
      jaccard_overlap,
    geographic_overlap_coefficient_1deg =
      overlap_coefficient
  )

stopifnot(
  nrow(geo_05) == 153L,
  nrow(geo_10) == 153L
)

cooccurrence_geography_pairs <-
  cooccurrence_canonical %>%
  inner_join(
    geo_05,
    by = c(
      "pair_species_1",
      "pair_species_2"
    )
  ) %>%
  inner_join(
    geo_10,
    by = c(
      "pair_species_1",
      "pair_species_2"
    )
  ) %>%
  arrange(
    desc(cooccurrence_jaccard)
  )

stopifnot(
  nrow(cooccurrence_geography_pairs) == 153L
)

cooccurrence_geography_summary <- data.frame(
  measure = c(
    "species_pairs",
    "spearman_cooccurrence_vs_geographic_jaccard_05deg",
    "spearman_cooccurrence_vs_geographic_overlap_coefficient_05deg",
    "spearman_cooccurrence_vs_geographic_jaccard_1deg",
    "spearman_cooccurrence_vs_geographic_overlap_coefficient_1deg"
  ),
  value = c(
    nrow(cooccurrence_geography_pairs),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_jaccard_05deg
    ),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_overlap_coefficient_05deg
    ),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_jaccard_1deg
    ),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_overlap_coefficient_1deg
    )
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# B. Environmental versus species-composition difference among 0.5° cells
#
# Static environment uses BIO1-BIO19 plus elevation only. The two
# event-month climatology variables are intentionally excluded here so this
# analysis measures broad environmental context rather than re-introducing
# seasonal recording composition into the cell-level environmental distance.
# -------------------------------------------------------------------------

cell_x <- floor(
  frogs$decimalLongitude /
    GRID_SIZE
)

cell_y <- floor(
  frogs$decimalLatitude /
    GRID_SIZE
)

grid <- data.frame(
  frogs,
  cell_x = cell_x,
  cell_y = cell_y,
  cell_id = paste(
    cell_x,
    cell_y,
    sep = "_"
  ),
  cell_lon =
    (cell_x + 0.5) *
      GRID_SIZE,
  cell_lat =
    (cell_y + 0.5) *
      GRID_SIZE,
  stringsAsFactors = FALSE
)

cell_meta <- grid %>%
  distinct(
    cell_id,
    cell_lon,
    cell_lat
  ) %>%
  left_join(
    grid %>%
      count(
        cell_id,
        name = "events"
      ),
    by = "cell_id"
  )

cell_species_counts <- grid %>%
  count(
    cell_id,
    scientificName,
    name = "events"
  )

cell_species_table <- xtabs(
  events ~ cell_id + scientificName,
  data = cell_species_counts
)

complete_static_environment <-
  complete.cases(
    grid[STATIC_ENV_FEATURES]
  )

grid_environment_complete <-
  grid[
    complete_static_environment,
    ,
    drop = FALSE
  ]

cell_environment <- grid_environment_complete %>%
  group_by(
    cell_id
  ) %>%
  summarise(
    across(
      all_of(STATIC_ENV_FEATURES),
      median
    ),
    complete_environment_events = n(),
    .groups = "drop"
  )

usable_cell_ids <- intersect(
  rownames(cell_species_table),
  cell_environment$cell_id
)

usable_cell_ids <- sort(
  usable_cell_ids
)

stopifnot(
  length(usable_cell_ids) > 0L
)

usable_meta <- cell_meta[
  match(
    usable_cell_ids,
    cell_meta$cell_id
  ),
  ,
  drop = FALSE
]

usable_environment <- cell_environment[
  match(
    usable_cell_ids,
    cell_environment$cell_id
  ),
  ,
  drop = FALSE
]

stopifnot(
  all(
    usable_meta$cell_id ==
      usable_cell_ids
  ),
  all(
    usable_environment$cell_id ==
      usable_cell_ids
  )
)

cell_composition <- cell_species_table[
  usable_cell_ids,
  ,
  drop = FALSE
]

cell_composition <-
  cell_composition /
  rowSums(
    cell_composition
  )

# -------------------------------------------------------------------------
# Cell-level static-environment PCA
#
# PCA is performed on cell medians, not event rows. This gives each occupied
# environmental cell equal weight rather than allowing recording-dense cells
# to dominate the environmental representation.
# -------------------------------------------------------------------------

cell_environment_matrix <- as.matrix(
  usable_environment[
    STATIC_ENV_FEATURES
  ]
)

environment_pca <- prcomp(
  cell_environment_matrix,
  center = TRUE,
  scale. = TRUE
)

environment_pca_variance <-
  environment_pca$sdev^2

environment_pca_share <-
  environment_pca_variance /
  sum(environment_pca_variance)

environment_pca_cumulative <-
  cumsum(
    environment_pca_share
  )

pcs_for_90_percent <-
  which(
    environment_pca_cumulative >=
      0.90
  )[1]

static_environment_pca_variance <- data.frame(
  component = paste0(
    "PC",
    seq_along(
      environment_pca_variance
    )
  ),
  variance =
    environment_pca_variance,
  variance_share =
    environment_pca_share,
  cumulative_variance_share =
    environment_pca_cumulative,
  stringsAsFactors = FALSE
)

environment_scores <- environment_pca$x[
  ,
  seq_len(
    pcs_for_90_percent
  ),
  drop = FALSE
]

# -------------------------------------------------------------------------
# Pairwise cell distances and species-composition TVD
# -------------------------------------------------------------------------

cell_pairs <- combn(
  seq_along(
    usable_cell_ids
  ),
  2
)

pair_count <- ncol(
  cell_pairs
)

pair_i <- cell_pairs[1, ]
pair_j <- cell_pairs[2, ]

geographic_distance_km <- numeric(
  pair_count
)

environmental_distance <- numeric(
  pair_count
)

composition_tvd <- numeric(
  pair_count
)

chunk_size <- 50000L

for (
  start in seq.int(
    1L,
    pair_count,
    by = chunk_size
  )
) {

  end <- min(
    start +
      chunk_size -
      1L,
    pair_count
  )

  idx <- start:end

  i <- pair_i[idx]
  j <- pair_j[idx]

  geographic_distance_km[idx] <-
    haversine_km(
      usable_meta$cell_lon[i],
      usable_meta$cell_lat[i],
      usable_meta$cell_lon[j],
      usable_meta$cell_lat[j]
    )

  environmental_difference <-
    environment_scores[
      i,
      ,
      drop = FALSE
    ] -
    environment_scores[
      j,
      ,
      drop = FALSE
    ]

  environmental_distance[idx] <-
    sqrt(
      rowSums(
        environmental_difference^2
      )
    )

  composition_tvd[idx] <-
    0.5 *
    rowSums(
      abs(
        cell_composition[
          i,
          ,
          drop = FALSE
        ] -
        cell_composition[
          j,
          ,
          drop = FALSE
        ]
      )
    )
}

distance_breaks <- c(
  -Inf,
  50,
  100,
  250,
  500,
  1000,
  Inf
)

distance_labels <- c(
  "<50",
  "50-100",
  "100-250",
  "250-500",
  "500-1000",
  "1000+"
)

pair_data <- data.frame(
  geographic_distance_km =
    geographic_distance_km,
  environmental_distance =
    environmental_distance,
  composition_tvd =
    composition_tvd,
  cell_i_events =
    usable_meta$events[
      pair_i
    ],
  cell_j_events =
    usable_meta$events[
      pair_j
    ],
  stringsAsFactors = FALSE
)

pair_data$distance_bin <- cut(
  pair_data$geographic_distance_km,
  breaks = distance_breaks,
  labels = distance_labels,
  right = FALSE
)

stable_pair_mask <-
  pair_data$cell_i_events >=
    STABLE_CELL_MIN_EVENTS &
  pair_data$cell_j_events >=
    STABLE_CELL_MIN_EVENTS

stable_pair_data <- pair_data[
  stable_pair_mask,
  ,
  drop = FALSE
]

environment_composition_distance_summary <-
  bind_rows(
    summarise_pair_relationships(
      pair_data,
      "all_environment_usable_cells"
    ),
    summarise_pair_relationships(
      stable_pair_data,
      paste0(
        "both_cells_at_least_",
        STABLE_CELL_MIN_EVENTS,
        "_events"
      )
    )
  )

# -------------------------------------------------------------------------
# Environmental-distance quartiles within geographic-distance bands
#
# This gives a direct visual question:
# Within cells already separated by similar geographic distances, does species
# composition differ more across environmentally dissimilar cell pairs?
# -------------------------------------------------------------------------

stable_pair_quartiles <- stable_pair_data %>%
  filter(
    !is.na(distance_bin)
  ) %>%
  group_by(
    distance_bin
  ) %>%
  mutate(
    environmental_distance_quartile =
      ntile(
        environmental_distance,
        4
      )
  ) %>%
  ungroup()

environment_quartile_summary <-
  stable_pair_quartiles %>%
  group_by(
    distance_bin,
    environmental_distance_quartile
  ) %>%
  summarise(
    cell_pairs = n(),
    median_environmental_distance =
      median(
        environmental_distance
      ),
    median_composition_tvd =
      median(
        composition_tvd
      ),
    q25_composition_tvd =
      unname(
        quantile(
          composition_tvd,
          0.25
        )
      ),
    q75_composition_tvd =
      unname(
        quantile(
          composition_tvd,
          0.75
        )
      ),
    .groups = "drop"
  )

# -------------------------------------------------------------------------
# Integrated descriptive summary
# -------------------------------------------------------------------------

stable_cells <-
  sum(
    usable_meta$events >=
      STABLE_CELL_MIN_EVENTS
  )

integrated_context_summary <- data.frame(
  measure = c(
    "species_pairs",
    "cooccurrence_vs_geographic_jaccard_spearman_05deg",
    "cooccurrence_vs_geographic_jaccard_spearman_1deg",
    "occupied_05deg_cells",
    "environment_usable_05deg_cells",
    "stable_environment_usable_05deg_cells",
    "all_environment_usable_cell_pairs",
    "stable_cell_pairs",
    "static_environment_predictors",
    "static_environment_pcs_for_90_percent_variance",
    "static_environment_variance_captured_by_retained_pcs",
    "all_pairs_environment_vs_composition_spearman",
    "all_pairs_geography_vs_composition_spearman",
    "all_pairs_geography_vs_environment_spearman",
    "all_pairs_partial_environment_vs_composition_controlling_geography",
    "all_pairs_partial_geography_vs_composition_controlling_environment",
    "stable_pairs_environment_vs_composition_spearman",
    "stable_pairs_geography_vs_composition_spearman",
    "stable_pairs_geography_vs_environment_spearman",
    "stable_pairs_partial_environment_vs_composition_controlling_geography",
    "stable_pairs_partial_geography_vs_composition_controlling_environment"
  ),
  value = c(
    nrow(
      cooccurrence_geography_pairs
    ),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_jaccard_05deg
    ),
    safe_spearman(
      cooccurrence_geography_pairs$cooccurrence_jaccard,
      cooccurrence_geography_pairs$geographic_jaccard_1deg
    ),
    nrow(
      cell_meta
    ),
    length(
      usable_cell_ids
    ),
    stable_cells,
    nrow(
      pair_data
    ),
    nrow(
      stable_pair_data
    ),
    length(
      STATIC_ENV_FEATURES
    ),
    pcs_for_90_percent,
    environment_pca_cumulative[
      pcs_for_90_percent
    ],
    safe_spearman(
      pair_data$environmental_distance,
      pair_data$composition_tvd
    ),
    safe_spearman(
      pair_data$geographic_distance_km,
      pair_data$composition_tvd
    ),
    safe_spearman(
      pair_data$geographic_distance_km,
      pair_data$environmental_distance
    ),
    partial_spearman(
      pair_data$environmental_distance,
      pair_data$composition_tvd,
      pair_data$geographic_distance_km
    ),
    partial_spearman(
      pair_data$geographic_distance_km,
      pair_data$composition_tvd,
      pair_data$environmental_distance
    ),
    safe_spearman(
      stable_pair_data$environmental_distance,
      stable_pair_data$composition_tvd
    ),
    safe_spearman(
      stable_pair_data$geographic_distance_km,
      stable_pair_data$composition_tvd
    ),
    safe_spearman(
      stable_pair_data$geographic_distance_km,
      stable_pair_data$environmental_distance
    ),
    partial_spearman(
      stable_pair_data$environmental_distance,
      stable_pair_data$composition_tvd,
      stable_pair_data$geographic_distance_km
    ),
    partial_spearman(
      stable_pair_data$geographic_distance_km,
      stable_pair_data$composition_tvd,
      stable_pair_data$environmental_distance
    )
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# Figures
# -------------------------------------------------------------------------

# Figure 1: co-occurrence vs geographic footprint overlap.
cooccurrence_plot_data <- bind_rows(
  cooccurrence_geography_pairs %>%
    transmute(
      pair_species_1,
      pair_species_2,
      cooccurrence_jaccard,
      geographic_jaccard =
        geographic_jaccard_05deg,
      geographic_scale = "0.5°"
    ),
  cooccurrence_geography_pairs %>%
    transmute(
      pair_species_1,
      pair_species_2,
      cooccurrence_jaccard,
      geographic_jaccard =
        geographic_jaccard_1deg,
      geographic_scale = "1°"
    )
)

p_cooccurrence_geography <- ggplot(
  cooccurrence_plot_data,
  aes(
    x = geographic_jaccard,
    y = cooccurrence_jaccard
  )
) +
  geom_point(
    alpha = 0.65,
    size = 1.8
  ) +
  facet_wrap(
    ~ geographic_scale,
    nrow = 1
  ) +
  labs(
    title = "Multi-species co-occurrence versus geographic footprint overlap",
    subtitle = "Each point is one pair among the 18 target species",
    x = "Geographic occupied-cell Jaccard overlap",
    y = "Multi-species co-occurrence Jaccard"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda09b_cooccurrence_vs_geography.png"
  ),
  p_cooccurrence_geography,
  width = 10,
  height = 5.8,
  dpi = 180
)

# Figure 2: environmental difference vs composition difference within
# decision-relevant geographic-distance bands. Use stable cells only so that
# species-composition proportions are not dominated by tiny cell samples.
decision_distance_bins <- c(
  "<50",
  "50-100",
  "100-250",
  "250-500"
)

environment_quartile_plot_data <-
  environment_quartile_summary %>%
  filter(
    as.character(
      distance_bin
    ) %in%
      decision_distance_bins
  )

environment_quartile_plot_data$distance_bin <- factor(
  as.character(
    environment_quartile_plot_data$distance_bin
  ),
  levels = decision_distance_bins
)

environment_quartile_plot_data$environmental_distance_quartile <- factor(
  environment_quartile_plot_data$environmental_distance_quartile,
  levels = 1:4,
  labels = c(
    "Q1\nmost similar",
    "Q2",
    "Q3",
    "Q4\nmost different"
  )
)

p_environment_composition <- ggplot(
  environment_quartile_plot_data,
  aes(
    x = environmental_distance_quartile,
    y = median_composition_tvd,
    group = 1
  )
) +
  geom_line(
    linewidth = 0.7
  ) +
  geom_point(
    size = 2
  ) +
  facet_wrap(
    ~ distance_bin,
    nrow = 1
  ) +
  labs(
    title = "Species-composition difference across environmental-distance quartiles",
    subtitle = paste0(
      "0.5-degree cells with at least ",
      STABLE_CELL_MIN_EVENTS,
      " events; panels hold geographic separation approximately constant"
    ),
    x = "Environmental distance within geographic band",
    y = "Median species-composition TVD"
  ) +
  theme_minimal() +
  theme(
    axis.text.x = element_text(
      size = 7
    )
  )

ggsave(
  file.path(
    FIG_DIR,
    "eda09b_environment_vs_composition.png"
  ),
  p_environment_composition,
  width = 12,
  height = 5.8,
  dpi = 180
)

# -------------------------------------------------------------------------
# Write aggregate outputs
# -------------------------------------------------------------------------

write.csv(
  cooccurrence_geography_pairs,
  file.path(
    TABLE_DIR,
    "eda09b_cooccurrence_geography_pairs.csv"
  ),
  row.names = FALSE
)

write.csv(
  cooccurrence_geography_summary,
  file.path(
    TABLE_DIR,
    "eda09b_cooccurrence_geography_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  static_environment_pca_variance,
  file.path(
    TABLE_DIR,
    "eda09b_static_environment_pca_variance.csv"
  ),
  row.names = FALSE
)

write.csv(
  environment_composition_distance_summary,
  file.path(
    TABLE_DIR,
    "eda09b_environment_composition_distance_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  environment_quartile_summary,
  file.path(
    TABLE_DIR,
    "eda09b_environment_quartile_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  integrated_context_summary,
  file.path(
    TABLE_DIR,
    "eda09b_integrated_context_summary.csv"
  ),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-09B INTEGRATED ECOLOGICAL VS GEOGRAPHIC STRUCTURE\n")
cat("============================================================\n")

cat("\nCo-occurrence versus geography summary:\n")
print(
  cooccurrence_geography_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nTop 15 co-occurring species pairs with geographic overlap:\n")
print(
  head(
    cooccurrence_geography_pairs,
    15
  ),
  row.names = FALSE,
  digits = 4
)

cat("\nStatic environmental PCA variance:\n")
print(
  head(
    static_environment_pca_variance,
    10
  ),
  row.names = FALSE,
  digits = 5
)

cat(sprintf(
  "\nPCs required for >=90%% of static cell-level environmental variance: %d\n",
  pcs_for_90_percent
))

cat("\nEnvironmental distance versus composition difference by geographic band:\n")
print(
  environment_composition_distance_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nEnvironmental-distance quartile summary:\n")
print(
  environment_quartile_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nIntegrated context summary:\n")
print(
  integrated_context_summary,
  row.names = FALSE,
  digits = 6
)

cat("\nEDA-09B COMPLETE\n")
cat(
  paste0(
    "No classifier was fitted. Correlations are descriptive only; ",
    "cell-pair observations are non-independent and no inferential p-values ",
    "were used.\n"
  )
)
