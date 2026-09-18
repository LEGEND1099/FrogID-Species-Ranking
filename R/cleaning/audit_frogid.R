library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(lubridate)
library(tibble)

input_file <- file.path(
  "data",
  "raw",
  "frogid",
  "FrogID6_final_dataset.csv"
)

if (!file.exists(input_file)) {
  stop("Raw FrogID CSV does not exist. Run the acquisition script first.")
}

message("Reading FrogID raw data...")

frog <- read_csv(
  input_file,
  show_col_types = FALSE,
  progress = TRUE,
  col_types = cols(
    .default = col_guess(),
    occurrenceID = col_character(),
    eventID = col_character(),
    recordedBy = col_character()
  )
)

dir.create(
  file.path("outputs", "tables"),
  recursive = TRUE,
  showWarnings = FALSE
)

# ------------------------------------------------------------
# 1. Basic structure
# ------------------------------------------------------------

basic_summary <- tibble(
  metric = c(
    "rows",
    "columns",
    "unique_occurrence_ids",
    "unique_event_ids",
    "unique_species"
  ),
  value = c(
    nrow(frog),
    ncol(frog),
    n_distinct(frog$occurrenceID),
    n_distinct(frog$eventID),
    n_distinct(frog$scientificName)
  )
)

print(basic_summary)

write_csv(
  basic_summary,
  file.path("outputs", "tables", "audit_basic_summary.csv")
)

# ------------------------------------------------------------
# 2. Print actual raw column names
# ------------------------------------------------------------

cat("\nRAW COLUMN NAMES\n")
cat("================\n")

print(names(frog))

write_csv(
  tibble(column = names(frog)),
  file.path("outputs", "tables", "audit_columns.csv")
)

# ------------------------------------------------------------
# 3. Missingness
# ------------------------------------------------------------

missingness <- tibble(
  column = names(frog),
  missing_n = vapply(
    frog,
    function(x) sum(is.na(x)),
    numeric(1)
  )
) |>
  mutate(
    missing_pct = 100 * missing_n / nrow(frog)
  ) |>
  arrange(desc(missing_pct))

cat("\nMISSINGNESS\n")
cat("===========\n")

print(missingness, n = Inf)

write_csv(
  missingness,
  file.path("outputs", "tables", "audit_missingness.csv")
)

# ------------------------------------------------------------
# 4. Species frequencies
# ------------------------------------------------------------

species_counts <- frog |>
  filter(
    !is.na(scientificName),
    scientificName != ""
  ) |>
  count(
    scientificName,
    sort = TRUE,
    name = "occurrence_rows"
  )

cat("\nTOP 30 SPECIES BY OCCURRENCE ROWS\n")
cat("=================================\n")

print(species_counts, n = 30)

write_csv(
  species_counts,
  file.path("outputs", "tables", "audit_species_counts.csv")
)

# ------------------------------------------------------------
# 5. Event structure
# ------------------------------------------------------------

event_species <- frog |>
  filter(
    !is.na(eventID),
    !is.na(scientificName),
    scientificName != ""
  ) |>
  distinct(
    eventID,
    scientificName
  )

event_species_counts <- event_species |>
  count(
    eventID,
    name = "n_species"
  )

event_structure <- event_species_counts |>
  count(
    n_species,
    name = "n_events"
  ) |>
  mutate(
    pct_events = 100 * n_events / sum(n_events)
  ) |>
  arrange(n_species)

cat("\nNUMBER OF SPECIES PER EVENT\n")
cat("===========================\n")

print(event_structure, n = Inf)

write_csv(
  event_structure,
  file.path("outputs", "tables", "audit_event_species_structure.csv")
)

cat("\nEVENT SUMMARY\n")
cat("=============\n")

cat(
  "Single-species events:",
  sum(event_species_counts$n_species == 1L),
  "\n"
)

cat(
  "Multi-species events:",
  sum(event_species_counts$n_species >= 2L),
  "\n"
)

cat(
  "Maximum species in one event:",
  max(event_species_counts$n_species, na.rm = TRUE),
  "\n"
)

# ------------------------------------------------------------
# 6. Duplicate diagnostics
# ------------------------------------------------------------

