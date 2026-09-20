# =========================================================================
# EDA-06: Environmental missingness
#
# Purpose:
# Determine whether the 4,806 primary events with missing environmental values
# are concentrated by variable, species, time or geography, and quantify how
# much complete-case removal would alter the observed dataset composition.
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs contain only aggregate missingness summaries and coarse geography.
#
# No imputation or row removal decision is made in this script.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA06"

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
  "eventDate",
  "month",
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

frogs$date <- as.Date(frogs$eventDate)
frogs$year <- as.integer(format(frogs$date, "%Y"))

missing_vars_per_row <- rowSums(
  is.na(frogs[ENV_FEATURES])
)

frogs$environment_missing <-
  missing_vars_per_row > 0L

stopifnot(
  sum(frogs$environment_missing) == 4806L
)

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

cramers_v <- function(tab) {

  chi <- suppressWarnings(
    chisq.test(
      tab,
      correct = FALSE
    )
  )

  denominator_dimension <-
    min(
      nrow(tab) - 1L,
      ncol(tab) - 1L
    )

  if (denominator_dimension <= 0L) {
    return(NA_real_)
  }

  sqrt(
    unname(chi$statistic) /
      (
        sum(tab) *
          denominator_dimension
      )
  )
}

distribution_tvd <- function(full_counts,
                             complete_counts) {

  all_names <- union(
    names(full_counts),
    names(complete_counts)
  )

  full <- full_counts[all_names]
  complete <- complete_counts[all_names]

  full[is.na(full)] <- 0
  complete[is.na(complete)] <- 0

  p <- full / sum(full)
  q <- complete / sum(complete)

  0.5 * sum(abs(p - q))
}

# -------------------------------------------------------------------------
# 1. Per-variable and row-level missingness patterns
# -------------------------------------------------------------------------

variable_missingness <- data.frame(
  feature = ENV_FEATURES,
  missing_n = vapply(
    frogs[ENV_FEATURES],
    function(x) sum(is.na(x)),
    integer(1)
  ),
  stringsAsFactors = FALSE
)

variable_missingness$missing_percent <-
  100 * variable_missingness$missing_n /
    nrow(frogs)

missingness_pattern <- as.data.frame(
  table(missing_vars_per_row),
  stringsAsFactors = FALSE
)

names(missingness_pattern) <-
  c(
    "missing_environmental_variables",
    "events"
  )

missingness_pattern$missing_environmental_variables <-
  as.integer(
    as.character(
      missingness_pattern$missing_environmental_variables
    )
  )

missingness_pattern$event_percent <-
  100 * missingness_pattern$events /
    nrow(frogs)

# -------------------------------------------------------------------------
# 2. Species missingness and complete-case composition shift
# -------------------------------------------------------------------------

species_missingness <- frogs %>%
  group_by(scientificName) %>%
  summarise(
    events = n(),
    missing_n = sum(environment_missing),
    missing_percent =
      100 * mean(environment_missing),
    .groups = "drop"
  )

full_species_counts <- table(
  frogs$scientificName
)

complete_species_counts <- table(
  frogs$scientificName[
    !frogs$environment_missing
  ]
)

species_composition <- data.frame(
  scientificName = names(full_species_counts),
  full_events = as.integer(full_species_counts),
  stringsAsFactors = FALSE
)

species_composition$full_share <-
  species_composition$full_events /
    sum(species_composition$full_events)

complete_lookup <- as.integer(
  complete_species_counts[
    species_composition$scientificName
  ]
)

complete_lookup[is.na(complete_lookup)] <- 0L

species_composition$complete_case_events <-
  complete_lookup

species_composition$complete_case_share <-
  species_composition$complete_case_events /
    sum(species_composition$complete_case_events)

species_composition$share_change_percentage_points <-
  100 * (
    species_composition$complete_case_share -
      species_composition$full_share
  )

species_missingness <-
  species_missingness %>%
  left_join(
    species_composition,
    by = "scientificName"
  ) %>%
  arrange(desc(missing_percent))

species_missing_cramers_v <- cramers_v(
  table(
    frogs$scientificName,
    frogs$environment_missing
  )
)

species_complete_case_tvd <- distribution_tvd(
  full_species_counts,
  complete_species_counts
)

# -------------------------------------------------------------------------
# 3. Temporal missingness
# -------------------------------------------------------------------------

month_missingness <- frogs %>%
  group_by(month) %>%
  summarise(
    events = n(),
    missing_n = sum(environment_missing),
    missing_percent =
      100 * mean(environment_missing),
    .groups = "drop"
  )

year_missingness <- frogs %>%
  group_by(year) %>%
  summarise(
    events = n(),
    missing_n = sum(environment_missing),
    missing_percent =
      100 * mean(environment_missing),
    .groups = "drop"
  )

month_missing_cramers_v <- cramers_v(
  table(
    frogs$month,
    frogs$environment_missing
  )
)

year_missing_cramers_v <- cramers_v(
  table(
    frogs$year,
    frogs$environment_missing
  )
)

