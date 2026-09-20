# =========================================================================
# EDA-04: Geographic structure
#
# Purpose:
# Describe the spatial structure of the primary FrogID multiclass cohort
# before making any decision about geographic predictors or validation design.
#
# Questions:
#   1. How geographically concentrated are recording events?
#   2. How much repeated-location structure exists?
#   3. How geographically concentrated are individual species?
#   4. How strongly do species' coarse geographic footprints overlap?
#   5. How homogeneous is species composition within coarse spatial cells?
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs contain only aggregate spatial summaries. Exact coordinate pairs,
# event IDs and observer-level information are never written to disk.
#
# No classifier is fitted and no validation strategy is selected here.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA04"

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

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

make_grid <- function(data, size) {

  cell_x <- floor(data$decimalLongitude / size)
  cell_y <- floor(data$decimalLatitude / size)

  data.frame(
    data,
    cell_id = paste(cell_x, cell_y, sep = "_"),
    cell_lon = (cell_x + 0.5) * size,
    cell_lat = (cell_y + 0.5) * size,
    stringsAsFactors = FALSE
  )
}

entropy_bits <- function(p) {
  p <- p[p > 0]
  -sum(p * log2(p))
}

cell_structure <- function(data, size, species_entropy) {

  grid <- make_grid(data, size)

  cell_counts <- grid %>%
    count(cell_id, name = "events") %>%
    arrange(desc(events))

  cell_species <- grid %>%
    count(cell_id, scientificName, name = "events")

  cell_stats <- cell_species %>%
  group_by(cell_id) %>%
  summarise(
    species_present = n(),
    dominant_species_events = max(events),
    entropy = entropy_bits(events / sum(events)),
    events = sum(events),
    .groups = "drop"
  )

  top_1pct_cells <- max(
    1L,
    ceiling(0.01 * nrow(cell_counts))
  )

  conditional_entropy <- sum(
    (cell_stats$events / nrow(data)) * cell_stats$entropy
  )

  mutual_information <- species_entropy - conditional_entropy

  data.frame(
    grid_size_degrees = size,
    occupied_cells = nrow(cell_counts),
    median_events_per_cell = median(cell_counts$events),
    maximum_events_in_one_cell = max(cell_counts$events),
    top_10_cells_event_share_percent =
      100 * sum(head(cell_counts$events, 10)) / nrow(data),
    top_1_percent_cells_event_share_percent =
      100 * sum(head(cell_counts$events, top_1pct_cells)) / nrow(data),
    single_species_cells_percent =
      100 * mean(cell_stats$species_present == 1L),
    events_in_single_species_cells_percent =
      100 * sum(
        cell_stats$events[cell_stats$species_present == 1L]
      ) / nrow(data),
    weighted_dominant_species_share_percent =
      100 * sum(cell_stats$dominant_species_events) / nrow(data),
    conditional_species_entropy_bits = conditional_entropy,
    location_species_mutual_information_bits = mutual_information,
    location_species_information_fraction =
      mutual_information / species_entropy,
    stringsAsFactors = FALSE
  )
}

pairwise_overlap <- function(data, size) {

  grid <- make_grid(data, size)

  presence <- unique(
    grid[c("scientificName", "cell_id")]
  )

  sets <- split(
    presence$cell_id,
    presence$scientificName
  )

  species <- species_order

  pair_matrix <- combn(species, 2)

  rows <- lapply(
    seq_len(ncol(pair_matrix)),
    function(i) {

      a <- pair_matrix[1, i]
      b <- pair_matrix[2, i]

      set_a <- unique(sets[[a]])
      set_b <- unique(sets[[b]])

      intersection_n <- length(intersect(set_a, set_b))
      union_n <- length(union(set_a, set_b))

      data.frame(
        grid_size_degrees = size,
        species_a = a,
        species_b = b,
        cells_a = length(set_a),
        cells_b = length(set_b),
        shared_cells = intersection_n,
        jaccard_overlap =
          if (union_n > 0) intersection_n / union_n else NA_real_,
        overlap_coefficient =
          if (min(length(set_a), length(set_b)) > 0) {
            intersection_n / min(length(set_a), length(set_b))
          } else {
            NA_real_
          },
        stringsAsFactors = FALSE
      )
    }
  )

  do.call(rbind, rows)
}

# -------------------------------------------------------------------------
# 1. Overall geographic coverage and exact-coordinate repetition
# -------------------------------------------------------------------------

# Exact coordinate IDs are used only in memory and are never written out.
coordinate_id <- paste(
  frogs$decimalLatitude,
  frogs$decimalLongitude,
  sep = "|"
)

coordinate_frequency <- table(coordinate_id)

events_at_repeated_coordinates <-
  sum(coordinate_frequency[coordinate_frequency > 1L])