cat("\nDUPLICATE DIAGNOSTICS\n")
cat("=====================\n")

cat(
  "Duplicated occurrenceID rows:",
  sum(duplicated(frog$occurrenceID)),
  "\n"
)

cat(
  "Exact duplicate rows:",
  if (!anyDuplicated(frog$occurrenceID)) 0L else sum(duplicated(frog)),
  "\n"
)

# ------------------------------------------------------------
# 7. Coordinate quality
# ------------------------------------------------------------

coord_summary <- frog |>
  summarise(
    missing_latitude = sum(is.na(decimalLatitude)),
    missing_longitude = sum(is.na(decimalLongitude)),
    missing_uncertainty = sum(is.na(coordinateUncertaintyInMeters)),
    uncertainty_le_100m = sum(
      coordinateUncertaintyInMeters > 0 & coordinateUncertaintyInMeters <= 100,
      na.rm = TRUE
    ),
    uncertainty_le_1000m = sum(
      coordinateUncertaintyInMeters > 0 & coordinateUncertaintyInMeters <= 1000,
      na.rm = TRUE
    ),
    uncertainty_le_3000m = sum(
      coordinateUncertaintyInMeters > 0 & coordinateUncertaintyInMeters <= 3000,
      na.rm = TRUE
    ),
    uncertainty_gt_3000m = sum(
      coordinateUncertaintyInMeters > 3000,
      na.rm = TRUE
    )
  )

cat("\nCOORDINATE QUALITY\n")
cat("==================\n")

print(coord_summary)

write_csv(
  coord_summary,
  file.path("outputs", "tables", "audit_coordinate_quality.csv")
)

uncertainty_quantiles <- tibble(
  probability = c(
    0,
    0.25,
    0.50,
    0.75,
    0.90,
    0.95,
    0.99,
    1
  ),
  metres = as.numeric(
    quantile(
      frog$coordinateUncertaintyInMeters,
      probs = c(
        0,
        0.25,
        0.50,
        0.75,
        0.90,
        0.95,
        0.99,
        1
      ),
      na.rm = TRUE
    )
  )
)

cat("\nCOORDINATE UNCERTAINTY QUANTILES\n")
cat("================================\n")

print(uncertainty_quantiles)

write_csv(
  uncertainty_quantiles,
  file.path(
    "outputs",
    "tables",
    "audit_coordinate_uncertainty_quantiles.csv"
  )
)

# ------------------------------------------------------------
# 8. Geography sanity checks
# ------------------------------------------------------------

coordinate_sanity <- frog |>
  summarise(
    latitude_min = min(decimalLatitude, na.rm = TRUE),
    latitude_max = max(decimalLatitude, na.rm = TRUE),
    longitude_min = min(decimalLongitude, na.rm = TRUE),
    longitude_max = max(decimalLongitude, na.rm = TRUE),
    invalid_latitude = sum(
      decimalLatitude < -90 | decimalLatitude > 90,
      na.rm = TRUE
    ),
    invalid_longitude = sum(
      decimalLongitude < -180 | decimalLongitude > 180,
      na.rm = TRUE
    )
  )

cat("\nCOORDINATE SANITY\n")
cat("=================\n")

print(coordinate_sanity)

write_csv(
  coordinate_sanity,
  file.path("outputs", "tables", "audit_coordinate_sanity.csv")
)

# ------------------------------------------------------------
# 9. Date coverage
# ------------------------------------------------------------

parsed_dates <- suppressWarnings(
  as.Date(frog$eventDate)
)

date_summary <- tibble(
  min_date = min(parsed_dates, na.rm = TRUE),
  max_date = max(parsed_dates, na.rm = TRUE),
  missing_date = sum(is.na(parsed_dates))
)

cat("\nDATE COVERAGE\n")
cat("=============\n")

print(date_summary)

write_csv(
  date_summary,
  file.path("outputs", "tables", "audit_date_summary.csv")
)

year_counts <- tibble(
  eventDate = parsed_dates
) |>
  mutate(
    year = year(eventDate)
  ) |>
  count(
    year,
    sort = FALSE,
    name = "occurrence_rows"
  )

