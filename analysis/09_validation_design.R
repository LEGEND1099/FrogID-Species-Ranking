# =========================================================================
# EDA-09: Validation-design diagnostics
#
# Purpose:
# Use the observed class and geographic structure to diagnose whether ordinary
# row-wise validation would share substantial spatial context across folds and
# whether candidate whole-cell blocking scales retain enough class support.
#
# This script does NOT fit a classifier and does NOT choose a final validation
# strategy. It produces evidence for that later decision.
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs:
#   outputs/tables/eda09_random_fold_spatial_sharing.csv
#   outputs/tables/eda09_species_block_support.csv
#   outputs/tables/eda09_block_scale_summary.csv
#   outputs/tables/eda09_composition_distance_summary.csv
#   outputs/tables/eda09_validation_summary.csv
#   outputs/figures/EDA09/eda09_block_support.png
#   outputs/figures/EDA09/eda09_composition_distance.png
#
# No exact coordinate pairs, cell IDs, or event IDs are written to outputs.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA09"

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
  "decimalLongitude"
)

stopifnot(
  nrow(frogs) == 247406L,
  all(required %in% names(frogs)),
  length(unique(frogs$scientificName)) == 18L,
  length(unique(frogs$eventID)) == nrow(frogs),
  !any(is.na(frogs$decimalLatitude)),
  !any(is.na(frogs$decimalLongitude)),
  all(is.finite(frogs$decimalLatitude)),
  all(is.finite(frogs$decimalLongitude))
)

species_order <- names(
  sort(table(frogs$scientificName), decreasing = TRUE)
)

GRID_SIZES <- c(0.25, 0.5, 1, 2)
K_VALUES <- c(3L, 5L, 10L)

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

entropy_bits <- function(p) {
  p <- p[p > 0]

  if (!length(p)) {
    return(0)
  }

  -sum(p * log2(p))
}

make_grid <- function(data, size) {

  cell_x <- floor(data$decimalLongitude / size)
  cell_y <- floor(data$decimalLatitude / size)

  data.frame(
    data,
    cell_x = cell_x,
    cell_y = cell_y,
    cell_id = paste(cell_x, cell_y, sep = "_"),
    cell_lon = (cell_x + 0.5) * size,
    cell_lat = (cell_y + 0.5) * size,
    stringsAsFactors = FALSE
  )
}

# Probability that n observations assigned independently and uniformly to
# k folds appear in more than one fold.
#
# P(all observations in one fold) = k * (1/k)^n = k^(1-n)
split_group_probability <- function(n, k) {

  ifelse(
    n <= 1L,
    0,
    1 - k^(1 - n)
  )
}

