# End-to-end artifact validation; no raster re-extraction, EDA, or modelling.
# Run from the repository root after every data-preparation stage has completed.
source("R/pipeline_helpers.R")
source("R/acquisition/download_worldclim.R")

# Successful evidence is only written at the end; remove stale success first.
evidence_path <- "data/interim/validation/processed_validation.rds"
if (file.exists(evidence_path)) unlink(evidence_path)

assert <- function(condition, description) {
  if (!isTRUE(condition)) stop(description, call. = FALSE)
}
same_values <- function(x, y) {
  isTRUE(all.equal(x, y, check.attributes = FALSE, tolerance = 0))
}
read_required_rds <- function(path) {
  assert(file.exists(path), paste("Required artifact missing:", path))
  readRDS(path)
}
check_unique_id <- function(x, label) {
  assert("eventID" %in% names(x), paste(label, "has no eventID"))
  assert(!anyNA(x$eventID) && all(nzchar(x$eventID)) &&
           !anyDuplicated(x$eventID), paste(label, "must have unique nonmissing eventIDs"))
}
match_ids <- function(ids, reference, label) {
  index <- match(ids, reference)
  assert(!anyNA(index), paste("Unmatched eventID in", label))
  index
}

# These committed pins survive rebuilding the ignored acquisition manifests.
source_pins <- read_csv("config/source_checksums.csv",
                        col_types = cols(.default = col_character()))
assert(nrow(source_pins) == 6L && !anyDuplicated(source_pins$source) &&
         !anyDuplicated(source_pins$file) &&
         setequal(source_pins$source, c("frogid_dataset6", "worldclim_bio",
                                       "worldclim_elev", "worldclim_tavg",
                                       "worldclim_prec", "epbc_sprat")),
       "Committed source pins are incomplete or duplicated")
assert(all(file.exists(source_pins$file)), "A pinned source file is missing")
assert(identical(unname(tools::md5sum(source_pins$file)), source_pins$md5),
       "A source checksum differs from the committed frozen acquisition")
env_columns <- c(paste0("BIO", seq_len(19L)), "elevation",
                 "climatological_tavg_event_month", "climatological_prec_event_month")
calendar_columns <- c("month", "day_of_year", "month_sin", "month_cos",
                      "day_of_year_sin", "day_of_year_cos")
expected_predictors <- c("decimalLongitude", "decimalLatitude", calendar_columns,
                         env_columns)
forbidden_predictors <- c(
  "scientificName", "species_list", "selected_species_list", "n_species",
  "n_selected_species", "all_species_in_vocabulary", "recall_at_k_eligible",
  "occurrenceID", "eventID", "recordedBy", "modified", "datasetName",
  "machineObservation", "coordinateUncertaintyInMeters", "geoprivacy",
  "dataGeneralizations", "epbc_listed", "epbc_category", "epbc_match_status",
  "eventDate", "eventTime", "local_hour", "taxonID", "vernacularName",
  "kingdom", "phylum", "class", "order", "family", "genus"
)

message("Reading final datasets, source cohorts, and frozen manifests...")
primary <- read_required_rds("data/processed/frog_primary_multiclass.rds")
multi <- read_required_rds("data/processed/frog_multispecies_extension.rds")
species <- read_required_rds("data/processed/species_metadata.rds")
primary_predictors <- read_required_rds("data/processed/frog_primary_predictors.rds")
multi_predictors <- read_required_rds("data/processed/frog_multispecies_predictors.rds")
clean <- read_required_rds("data/interim/frogid/clean_events.rds")
source_primary <- read_required_rds("data/interim/frogid/primary_cohort.rds")
source_multi <- read_required_rds("data/interim/frogid/multispecies_cohort.rds")
cohort_manifest <- read_required_rds("data/interim/frogid/cohort_manifest.rds")
cohort <- read_csv("outputs/tables/species_cohort.csv", show_col_types = FALSE)
row_counts <- read_required_rds("data/interim/frogid/integration_row_counts.rds")
environment <- read_required_rds("data/interim/environmental/event_environment.rds")
environment_validation <- read_required_rds("data/interim/environmental/integration_validation.rds")
cache <- read_required_rds("data/interim/environmental/coordinate_environment_cache.rds")
worldclim_manifest <- read_required_rds("data/raw/worldclim/acquisition_manifest.rds")
conservation <- read_required_rds("data/interim/epbc/species_conservation.rds")
epbc_manifest <- read_csv("data/raw/epbc/source_manifest.csv",
                          col_types = cols(.default = col_character()))