month_complete_case_tvd <- distribution_tvd(
  table(frogs$month),
  table(
    frogs$month[
      !frogs$environment_missing
    ]
  )
)

year_complete_case_tvd <- distribution_tvd(
  table(frogs$year),
  table(
    frogs$year[
      !frogs$environment_missing
    ]
  )
)

temporal_missingness <- bind_rows(
  month_missingness %>%
    transmute(
      temporal_type = "month",
      value = as.character(month),
      events = events,
      missing_n = missing_n,
      missing_percent = missing_percent
    ),
  year_missingness %>%
    transmute(
      temporal_type = "year",
      value = as.character(year),
      events = events,
      missing_n = missing_n,
      missing_percent = missing_percent
    )
)

# -------------------------------------------------------------------------
# 4. Geographic missingness
# -------------------------------------------------------------------------

geographic_group_summary <- bind_rows(
  frogs %>%
    filter(!environment_missing) %>%
    summarise(
      environmental_status = "complete",
      events = n(),
      latitude_min = min(decimalLatitude),
      latitude_q25 =
        unname(
          quantile(
            decimalLatitude,
            0.25
          )
        ),
      latitude_median =
        median(decimalLatitude),
      latitude_q75 =
        unname(
          quantile(
            decimalLatitude,
            0.75
          )
        ),
      latitude_max = max(decimalLatitude),
      longitude_min = min(decimalLongitude),
      longitude_q25 =
        unname(
          quantile(
            decimalLongitude,
            0.25
          )
        ),
      longitude_median =
        median(decimalLongitude),
      longitude_q75 =
        unname(
          quantile(
            decimalLongitude,
            0.75
          )
        ),
      longitude_max = max(decimalLongitude)
    ),
  frogs %>%
    filter(environment_missing) %>%
    summarise(
      environmental_status = "missing",
      events = n(),
      latitude_min = min(decimalLatitude),
      latitude_q25 =
        unname(
          quantile(
            decimalLatitude,
            0.25
          )
        ),
      latitude_median =
        median(decimalLatitude),
      latitude_q75 =
        unname(
          quantile(
            decimalLatitude,
            0.75
          )
        ),
      latitude_max = max(decimalLatitude),
      longitude_min = min(decimalLongitude),
      longitude_q25 =
        unname(
          quantile(
            decimalLongitude,
            0.25
          )
        ),
      longitude_median =
        median(decimalLongitude),
      longitude_q75 =
        unname(
          quantile(
            decimalLongitude,
            0.75
          )
        ),
      longitude_max = max(decimalLongitude)
    )
)

cell_x <- floor(
  frogs$decimalLongitude
)

cell_y <- floor(
  frogs$decimalLatitude
)

grid_missingness <- data.frame(
  frogs,
  cell_x = cell_x,
  cell_y = cell_y,
  cell_lon = cell_x + 0.5,
  cell_lat = cell_y + 0.5,
  stringsAsFactors = FALSE
) %>%
  group_by(
    cell_x,
    cell_y,
    cell_lon,
    cell_lat
  ) %>%
  summarise(
    events = n(),
    missing_n = sum(environment_missing),
    missing_percent =
      100 * mean(environment_missing),
    .groups = "drop"
  )

grid_missingness_with_missing <-
  grid_missingness %>%
  filter(missing_n > 0)

missing_cells <- nrow(
  grid_missingness_with_missing
)

occupied_cells <- nrow(
  grid_missingness
)

top_10_missing_cells_share_percent <-
  100 *
    sum(
      head(
        sort(
          grid_missingness$missing_n,
          decreasing = TRUE
        ),
        10
      )
    ) /
    sum(frogs$environment_missing)

grid_20plus <- grid_missingness %>%
  filter(events >= 20)

# -------------------------------------------------------------------------
# 5. Compact missingness summary
# -------------------------------------------------------------------------