geographic_summary <- data.frame(
  measure = c(
    "events",
    "unique_exact_coordinate_pairs",
    "coordinate_pairs_used_more_than_once",
    "events_at_repeated_exact_coordinates",
    "events_at_repeated_exact_coordinates_percent",
    "maximum_events_at_one_exact_coordinate",
    "latitude_min",
    "latitude_q25",
    "latitude_median",
    "latitude_q75",
    "latitude_max",
    "longitude_min",
    "longitude_q25",
    "longitude_median",
    "longitude_q75",
    "longitude_max"
  ),
  value = c(
    nrow(frogs),
    length(coordinate_frequency),
    sum(coordinate_frequency > 1L),
    events_at_repeated_coordinates,
    100 * events_at_repeated_coordinates / nrow(frogs),
    max(coordinate_frequency),
    min(frogs$decimalLatitude),
    unname(quantile(frogs$decimalLatitude, 0.25)),
    median(frogs$decimalLatitude),
    unname(quantile(frogs$decimalLatitude, 0.75)),
    max(frogs$decimalLatitude),
    min(frogs$decimalLongitude),
    unname(quantile(frogs$decimalLongitude, 0.25)),
    median(frogs$decimalLongitude),
    unname(quantile(frogs$decimalLongitude, 0.75)),
    max(frogs$decimalLongitude)
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# 2. Geographic cell concentration and species composition
# -------------------------------------------------------------------------

species_prob <- prop.table(
  table(frogs$scientificName)
)

species_entropy <- entropy_bits(
  as.numeric(species_prob)
)

grid_sizes <- c(0.25, 0.5, 1, 2)

cell_structure_summary <- do.call(
  rbind,
  lapply(
    grid_sizes,
    function(size) {
      cell_structure(
        frogs,
        size,
        species_entropy
      )
    }
  )
)

# -------------------------------------------------------------------------
# 3. Per-species geographic concentration
# -------------------------------------------------------------------------

grid_05 <- make_grid(frogs, 0.5)
grid_10 <- make_grid(frogs, 1)

species_cells_05 <- grid_05 %>%
  distinct(scientificName, cell_id) %>%
  count(scientificName, name = "occupied_cells_05deg")

species_cells_10 <- grid_10 %>%
  distinct(scientificName, cell_id) %>%
  count(scientificName, name = "occupied_cells_1deg")

species_top_cells <- grid_05 %>%
  count(scientificName, cell_id, name = "events") %>%
  group_by(scientificName) %>%
  summarise(
    top_5_cells_event_share_percent =
      100 * sum(head(sort(events, decreasing = TRUE), 5)) / sum(events),
    top_10_cells_event_share_percent =
      100 * sum(head(sort(events, decreasing = TRUE), 10)) / sum(events),
    .groups = "drop"
  )

species_geographic_summary <- frogs %>%
  mutate(
    coordinate_id_internal = coordinate_id
  ) %>%
  group_by(scientificName) %>%
  summarise(
    events = n(),
    unique_exact_coordinate_pairs =
      n_distinct(coordinate_id_internal),
    latitude_median = median(decimalLatitude),
    latitude_iqr = IQR(decimalLatitude),
    longitude_median = median(decimalLongitude),
    longitude_iqr = IQR(decimalLongitude),
    .groups = "drop"
  ) %>%
  left_join(
    species_cells_05,
    by = "scientificName"
  ) %>%
  left_join(
    species_cells_10,
    by = "scientificName"
  ) %>%
  left_join(
    species_top_cells,
    by = "scientificName"
  ) %>%
  arrange(
    match(scientificName, species_order)
  )

# -------------------------------------------------------------------------
# 4. Pairwise geographic overlap
# -------------------------------------------------------------------------

overlap_05 <- pairwise_overlap(
  frogs,
  0.5
)

overlap_10 <- pairwise_overlap(
  frogs,
  1
)

pairwise_cell_overlap <- rbind(
  overlap_05,
  overlap_10
)

# -------------------------------------------------------------------------
# 5. Aggregate figures
# -------------------------------------------------------------------------

# Figure 1: coarse national recording-density surface.
density_05 <- grid_05 %>%
  count(
    cell_lon,
    cell_lat,
    name = "events"
  )

p_density <- ggplot(
  density_05,
  aes(
    x = cell_lon,
    y = cell_lat,
    fill = log10(events)
  )
) +
  geom_tile(
    width = 0.5,
    height = 0.5
  ) +
  coord_fixed() +
  scale_fill_viridis_c(
    name = "log10(events)"
  ) +
  labs(
    title = "FrogID primary cohort: coarse recording density",
    subtitle = "Events aggregated to 0.5-degree cells; no exact locations shown",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda04_sampling_density_05deg.png"
  ),
  p_density,
  width = 8,
  height = 7,
  dpi = 180
)

# Figure 2: species coarse geographic footprints.
species_density_05 <- grid_05 %>%
  count(
    scientificName,
    cell_lon,
    cell_lat,
    name = "events"
  )

p_species <- ggplot(
  species_density_05,
  aes(
    x = cell_lon,
    y = cell_lat,
    fill = log10(events)
  )
) +
  geom_tile(
    width = 0.5,
    height = 0.5
  ) +
  facet_wrap(
    ~ scientificName,
    ncol = 3
  ) +
  coord_fixed() +
  scale_fill_viridis_c(
    name = "log10(events)"
  ) +
  labs(
    title = "Coarse geographic footprints of the 18 target species",
    subtitle = "0.5-degree cells; descriptive recording distributions only",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal() +
  theme(
    strip.text = element_text(size = 7),
    axis.text = element_text(size = 6)
  )

ggsave(
  file.path(
    FIG_DIR,
    "eda04_species_coarse_footprints.png"
  ),
  p_species,
  width = 11,
  height = 14,
  dpi = 180
)

# Figure 3: pairwise 1-degree Jaccard overlap.
overlap_plot_data <- overlap_10 %>%
  select(
    species_a,
    species_b,
    jaccard_overlap
  )

reverse_overlap <- overlap_plot_data %>%
  rename(
    original_species_a = species_a,
    original_species_b = species_b
  ) %>%
  transmute(
    species_a = original_species_b,
    species_b = original_species_a,
    jaccard_overlap = jaccard_overlap
  )

diagonal_overlap <- data.frame(
  species_a = species_order,
  species_b = species_order,
  jaccard_overlap = 1,
  stringsAsFactors = FALSE
)

overlap_plot_data <- bind_rows(
  overlap_plot_data,
  reverse_overlap,
  diagonal_overlap
)

overlap_plot_data$species_a <- factor(
  overlap_plot_data$species_a,
  levels = species_order
)

overlap_plot_data$species_b <- factor(
  overlap_plot_data$species_b,
  levels = rev(species_order)
)

p_overlap <- ggplot(
  overlap_plot_data,
  aes(
    x = species_a,
    y = species_b,
    fill = jaccard_overlap
  )
) +
  geom_tile() +
  scale_fill_viridis_c(
    limits = c(0, 1),
    name = "Jaccard"
  ) +
  labs(
    title = "Pairwise geographic overlap of target species",
    subtitle = "Jaccard overlap of occupied 1-degree cells",
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
    "eda04_species_cell_overlap.png"
  ),
  p_overlap,
  width = 11,
  height = 9,
  dpi = 180
)

# -------------------------------------------------------------------------
# 6. Write aggregate outputs
# -------------------------------------------------------------------------

write.csv(
  geographic_summary,
  file.path(
    TABLE_DIR,
    "eda04_geographic_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  cell_structure_summary,
  file.path(
    TABLE_DIR,
    "eda04_cell_structure_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  species_geographic_summary,
  file.path(
    TABLE_DIR,
    "eda04_species_geographic_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  pairwise_cell_overlap,
  file.path(
    TABLE_DIR,
    "eda04_pairwise_cell_overlap.csv"
  ),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# 7. Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-04 GEOGRAPHIC STRUCTURE\n")
cat("============================================================\n")

cat("\nOverall geographic summary:\n")
print(
  geographic_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nCoarse-cell structure:\n")
print(
  cell_structure_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nPer-species geographic summary:\n")
print(
  species_geographic_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nPairwise overlap summary:\n")

for (size in c(0.5, 1)) {

  z <- pairwise_cell_overlap[
    pairwise_cell_overlap$grid_size_degrees == size,
  ]

  cat(
    sprintf(
      paste0(
        "\n%.1f-degree cells: ",
        "median Jaccard = %.4f; ",
        "Q25 = %.4f; ",
        "Q75 = %.4f; ",
        "zero-overlap pairs = %d/%d\n"
      ),
      size,
      median(z$jaccard_overlap),
      unname(quantile(z$jaccard_overlap, 0.25)),
      unname(quantile(z$jaccard_overlap, 0.75)),
      sum(z$jaccard_overlap == 0),
      nrow(z)
    )
  )
}

cat("\nTen highest-overlap species pairs at 1 degree:\n")

print(
  overlap_10 %>%
    arrange(desc(jaccard_overlap)) %>%
    head(10),
  row.names = FALSE,
  digits = 4
)

cat("\nEDA-04 COMPLETE\n")
cat(
  paste0(
    "No classifier was fitted, no validation strategy was selected, ",
    "and no exact coordinate pairs were written to outputs.\n"
  )
)