vocabulary <- cohort$scientificName[cohort$selected]

for (item in c("primary", "multi", "clean", "source_primary", "source_multi", "environment")) {
  check_unique_id(get(item), item)
}
assert(length(vocabulary) > 0L && !anyDuplicated(vocabulary), "Vocabulary must be nonempty and unique")
assert(identical(vocabulary, cohort_manifest$vocabulary), "Frozen vocabulary differs from cohort manifest")
assert(identical(primary$eventID, source_primary$eventID), "Primary events or order changed during integration")
assert(identical(multi$eventID, source_multi$eventID), "Multispecies events or order changed during integration")
assert(!any(primary$eventID %in% multi$eventID), "Single- and multispecies cohorts overlap")
assert(setequal(row_counts$stage, c("pre_join", "after_environment", "after_conservation")) &&
         !anyDuplicated(row_counts$stage), "Join row-count evidence is missing or duplicated")
assert(all(row_counts$primary_rows == nrow(primary)) &&
         all(row_counts$multispecies_rows == nrow(multi)) &&
         nrow(primary) == nrow(source_primary) && nrow(multi) == nrow(source_multi),
       "Environmental or conservation integration multiplied or dropped events")

message("Checking original FrogID rows, metadata agreement, and all occurrence-level QC...")
assert(identical(unname(tools::md5sum(raw_frogid_path)), cohort_manifest$raw_md5),
       "The original raw FrogID CSV changed after cohort construction")
raw <- read_frogid()
assert(nrow(raw) == 974120L && ncol(raw) == 21L &&
         n_distinct(raw$eventID) == 542287L &&
         n_distinct(raw$occurrenceID) == 974120L &&
         n_distinct(raw$scientificName) == 216L,
       "Raw Dataset 6 dimensions differ from the certified release")
assert(nrow(raw) == cohort_manifest$raw_rows && ncol(raw) == cohort_manifest$raw_columns &&
         n_distinct(raw$eventID) == cohort_manifest$raw_events &&
         n_distinct(raw$scientificName) == cohort_manifest$raw_species,
       "Raw dimensions differ from the frozen audit manifest")
assert(!anyDuplicated(raw$occurrenceID) && !anyDuplicated(raw), "Raw occurrence IDs or rows are duplicated")
conflicts <- event_metadata_conflicts(raw)
assert(nrow(conflicts) == 0L, "Rows of the same event disagree on core event metadata")
assert(nrow(read_required_rds("data/interim/frogid/event_metadata_conflicts.rds")) == 0L,
       "Saved metadata-conflict report is nonempty")

# Prove completeness as well as purity: every event passing all source-row QC
# must be retained. A dropped valid event must not silently pass validation.
raw_dates <- as.Date(raw$eventDate, format = "%Y-%m-%d")
source_qc <- !is.na(raw$scientificName) & nzchar(trimws(raw$scientificName)) &
  valid_coordinates(raw$decimalLatitude, raw$decimalLongitude) &
  valid_uncertainty(raw$coordinateUncertaintyInMeters) &
  !is.na(raw$geoprivacy) & raw$geoprivacy == "open" &
  !is.na(raw$dataGeneralizations) & raw$dataGeneralizations == "No data generalization" &
  !is.na(raw_dates) & format(raw_dates, "%Y-%m-%d") == raw$eventDate
bad_event_ids <- unique(raw$eventID[is.na(source_qc) | !source_qc])
expected_clean_ids <- setdiff(unique(raw$eventID), bad_event_ids)
assert(setequal(clean$eventID, expected_clean_ids),
       "Clean events do not equal every original event whose entire occurrence set passes QC")
assert(nrow(clean) == 519414L && nrow(primary) == 247406L && nrow(multi) == 213675L,
       "Certified clean/primary/multispecies dimensions changed")

# Checking ALL source occurrences prevents a valid representative row from
# concealing an invalid uncertainty, privacy flag, or omitted target species.
retained <- raw[raw$eventID %in% clean$eventID, ]
assert(n_distinct(retained$eventID) == nrow(clean), "A clean event is absent from the raw source")
assert(all(valid_coordinates(retained$decimalLatitude, retained$decimalLongitude)),
       "A retained occurrence has invalid coordinates")