missingness_summary <- data.frame(
  measure = c(
    "events",
    "environmental_missing_events",
    "environmental_missing_percent",
    "environmental_predictors",
    "distinct_missing_variable_counts_per_row",
    "all_environmental_predictors_missing_together",
    "species_missingness_cramers_v",
    "species_complete_case_distribution_tvd",
    "maximum_absolute_species_share_change_percentage_points",
    "month_missingness_cramers_v",
    "month_complete_case_distribution_tvd",
    "year_missingness_cramers_v",
    "year_complete_case_distribution_tvd",
    "occupied_1deg_cells",
    "occupied_1deg_cells_with_missing_events",
    "top_10_1deg_cells_share_of_missing_events_percent",
    "median_missing_percent_in_1deg_cells_with_at_least_20_events",
    "maximum_missing_percent_in_1deg_cells_with_at_least_20_events"
  ),
  value = c(
    nrow(frogs),
    sum(frogs$environment_missing),
    100 * mean(frogs$environment_missing),
    length(ENV_FEATURES),
    length(unique(missing_vars_per_row)),
    as.integer(
      all(
        missing_vars_per_row[
          frogs$environment_missing
        ] == length(ENV_FEATURES)
      )
    ),
    species_missing_cramers_v,
    species_complete_case_tvd,
    max(
      abs(
        species_composition$share_change_percentage_points
      )
    ),
    month_missing_cramers_v,
    month_complete_case_tvd,
    year_missing_cramers_v,
    year_complete_case_tvd,
    occupied_cells,
    missing_cells,
    top_10_missing_cells_share_percent,
    median(grid_20plus$missing_percent),
    max(grid_20plus$missing_percent)
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# 6. Figures
# -------------------------------------------------------------------------

# Figure 1: required missingness-pattern visualisation.
png(
  file.path(
    FIG_DIR,
    "eda06_missingness_pattern.png"
  ),
  width = 2100,
  height = 1050,
  res = 180
)

par(
  mfrow = c(1, 2),
  mar = c(11, 5, 4, 2)
)

barplot(
  missingness_pattern$events,
  names.arg =
    missingness_pattern$missing_environmental_variables,
  xlab = "Number of missing environmental variables in an event",
  ylab = "Events",
  main = "Row-level environmental missingness pattern"
)

barplot(
  variable_missingness$missing_percent,
  names.arg = variable_missingness$feature,
  las = 2,
  cex.names = 0.58,
  ylab = "Missing events (%)",
  main = "Missingness by environmental predictor"
)

dev.off()

# Figure 2: coarse geographic missingness.
# Restrict the visualisation to cells with at least 20 events so that very
# small denominators do not dominate displayed missingness percentages.
# The complete grid_missingness table remains unchanged.
p_missing_map <- ggplot(
  grid_20plus,
  aes(
    x = cell_lon,
    y = cell_lat,
    fill = missing_percent
  )
) +
  geom_tile(
    width = 1,
    height = 1
  ) +
  coord_fixed() +
  scale_fill_viridis_c(
    name = "Missing (%)"
  ) +
  labs(
    title = "Environmental missingness by 1-degree cell",
    subtitle = "Cells with at least 20 events; coarse aggregate rates; no exact locations shown",
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda06_geographic_missingness.png"
  ),
  p_missing_map,
  width = 8,
  height = 7,
  dpi = 180
)

# Figure 3: species missingness rates.
species_plot <- species_missingness %>%
  arrange(missing_percent)

species_plot$scientificName <- factor(
  species_plot$scientificName,
  levels = species_plot$scientificName
)

p_species_missing <- ggplot(
  species_plot,
  aes(
    x = missing_percent,
    y = scientificName
  )
) +
  geom_col() +
  labs(
    title = "Environmental missingness by species",
    x = "Events with missing environmental predictors (%)",
    y = NULL
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda06_species_missingness.png"
  ),
  p_species_missing,
  width = 8,
  height = 7,
  dpi = 180
)

# -------------------------------------------------------------------------
# 7. Write aggregate outputs
# -------------------------------------------------------------------------

write.csv(
  variable_missingness,
  file.path(
    TABLE_DIR,
    "eda06_variable_missingness.csv"
  ),
  row.names = FALSE
)

write.csv(
  missingness_pattern,
  file.path(
    TABLE_DIR,
    "eda06_missingness_pattern.csv"
  ),
  row.names = FALSE
)

write.csv(
  species_missingness,
  file.path(
    TABLE_DIR,
    "eda06_species_missingness.csv"
  ),
  row.names = FALSE
)

write.csv(
  temporal_missingness,
  file.path(
    TABLE_DIR,
    "eda06_temporal_missingness.csv"
  ),
  row.names = FALSE
)

write.csv(
  geographic_group_summary,
  file.path(
    TABLE_DIR,
    "eda06_geographic_group_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  grid_missingness,
  file.path(
    TABLE_DIR,
    "eda06_grid_missingness_1deg.csv"
  ),
  row.names = FALSE
)

write.csv(
  missingness_summary,
  file.path(
    TABLE_DIR,
    "eda06_missingness_summary.csv"
  ),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# 8. Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-06 ENVIRONMENTAL MISSINGNESS\n")
cat("============================================================\n")

cat("\nRow-level missingness pattern:\n")
print(
  missingness_pattern,
  row.names = FALSE
)

cat("\nPer-variable missingness:\n")
print(
  variable_missingness,
  row.names = FALSE,
  digits = 4
)

cat("\nSpecies missingness:\n")
print(
  species_missingness[
    ,
    c(
      "scientificName",
      "events",
      "missing_n",
      "missing_percent",
      "share_change_percentage_points"
    )
  ],
  row.names = FALSE,
  digits = 4
)

cat("\nTemporal missingness:\n")
print(
  temporal_missingness,
  row.names = FALSE,
  digits = 4
)

cat("\nComplete versus missing geography:\n")
print(
  geographic_group_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nCompact missingness summary:\n")
print(
  missingness_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nEDA-06 COMPLETE\n")
cat(
  paste0(
    "No environmental values were imputed and no rows were removed. ",
    "No missing-data handling strategy was selected.\n"
  )
)