cat("\nROWS BY YEAR\n")
cat("============\n")

print(year_counts, n = Inf)

write_csv(
  year_counts,
  file.path("outputs", "tables", "audit_year_counts.csv")
)

# ------------------------------------------------------------
# 10. Check whether event-level metadata is internally stable
# ------------------------------------------------------------

event_metadata_check <- frog |>
  filter(!is.na(eventID)) |>
  distinct(eventID, decimalLatitude, decimalLongitude, eventDate, eventTime, recordedBy) |>
  count(eventID, name = "metadata_versions")

event_metadata_conflicts <- event_metadata_check |>
  filter(metadata_versions > 1L)

cat("\nEVENT-LEVEL METADATA CONSISTENCY\n")
cat("================================\n")

cat(
  "Events with conflicting metadata:",
  nrow(event_metadata_conflicts),
  "\n"
)

write_csv(
  tibble(conflicting_events = nrow(event_metadata_conflicts)),
  file.path("outputs", "tables", "audit_event_metadata_conflicts.csv")
)

# ------------------------------------------------------------
# 11. Potential privacy / generalisation fields
# ------------------------------------------------------------

sensitive_fields <- intersect(
  c(
    "geoprivacy",
    "dataGeneralizations",
    "coordinateUncertaintyInMeters"
  ),
  names(frog)
)

cat("\nPRIVACY / GENERALISATION FIELDS PRESENT\n")
cat("=======================================\n")

print(sensitive_fields)

for (field in sensitive_fields) {

  values <- frog |>
    count(
      .data[[field]],
      sort = TRUE,
      name = "n"
    )

  print(values, n = 30)

  safe_name <- str_replace_all(
    field,
    "[^A-Za-z0-9]+",
    "_"
  )

  # Keep the high-cardinality uncertainty frequency dump local; publish only
  # its top 30 values. Nonpositive values have their own complete QC summary.
  if (field == "coordinateUncertaintyInMeters") {
    dir.create("data/interim/frogid", recursive = TRUE, showWarnings = FALSE)
    write_csv(values, "data/interim/frogid/audit_coordinateUncertaintyInMeters_full.csv")
    values <- slice_head(values, n = 30)
  }

  write_csv(
    values,
    file.path(
      "outputs",
      "tables",
      paste0(
        "audit_",
        safe_name,
        ".csv"
      )
    )
  )
}

# ------------------------------------------------------------
# 12. Candidate species after initial coordinate-quality filter
# ------------------------------------------------------------

# Use the canonical event-level cohort rule, including positive uncertainty and
# whole-event QC, rather than maintaining a competing occurrence-level filter.
source("R/cleaning/build_cohorts.R", local = new.env(parent = globalenv()))
candidate_counts <- read_csv("outputs/tables/species_cohort.csv", show_col_types = FALSE) |>
  select(scientificName, clean_single_species_events) |>
  filter(clean_single_species_events > 0)

cat("\nTOP 40 CANDIDATE SPECIES AFTER INITIAL QUALITY FILTER\n")
cat("=====================================================\n")

print(candidate_counts, n = 40)

write_csv(
  candidate_counts,
  file.path(
    "outputs",
    "tables",
    "audit_candidate_species_counts.csv"
  )
)

# ------------------------------------------------------------
# 13. Save lightweight audit metadata
# ------------------------------------------------------------

audit_metadata <- list(
  audited_at = Sys.time(),
  raw_file = normalizePath(input_file, winslash = "/"),
  rows = nrow(frog),
  columns = ncol(frog),
  unique_events = n_distinct(frog$eventID),
  unique_species = n_distinct(frog$scientificName),
  single_species_events = sum(event_species_counts$n_species == 1L),
  multi_species_events = sum(event_species_counts$n_species >= 2L),
  event_metadata_conflicts = nrow(event_metadata_conflicts)
)

dir.create("data/interim/frogid", recursive = TRUE, showWarnings = FALSE)
saveRDS(
  audit_metadata,
  file.path(
    "data",
    "interim",
    "frogid",
    "audit_metadata.rds"
  )
)

cat("\nFrogID raw audit complete.\n")