assert(all(is.finite(retained$coordinateUncertaintyInMeters) &
             retained$coordinateUncertaintyInMeters > 0 &
             retained$coordinateUncertaintyInMeters <= 1000),
       "A retained occurrence has nonpositive, missing, infinite, or excessive uncertainty")
assert(!anyNA(retained$geoprivacy) && all(retained$geoprivacy == "open"),
       "A retained occurrence has an obscured or missing geoprivacy value")
assert(!anyNA(retained$dataGeneralizations) &&
         all(retained$dataGeneralizations == "No data generalization"),
       "A retained occurrence has a generalised or missing location flag")
assert(!anyNA(retained$scientificName) && all(nzchar(trimws(retained$scientificName))),
       "A retained occurrence lacks a species target")
dates <- as.Date(retained$eventDate, format = "%Y-%m-%d")
assert(!anyNA(dates) && all(format(dates, "%Y-%m-%d") == retained$eventDate),
       "A retained occurrence has an invalid event date")

raw_pairs <- raw |> distinct(eventID, scientificName)
raw_event_counts <- raw_pairs |> count(eventID, name = "original_n_species")
assert(sum(raw_event_counts$original_n_species == 1L) == 301378L &&
         sum(raw_event_counts$original_n_species >= 2L) == 240909L &&
         max(raw_event_counts$original_n_species) == 13L &&
         min(raw_dates) == as.Date("2017-11-10") &&
         max(raw_dates) == as.Date("2023-11-09"),
       "Raw Dataset 6 dates or recording structure changed")
clean_raw_index <- match_ids(clean$eventID, raw_event_counts$eventID, "clean source species counts")
assert(identical(as.integer(clean$n_species),
                 as.integer(raw_event_counts$original_n_species[clean_raw_index])),
       "Cleaning altered an event's original number of detected species")
raw_primary <- raw_pairs[raw_pairs$eventID %in% primary$eventID, ]
assert(nrow(raw_primary) == nrow(primary) && !anyDuplicated(raw_primary$eventID),
       "A primary event originally contained multiple species")
primary_raw_index <- match_ids(primary$eventID, raw_primary$eventID, "primary raw labels")
assert(identical(primary$scientificName, raw_primary$scientificName[primary_raw_index]) &&
         !anyNA(primary$scientificName) && all(primary$scientificName %in% vocabulary),
       "Primary targets differ from original labels or the frozen vocabulary")
assert(!is.list(primary$scientificName) && all(source_primary$n_species == 1L),
       "Primary targets must be one species per event")

raw_multi_labels <- raw_pairs[raw_pairs$eventID %in% multi$eventID, ] |>
  group_by(eventID) |>
  summarise(original_species = list(sort(scientificName)), .groups = "drop")
multi_raw_index <- match_ids(multi$eventID, raw_multi_labels$eventID, "multispecies raw labels")
assert(is.list(multi$species_list) &&
         identical(multi$species_list, raw_multi_labels$original_species[multi_raw_index]),
       "Multispecies original complete target lists were altered or truncated")
assert(all(lengths(multi$species_list) >= 2L) &&
         identical(as.integer(lengths(multi$species_list)), as.integer(multi$n_species)),
       "A multispecies event does not originally contain at least two distinct labels")
expected_intersections <- lapply(multi$species_list, intersect, y = vocabulary)
assert(identical(multi$selected_species_list, expected_intersections) &&
         identical(as.integer(lengths(expected_intersections)), as.integer(multi$n_selected_species)) &&
         all(multi$n_selected_species > 0L),
       "Selected-species intersections or relevance counts are incorrect")
expected_eligible <- lengths(expected_intersections) == lengths(multi$species_list)
assert(identical(multi$all_species_in_vocabulary, expected_eligible) &&
         identical(multi$recall_at_k_eligible, expected_eligible),
       "Recall@k eligibility includes targets outside the model vocabulary")

# Recompute counts from clean event IDs and the ORIGINAL raw event labels.
clean_single_ids <- clean$eventID[clean$n_species == 1L]
single_counts <- raw_pairs[raw_pairs$eventID %in% clean_single_ids, ] |>
  count(scientificName, name = "clean_single_species_events")
expected_counts <- tibble(scientificName = sort(unique(raw$scientificName))) |>
  left_join(single_counts, by = "scientificName", relationship = "one-to-one") |>
  mutate(clean_single_species_events = coalesce(clean_single_species_events, 0L))