summarise_random_fold_sharing <- function(group_sizes,
                                          group_type,
                                          k) {

  n <- as.numeric(group_sizes)
  p_split <- split_group_probability(n, k)
  repeated <- n > 1L

  data.frame(
    group_type = group_type,
    folds = k,
    groups = length(n),
    groups_with_multiple_events = sum(repeated),
    events = sum(n),
    expected_groups_spanning_multiple_folds =
      sum(p_split),
    expected_groups_spanning_multiple_folds_percent =
      100 * mean(p_split),
    expected_repeated_groups_spanning_multiple_folds_percent =
      100 * sum(p_split[repeated]) / sum(repeated),
    expected_events_in_groups_spanning_multiple_folds =
      sum(n * p_split),
    expected_events_in_groups_spanning_multiple_folds_percent =
      100 * sum(n * p_split) / sum(n),
    expected_repeated_group_events_spanning_multiple_folds_percent =
      100 * sum(n[repeated] * p_split[repeated]) / sum(n[repeated]),
    stringsAsFactors = FALSE
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
    cos(lat1) * cos(lat2) * sin(dlon / 2)^2

  2 * radius_km * asin(pmin(1, sqrt(a)))
}

# -------------------------------------------------------------------------
# 1. Expected spatial sharing under ordinary row-wise random folds
# -------------------------------------------------------------------------

# Exact coordinate IDs remain internal only.
coordinate_id <- paste(
  frogs$decimalLatitude,
  frogs$decimalLongitude,
  sep = "|"
)

coordinate_sizes <- as.numeric(
  table(coordinate_id)
)

sharing_rows <- list()
sharing_index <- 1L

for (k in K_VALUES) {

  sharing_rows[[sharing_index]] <-
    summarise_random_fold_sharing(
      coordinate_sizes,
      "exact_coordinate",
      k
    )

  sharing_index <- sharing_index + 1L
}

for (size in GRID_SIZES) {

  grid <- make_grid(frogs, size)

  grid_sizes <- as.numeric(
    table(grid$cell_id)
  )

  for (k in K_VALUES) {

    sharing_rows[[sharing_index]] <-
      summarise_random_fold_sharing(
        grid_sizes,
        paste0(size, "_degree_cell"),
        k
      )

    sharing_index <- sharing_index + 1L
  }
}

random_fold_spatial_sharing <- do.call(
  rbind,
  sharing_rows
)

# -------------------------------------------------------------------------
# 2. Per-species support across candidate spatial block sizes
# -------------------------------------------------------------------------

support_rows <- list()
support_index <- 1L

for (size in GRID_SIZES) {

  grid <- make_grid(frogs, size)

  species_cell_counts <- grid %>%
    count(
      scientificName,
      cell_id,
      name = "events"
    )

  species_support <- species_cell_counts %>%
  group_by(scientificName) %>%
  summarise(
    occupied_blocks = n(),
    block_entropy_bits =
      entropy_bits(events / sum(events)),
    effective_blocks =
      2^entropy_bits(events / sum(events)),
    largest_block_share_percent =
      100 * max(events) / sum(events),
    top_5_blocks_share_percent =
      100 * sum(
        head(
          sort(events, decreasing = TRUE),
          5
        )
      ) / sum(events),
    median_events_per_occupied_block =
      median(events),
    events = sum(events),
    .groups = "drop"
  )

  species_support$grid_size_degrees <- size

  support_rows[[support_index]] <- species_support

  support_index <- support_index + 1L
}

species_block_support <- bind_rows(
  support_rows
) %>%
  select(
    grid_size_degrees,
    scientificName,
    everything()
  ) %>%
  arrange(
    grid_size_degrees,
    match(scientificName, species_order)
  )

# -------------------------------------------------------------------------
# 3. Aggregate block-scale feasibility summaries
# -------------------------------------------------------------------------

block_scale_rows <- list()
block_scale_index <- 1L

for (size in GRID_SIZES) {

  grid <- make_grid(frogs, size)

  block_counts <- grid %>%
    count(
      cell_id,
      name = "events"
    )

  z <- species_block_support[
    species_block_support$grid_size_degrees == size,
  ]

  block_scale_rows[[block_scale_index]] <- data.frame(
    grid_size_degrees = size,
    occupied_blocks = nrow(block_counts),
    median_events_per_block =
      median(block_counts$events),
    maximum_events_in_one_block =
      max(block_counts$events),
    largest_block_event_share_percent =
      100 * max(block_counts$events) / nrow(frogs),

    minimum_species_occupied_blocks =
      min(z$occupied_blocks),
    median_species_occupied_blocks =
      median(z$occupied_blocks),

    minimum_species_effective_blocks =
      min(z$effective_blocks),
    median_species_effective_blocks =
      median(z$effective_blocks),

    maximum_species_largest_block_share_percent =
      max(z$largest_block_share_percent),

    species_with_fewer_than_3_occupied_blocks =
      sum(z$occupied_blocks < 3),
    species_with_fewer_than_5_occupied_blocks =
      sum(z$occupied_blocks < 5),
    species_with_fewer_than_10_occupied_blocks =
      sum(z$occupied_blocks < 10),

    species_with_effective_blocks_below_3 =
      sum(z$effective_blocks < 3),
    species_with_effective_blocks_below_5 =
      sum(z$effective_blocks < 5),
    species_with_effective_blocks_below_10 =
      sum(z$effective_blocks < 10),

    stringsAsFactors = FALSE
  )

  block_scale_index <- block_scale_index + 1L
}

block_scale_summary <- bind_rows(
  block_scale_rows
)

# -------------------------------------------------------------------------
# 4. Does species composition become less similar with distance?
#
# Use 0.5-degree cells because EDA-04 showed this resolution retains many
# occupied cells while still representing meaningful coarse spatial context.
#
# This is descriptive only. No independence threshold is assumed.
# -------------------------------------------------------------------------

grid_05 <- make_grid(frogs, 0.5)

cell_meta <- grid_05 %>%
  distinct(
    cell_id,
    cell_lon,
    cell_lat
  ) %>%
  arrange(cell_id)

cell_species_counts <- grid_05 %>%
  count(
    cell_id,
    scientificName,
    name = "events"
  )

cell_table <- xtabs(
  events ~ cell_id + scientificName,
  data = cell_species_counts
)

# Match cell metadata to table row order.
cell_meta <- cell_meta[
  match(
    rownames(cell_table),
    cell_meta$cell_id
  ),
]

stopifnot(
  all(cell_meta$cell_id == rownames(cell_table))
)

cell_events <- rowSums(cell_table)

cell_prop <- cell_table / cell_events

dominant_species <- colnames(cell_prop)[
  max.col(
    cell_prop,
    ties.method = "first"
  )
]

pairs <- combn(
  seq_len(nrow(cell_prop)),
  2
)

pair_count <- ncol(pairs)

distance_km <- numeric(pair_count)
composition_tvd <- numeric(pair_count)
same_dominant_species <- logical(pair_count)

chunk_size <- 50000L

for (start in seq.int(
  1L,
  pair_count,
  by = chunk_size
)) {

  end <- min(
    start + chunk_size - 1L,
    pair_count
  )

  idx <- start:end

  i <- pairs[1, idx]
  j <- pairs[2, idx]

  distance_km[idx] <- haversine_km(
    cell_meta$cell_lon[i],
    cell_meta$cell_lat[i],
    cell_meta$cell_lon[j],
    cell_meta$cell_lat[j]
  )

  composition_tvd[idx] <-
    0.5 * rowSums(
      abs(
        cell_prop[i, , drop = FALSE] -
          cell_prop[j, , drop = FALSE]
      )
    )

  same_dominant_species[idx] <-
    dominant_species[i] ==
      dominant_species[j]
}

distance_breaks <- c(
  -Inf,
  50,
  100,
  250,
  500,
  1000,
  2000,
  Inf
)

distance_labels <- c(
  "<50",
  "50-100",
  "100-250",
  "250-500",
  "500-1000",
  "1000-2000",
  "2000+"
)

distance_bin <- cut(
  distance_km,
  breaks = distance_breaks,
  labels = distance_labels,
  right = FALSE
)

composition_distance_summary <- data.frame(
  distance_bin = distance_bin,
  composition_tvd = composition_tvd,
  same_dominant_species = same_dominant_species
) %>%
  group_by(distance_bin) %>%
  summarise(
    cell_pairs = n(),
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
    mean_composition_tvd =
      mean(composition_tvd),
    same_dominant_species_percent =
      100 * mean(same_dominant_species),
    .groups = "drop"
  )

distance_tvd_spearman <- suppressWarnings(
  cor(
    distance_km,
    composition_tvd,
    method = "spearman"
  )
)

# -------------------------------------------------------------------------
# 5. Compact validation-design summary
# -------------------------------------------------------------------------

validation_summary <- data.frame(
  measure = c(
    "events",
    "species",
    "exact_coordinate_groups",
    "events_at_repeated_exact_coordinates_percent",
    "cells_used_for_distance_analysis_05deg",
    "cell_pairs_used_for_distance_analysis",
    "distance_vs_composition_tvd_spearman"
  ),
  value = c(
    nrow(frogs),
    length(species_order),
    length(coordinate_sizes),
    100 * sum(
      coordinate_sizes[
        coordinate_sizes > 1L
      ]
    ) / nrow(frogs),
    nrow(cell_prop),
    pair_count,
    distance_tvd_spearman
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# 6. Figures
# -------------------------------------------------------------------------

# Figure 1: effective number of occupied blocks per species.
plot_support <- species_block_support

plot_support$grid_label <- factor(
  paste0(
    plot_support$grid_size_degrees,
    "\u00B0"
  ),
  levels = paste0(
    GRID_SIZES,
    "\u00B0"
  )
)

p_block_support <- ggplot(
  plot_support,
  aes(
    x = grid_label,
    y = effective_blocks
  )
) +
  geom_boxplot(
    outlier.shape = NA
  ) +
  geom_jitter(
    width = 0.12,
    alpha = 0.65,
    size = 1.7
  ) +
  labs(
    title = "Effective geographic support across candidate block sizes",
    subtitle = paste0(
      "Each point is one target species; effective blocks account for ",
      "uneven event concentration"
    ),
    x = "Candidate block size",
    y = "Effective number of occupied blocks"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda09_block_support.png"
  ),
  p_block_support,
  width = 8,
  height = 6,
  dpi = 180
)

# Figure 2: species-composition difference by geographic distance.
p_distance <- ggplot(
  composition_distance_summary,
  aes(
    x = distance_bin,
    y = median_composition_tvd,
    group = 1
  )
) +
  geom_ribbon(
    aes(
      ymin = q25_composition_tvd,
      ymax = q75_composition_tvd
    ),
    alpha = 0.20,
    group = 1
  ) +
  geom_line(
    linewidth = 0.8
  ) +
  geom_point(
    size = 2
  ) +
  labs(
    title = "Species-composition difference by spatial separation",
    subtitle = paste0(
      "Total-variation distance between species distributions of ",
      "0.5-degree cells"
    ),
    x = "Distance between cell centres (km)",
    y = "Median composition TVD"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda09_composition_distance.png"
  ),
  p_distance,
  width = 8,
  height = 6,
  dpi = 180
)

# -------------------------------------------------------------------------
# 7. Write aggregate outputs
# -------------------------------------------------------------------------

write.csv(
  random_fold_spatial_sharing,
  file.path(
    TABLE_DIR,
    "eda09_random_fold_spatial_sharing.csv"
  ),
  row.names = FALSE
)

write.csv(
  species_block_support,
  file.path(
    TABLE_DIR,
    "eda09_species_block_support.csv"
  ),
  row.names = FALSE
)

write.csv(
  block_scale_summary,
  file.path(
    TABLE_DIR,
    "eda09_block_scale_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  composition_distance_summary,
  file.path(
    TABLE_DIR,
    "eda09_composition_distance_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  validation_summary,
  file.path(
    TABLE_DIR,
    "eda09_validation_summary.csv"
  ),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# 8. Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-09 VALIDATION-DESIGN DIAGNOSTICS\n")
cat("============================================================\n")

cat("\nExpected spatial sharing under ordinary row-wise random folds:\n")
print(
  random_fold_spatial_sharing,
  row.names = FALSE,
  digits = 5
)

cat("\nCandidate spatial-block support:\n")
print(
  block_scale_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nSpecies block support:\n")
print(
  species_block_support,
  row.names = FALSE,
  digits = 4
)

cat("\nSpecies-composition difference by distance:\n")
print(
  composition_distance_summary,
  row.names = FALSE,
  digits = 4
)

cat(sprintf(
  paste0(
    "\nSpearman correlation between cell-pair distance and ",
    "composition TVD: %.4f\n"
  ),
  distance_tvd_spearman
))

cat("\nEDA-09 COMPLETE\n")
cat(
  paste0(
    "No classifier was fitted and no final validation strategy, ",
    "fold count or block size was selected.\n"
  )
)