counts_index <- match(cohort$scientificName, expected_counts$scientificName)
assert(!anyNA(counts_index) && !anyDuplicated(cohort$scientificName) &&
         nrow(cohort) == nrow(expected_counts) &&
         same_values(cohort$clean_single_species_events,
                     expected_counts$clean_single_species_events[counts_index]),
       "Frozen species counts do not equal clean original single-species-event counts")
threshold <- if (sum(expected_counts$clean_single_species_events >= 2000L) < 15L) 1000L else 2000L
eligible_names <- expected_counts |>
  filter(clean_single_species_events >= threshold) |>
  arrange(desc(clean_single_species_events), scientificName) |>
  slice_head(n = 25L) |>
  pull(scientificName)
assert(identical(vocabulary, eligible_names) && all(cohort$threshold_used == threshold),
       "Frozen model species violate the objective threshold/top-25 selection rule")
assert(length(vocabulary) == 18L && threshold == 2000L &&
         identical(as.integer(cohort_manifest$threshold_used), 2000L),
       "The objectively generated vocabulary must retain 18 classes at threshold 2000")
assert(nrow(primary) == sum(cohort$clean_single_species_events[cohort$selected]),
       "Primary dimensions do not match frozen selected species counts")

for (label in c("primary", "multi")) {
  x <- get(label)
  assert(all(valid_coordinates(x$decimalLatitude, x$decimalLongitude)),
         paste(label, "contains invalid coordinates"))
  source_index <- match_ids(x$eventID, clean$eventID, paste(label, "clean metadata"))
  for (field in c("decimalLatitude", "decimalLongitude", "eventDate", calendar_columns)) {
    assert(field %in% names(x) && same_values(x[[field]], clean[[field]][source_index]),
           paste(label, field, "changed during integration"))
  }
  assert(inherits(x$eventDate, "Date") && !anyNA(x$eventDate),
         paste(label, "must retain valid eventDate values for later EDA"))
  assert(all(x$month == as.integer(format(x$eventDate, "%m"))) &&
           all(x$day_of_year == as.integer(format(x$eventDate, "%j"))),
         paste(label, "calendar fields disagree with eventDate"))
  assert(all(is.finite(as.matrix(x[, calendar_columns]))),
         paste(label, "calendar features contain nonfinite values"))
  predictors <- get(paste0(label, "_predictors"))
  declared <- attr(x, "predictor_columns")
  assert(is.character(declared) && !anyDuplicated(declared) &&
           setequal(declared, expected_predictors) && length(declared) == 30L,
         paste(label, "predictor declaration is missing or differs from the 30-feature allow-list"))
  assert(identical(names(predictors), declared) && ncol(predictors) == 30L &&
           nrow(predictors) == nrow(x) && all(vapply(predictors, is.numeric, logical(1))),
         paste(label, "predictor artifact has incorrect rows, columns, order, or types"))
  assert(!any(names(predictors) %in% forbidden_predictors),
         paste(label, "predictors leak identifiers, targets, QC, or conservation metadata"))
  for (field in declared) {
    assert(same_values(predictors[[field]], x[[field]]),
           paste(label, "predictor rows no longer align for", field))
  }
}

message("Checking WorldClim source fingerprints, unique-coordinate cache, and month selection...")
assert(identical(names(environment), c("eventID", env_columns)) &&
         identical(environment$eventID, as.character(clean$eventID)) &&
         nrow(environment) == nrow(clean),
       "WorldClim event features must have exactly one row per clean event and the 22 required features")
assert(identical(environment_validation$input_md5,
                 unname(tools::md5sum("data/interim/frogid/clean_events.rds"))),
       "WorldClim cache was built against a different clean-event source")
assert(identical(environment_validation$eventID, environment$eventID) &&
         identical(environment_validation$feature_names, env_columns),
       "WorldClim validation manifest differs from saved event features")
source_columns <- c(paste0("BIO", seq_len(19L)), "elevation",
                    paste0("tavg_month_", seq_len(12L)), paste0("prec_month_", seq_len(12L)))
assert(identical(names(cache$values), source_columns) && ncol(cache$values) == 44L &&
         nrow(cache$values) == nrow(cache$coordinates) && !anyDuplicated(cache$coordinates),
       "WorldClim extraction cache must have 44 source layers and one row per unique coordinate")
coordinate_key <- function(x) paste(sprintf("%.17g", x$decimalLongitude),
                                    sprintf("%.17g", x$decimalLatitude), sep = "|")
coordinate_index <- match(coordinate_key(clean), coordinate_key(cache$coordinates))
assert(!anyNA(coordinate_index) &&
         same_values(clean$decimalLongitude, cache$coordinates$decimalLongitude[coordinate_index]) &&
         same_values(clean$decimalLatitude, cache$coordinates$decimalLatitude[coordinate_index]) &&
         identical(coordinate_index, environment_validation$coordinate_index) &&
         length(unique(coordinate_index)) == nrow(cache$coordinates),
       "Coordinate cache does not exactly cover clean-event coordinates")
assert(environment_validation$n_clean_events == nrow(clean) &&
         environment_validation$n_unique_coordinates == nrow(cache$coordinates) &&
         environment_validation$n_extraction_rows == nrow(cache$values) &&
         environment_validation$n_event_environment_rows == nrow(environment),
       "WorldClim extraction counts violate event/coordinate cardinality")
for (field in c(paste0("BIO", seq_len(19L)), "elevation")) {
  assert(same_values(environment[[field]], cache$values[[field]][coordinate_index]),
         paste("WorldClim event mapping is incorrect for", field))
}
for (prefix in c("tavg", "prec")) {
  monthly <- as.matrix(cache$values[, paste0(prefix, "_month_", seq_len(12L))])
  expected <- monthly[cbind(coordinate_index, clean$month)]
  field <- paste0("climatological_", prefix, "_event_month")
  assert(same_values(environment[[field]], expected),
         paste("Event-month climatological layer selection is incorrect for", prefix))
}
source_hashes <- stats::setNames(worldclim_manifest$md5, worldclim_manifest$variable)
assert(identical(cache$raster_md5, source_hashes) &&
         identical(environment_validation$raster_md5, source_hashes),
       "Environmental cache fingerprints do not match acquired source rasters")
assert(setequal(worldclim_manifest$variable, c("bio", "elev", "tavg", "prec")) &&
         !anyDuplicated(worldclim_manifest$variable) &&
         all(worldclim_manifest$worldclim_version == "2.1") &&
         all(worldclim_manifest$reference_period == "1970-2000") &&
         all(worldclim_manifest$country == "AUS") &&
         all(worldclim_manifest$resolution_arcseconds == 30),
       "WorldClim provenance specifies an unexpected source, version, or resolution")
# Use terra's bundled CRS database on Windows, as acquisition does.
if (.Platform$OS.type == "windows") {
  proj_directory <- system.file("proj", package = "terra")
  gdal_directory <- system.file("gdal", package = "terra")
  if (nzchar(proj_directory) && file.exists(file.path(proj_directory, "proj.db"))) {
    Sys.setenv(PROJ_LIB = proj_directory, PROJ_DATA = proj_directory)
  }
  if (nzchar(gdal_directory)) Sys.setenv(GDAL_DATA = gdal_directory)
}
specification <- worldclim_specification()
reference_raster <- NULL
for (i in seq_len(nrow(worldclim_manifest))) {
  row <- worldclim_manifest[i, ]
  pin <- source_pins[source_pins$source == paste0("worldclim_", row$variable), ]
  assert(row$file == pin$file && row$md5 == pin$md5 && row$source_url == pin$source_url,
         paste("WorldClim provenance differs from committed acquisition:", row$variable))
  raster <- terra::rast(row$file)
  expected_layers <- specification$expected_layers[match(row$variable, specification$variable)]
  validate_worldclim_raster(raster, row$variable, expected_layers)
  assert(terra::nlyr(raster) == row$n_layers &&
           identical(paste(names(raster), collapse = ";"), row$layer_names) &&
           same_values(as.vector(terra::ext(raster)), c(112.5, 159.5, -55.5, -9)) &&
           same_values(as.vector(terra::ext(raster)),
                       c(row$xmin, row$xmax, row$ymin, row$ymax)) &&
           nrow(raster) == 5580L && ncol(raster) == 5640L &&
           nrow(raster) == row$n_rows && ncol(raster) == row$n_columns &&
           terra::same.crs(raster, row$crs),
         paste("WorldClim layer structure/geometry differs from certified metadata:", row$variable))
  if (is.null(reference_raster)) reference_raster <- raster else {
    assert(terra::compareGeom(reference_raster, raster, lyrs = FALSE, stopOnError = FALSE),
           "WorldClim source rasters have inconsistent geometry")
  }
}
for (label in c("primary", "multi")) {
  x <- get(label)
  index <- match_ids(x$eventID, environment$eventID, paste(label, "environment join"))
  assert(all(env_columns %in% names(x)) &&
           all(vapply(x[, env_columns], is.numeric, logical(1))),
         paste(label, "environmental feature structure is incorrect"))
  for (field in env_columns) {
    assert(same_values(x[[field]], environment[[field]][index]),
           paste(label, "environmental values changed during join for", field))
  }
}
missingness <- read_csv("outputs/tables/environmental_missingness.csv", show_col_types = FALSE)
check_missingness <- function(x, label) {
  rows <- missingness[missingness$dataset == label, ]
  assert(setequal(rows$feature, c(env_columns, "any_environmental_feature")) &&
           !anyDuplicated(rows$feature), paste("Missingness report is incomplete for", label))
  expected <- c(colSums(is.na(x[, env_columns])),
                any_environmental_feature = sum(rowSums(is.na(x[, env_columns])) > 0L))
  index <- match(rows$feature, names(expected))
  assert(all(rows$n_events == nrow(x)) && same_values(rows$missing_n, unname(expected[index])) &&
           isTRUE(all.equal(rows$missing_percent, 100 * unname(expected[index]) / nrow(x),
                            check.attributes = FALSE, tolerance = 1e-12)),
         paste("Environmental missingness counts/percentages disagree with", label))
}
check_missingness(environment, "all_clean_events")
check_missingness(primary, "frog_primary_multiclass")
check_missingness(multi, "frog_multispecies_extension")
check_missingness(multi[multi$recall_at_k_eligible, ], "multispecies_recall_at_k_eligible")

message("Checking conservation joins, authoritative name matches, and explicit unresolved names...")
assert(!anyNA(species$scientificName) && !anyDuplicated(species$scientificName) &&
         nrow(species) == length(unique(raw$scientificName)) &&
         setequal(species$scientificName, raw$scientificName),
       "Final species metadata must contain one row per original scientificName")
assert(!anyDuplicated(conservation$scientificName) && nrow(conservation) == nrow(cohort) &&
         setequal(conservation$scientificName, cohort$scientificName),
       "Conservation lookup is not one row per frozen scientific name")
epbc_path <- file.path("data", "raw", "epbc", epbc_manifest$local_filename)
assert(nrow(epbc_manifest) == 1L && file.exists(epbc_path) &&
         unname(tools::md5sum(epbc_path)) == epbc_manifest$md5,
       "Official EPBC source differs from the acquisition manifest")
epbc_pin <- source_pins[source_pins$source == "epbc_sprat", ]
public_epbc_manifest <- read_csv("outputs/tables/epbc_acquisition_metadata.csv",
                                 col_types = cols(.default = col_character()))
assert(identical(as.data.frame(epbc_manifest), as.data.frame(public_epbc_manifest)) &&
         epbc_path == epbc_pin$file && epbc_manifest$md5 == epbc_pin$md5 &&
         epbc_manifest$source_url == epbc_pin$source_url &&
         epbc_manifest$publisher == paste0("Australian Government Department of Climate Change, ",
                                         "Energy, the Environment and Water") &&
         epbc_manifest$source_extracted_date == "2026-Aug-28" &&
         !is.na(as.POSIXct(epbc_manifest$retrieved_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
       "EPBC provenance does not match the official frozen acquisition")
official_all <- read_csv(epbc_path, col_types = cols(.default = col_character()), na = c("", "-"))
assert(nrow(problems(official_all)) == 0L && nrow(official_all) == 2222L &&
         nrow(official_all) == as.integer(epbc_manifest$source_rows) &&
         sum(official_all$Class == "Amphibia", na.rm = TRUE) == 53L &&
         sum(official_all$Class == "Amphibia", na.rm = TRUE) == as.integer(epbc_manifest$amphibian_rows) &&
         identical(unique(na.omit(official_all[["Date extracted"]])), epbc_manifest$source_extracted_date),
       "EPBC source rows, amphibian rows, or extraction date disagree with provenance")
official <- official_all |> filter(Class == "Amphibia")
normalize_name <- function(x) tolower(gsub("[[:space:]]+", " ", trimws(x)))
matched <- which(conservation$epbc_listed %in% TRUE)
assert(is.logical(conservation$epbc_listed) &&
         !any(conservation$epbc_listed %in% FALSE) &&
         identical(is.na(conservation$epbc_listed), is.na(conservation$epbc_category)),
       "Unmatched threatened-list names must remain explicit NA, not fabricated unlisted labels")
for (i in matched) {
  listed_index <- which(official[["Scientific Name"]] == conservation$epbc_source_scientific_name[i] &
                          official[["Listed SPRAT TaxonID"]] == conservation$epbc_sprat_taxon_id[i])
  assert(length(listed_index) == 1L, "A matched conservation taxon lacks one authoritative source row")
  official_names <- c(official[["Scientific Name"]][listed_index],
                      official[["Current Scientific Name"]][listed_index])
  assert(normalize_name(conservation$scientificName[i]) %in% normalize_name(na.omit(official_names)) &&
           conservation$epbc_category[i] == official[["Threatened status"]][listed_index],
         paste("Unsubstantiated conservation name/category match:", conservation$scientificName[i]))
}
unresolved <- conservation[is.na(conservation$epbc_listed), ]
assert(all(grepl("^(unmatched_|unresolved_)", unresolved$epbc_match_status)) &&
         !anyNA(unresolved$epbc_match_status), "Unresolved EPBC names lack explicit match statuses")
unmatched_report <- read_csv("outputs/tables/epbc_unmatched_species.csv", show_col_types = FALSE)
assert(setequal(unmatched_report$scientificName, unresolved$scientificName) &&
         !anyDuplicated(unmatched_report$scientificName),
       "Unmatched-name report omits or duplicates unresolved taxa")
for (label in c("primary", "species")) {
  x <- get(label)
  index <- match(x$scientificName, conservation$scientificName)
  assert(!anyNA(index), paste(label, "contains a species absent from conservation metadata"))
  for (field in c("epbc_listed", "epbc_category", "epbc_match_status")) {
    assert(field %in% names(x) && identical(x[[field]], conservation[[field]][index]),
           paste(label, "conservation values changed during join for", field))
  }
}
raw_counts <- raw |> count(scientificName, name = "raw_occurrence_rows") |>
  left_join(raw_pairs |> count(scientificName, name = "raw_events"),
            by = "scientificName", relationship = "one-to-one")
index <- match(species$scientificName, raw_counts$scientificName)
for (field in c("raw_occurrence_rows", "raw_events")) {
  assert(field %in% names(species) && same_values(species[[field]], raw_counts[[field]][index]),
         paste("Species metadata source counts disagree for", field))
}
assert(identical(unname(tools::md5sum(raw_frogid_path)), cohort_manifest$raw_md5),
       "The raw FrogID source changed during validation")
artifact_paths <- c(
  list.files("data/processed", pattern = "[.]rds$", full.names = TRUE),
  list.files("data/interim/frogid", pattern = "[.]rds$", full.names = TRUE),
  list.files("data/interim/environmental", pattern = "[.]rds$", full.names = TRUE),
  "data/interim/epbc/species_conservation.rds",
  "data/raw/worldclim/acquisition_manifest.rds", "data/raw/epbc/source_manifest.csv",
  "outputs/tables/species_cohort.csv", "outputs/tables/environmental_missingness.csv")
validation_script_paths <- c(list.files("R", pattern = "[.]R$", recursive = TRUE,
                                        full.names = TRUE),
                             "tests/validate_cohorts.R", "tests/validate_processed_data.R",
                             "config/source_checksums.csv")
dir.create(dirname(evidence_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(test = "tests/validate_processed_data.R", passed = TRUE,
             passed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             source_md5 = stats::setNames(source_pins$md5, source_pins$file),
             artifact_md5 = tools::md5sum(artifact_paths),
             script_md5 = tools::md5sum(validation_script_paths)), evidence_path)
message(sprintf(paste0("Final validation passed: primary %s x %s; multispecies %s x %s; ",
                       "species metadata %s x %s; 30 predictors; %s selected species. ",
                       "No rows multiplied, raw source unchanged, no raster extraction repeated."),
                nrow(primary), ncol(primary), nrow(multi), ncol(multi),
                nrow(species), ncol(species), length(vocabulary)))
