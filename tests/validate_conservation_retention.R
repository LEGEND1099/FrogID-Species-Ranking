# Independently reconcile the public aggregates with original occurrence sets.
source("R/pipeline_helpers.R")
evidence_path <- "data/interim/validation/conservation_validation.rds"
if (file.exists(evidence_path)) unlink(evidence_path)
raw <- read_frogid()
clean <- readRDS("data/interim/frogid/clean_events.rds")
lookup <- readRDS("data/interim/epbc/species_conservation.rds")
species <- read_csv("outputs/tables/conservation_species_retention.csv", show_col_types = FALSE)
category <- read_csv("outputs/tables/conservation_category_retention.csv", show_col_types = FALSE)
exclusions <- read_csv("outputs/tables/conservation_qc_exclusion_summary.csv", show_col_types = FALSE)
stopifnot(nrow(species) == 216L, !anyDuplicated(species$scientificName),
          setequal(species$scientificName, raw$scientificName),
          !any(species$epbc_listed %in% FALSE))
pairs <- unique(raw[c("eventID", "scientificName")])
event_size <- table(pairs$eventID)
single_ids <- names(event_size)[event_size == 1L]
all_ids <- unique(raw$eventID)
open_ids <- setdiff(all_ids, raw$eventID[is.na(raw$geoprivacy) | raw$geoprivacy != "open"])
precision_ids <- setdiff(all_ids, raw$eventID[!valid_uncertainty(raw$coordinateUncertaintyInMeters)])
count_names <- function(x) as.integer(table(factor(x, levels = species$scientificName)))
expected <- list(
  raw_occurrence_rows = count_names(raw$scientificName),
  raw_events = count_names(pairs$scientificName),
  raw_single_species_events = count_names(pairs$scientificName[pairs$eventID %in% single_ids]),
  open_location_events = count_names(pairs$scientificName[pairs$eventID %in% open_ids]),
  precision_eligible_events = count_names(pairs$scientificName[pairs$eventID %in% precision_ids]),
  clean_events = count_names(pairs$scientificName[pairs$eventID %in% clean$eventID]),
  clean_occurrence_rows = count_names(raw$scientificName[raw$eventID %in% clean$eventID]),
  clean_single_species_events = count_names(pairs$scientificName[
    pairs$eventID %in% intersect(single_ids, clean$eventID)]))
for (field in names(expected)) stopifnot(identical(as.integer(species[[field]]), expected[[field]]))
i <- match(species$scientificName, lookup$scientificName)
stopifnot(identical(species$epbc_listed, lookup$epbc_listed[i]),
          identical(species$epbc_category, lookup$epbc_category[i]),
          identical(species$epbc_match_status, lookup$epbc_match_status[i]),
          identical(species$selected_for_model, lookup$selected[i]),
          sum(species$clean_single_species_events[species$selected_for_model]) == 247406L)
check_percentage <- function(actual, numerator, denominator) {
  expected <- ifelse(denominator == 0, NA_real_, 100 * numerator / denominator)
  stopifnot(isTRUE(all.equal(actual, expected, tolerance = 1e-12)))
}
check_percentage(species$retention_raw_to_clean_percent, species$clean_events, species$raw_events)
check_percentage(species$retention_raw_single_to_clean_single_percent,
                 species$clean_single_species_events, species$raw_single_species_events)
# Category counts are unions of events, never sums of per-species event counts.
groups <- ifelse(lookup$epbc_listed %in% TRUE, lookup$epbc_category,
                 "not_confirmed_listed_or_unresolved")
for (row in seq_len(nrow(category))) {
  key <- category$epbc_category[row]
  names_in_category <- lookup$scientificName[groups == key]
  ids <- unique(raw$eventID[raw$scientificName %in% names_in_category])
  retained_ids <- intersect(ids, clean$eventID)
  stopifnot(category$species_count[row] == length(names_in_category),
            category$raw_events[row] == length(ids),
            category$clean_events[row] == length(retained_ids),
            category$raw_single_species_events[row] == sum(ids %in% single_ids),
            category$clean_single_species_events[row] == sum(retained_ids %in% single_ids))
}
check_percentage(category$retention_percent, category$clean_events, category$raw_events)
raw_dates <- as.Date(raw$eventDate, format = "%Y-%m-%d")
u <- raw$coordinateUncertaintyInMeters
reasons <- list(
  negative_coordinate_uncertainty = is.finite(u) & u < 0,
  zero_coordinate_uncertainty = is.finite(u) & u == 0,
  nonpositive_coordinate_uncertainty = is.finite(u) & u <= 0,
  uncertainty_over_1000m = is.finite(u) & u > 1000,
  nonfinite_or_missing_uncertainty = !is.finite(u),
  obscured_geoprivacy = !is.na(raw$geoprivacy) & raw$geoprivacy == "obscured",
  not_open_geoprivacy = is.na(raw$geoprivacy) | raw$geoprivacy != "open",
  generalised_location = !is.na(raw$dataGeneralizations) &
    raw$dataGeneralizations != "No data generalization",
  missing_generalization_flag = is.na(raw$dataGeneralizations),
  invalid_coordinates = !valid_coordinates(raw$decimalLatitude, raw$decimalLongitude),
  invalid_dates = is.na(raw_dates) | format(raw_dates, "%Y-%m-%d") != raw$eventDate,
  incomplete_species = is.na(raw$scientificName) | !nzchar(trimws(raw$scientificName)))
scopes <- list(all_events = all_ids,
  confirmed_EPBC_listed = unique(raw$eventID[raw$scientificName %in%
    lookup$scientificName[lookup$epbc_listed %in% TRUE]]),
  not_confirmed_listed_or_unresolved = unique(raw$eventID[raw$scientificName %in%
    lookup$scientificName[is.na(lookup$epbc_listed)]]))
for (scope in names(scopes)) for (reason in names(reasons)) {
  row <- exclusions[exclusions$scope == scope & exclusions$count_type == "non_exclusive" &
                      exclusions$reason == reason, ]
  bad <- raw$eventID %in% scopes[[scope]] & (is.na(reasons[[reason]]) | reasons[[reason]])
  stopifnot(nrow(row) == 1L, row$occurrence_rows == sum(bad),
            row$events == length(unique(raw$eventID[bad])),
            row$denominator_events == length(scopes[[scope]]))
}
flow <- read_csv("outputs/tables/qc_filter_flow.csv", show_col_types = FALSE)
flow <- flow[!is.na(flow$events_excluded), ]
sequential <- exclusions[exclusions$scope == "all_events" & exclusions$count_type == "sequential", ]
index <- match(flow$stage, sequential$reason)
stopifnot(!anyNA(index), nrow(sequential) == nrow(flow),
          all(sequential$events[index] == flow$events_excluded),
          all(sequential$events_remaining[index] == flow$events_remaining))
# Verify complete QC exclusion independently; reason-specific reconciliation is
# also asserted by the summary builder against the existing sequential QC flow.
stopifnot(sum(!all_ids %in% clean$eventID) == 22873L,
          sum(species$raw_occurrence_rows) == nrow(raw),
          sum(species$clean_occurrence_rows) == sum(raw$eventID %in% clean$eventID),
          sum(species$raw_single_species_events) == length(single_ids),
          sum(species$clean_single_species_events) == sum(clean$n_species == 1L))
for (x in list(species, category, exclusions)) {
  stopifnot(!any(names(x) %in% c("eventID", "occurrenceID", "recordedBy",
                                "decimalLatitude", "decimalLongitude")))
}
message("Conservation retention validation passed: species counts, category event unions, percentages, source lookup and non-sensitive schemas.")
dir.create(dirname(evidence_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(test = "tests/validate_conservation_retention.R", passed = TRUE,
  passed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  artifact_md5 = tools::md5sum(c(raw_frogid_path, "data/interim/frogid/clean_events.rds",
    "data/interim/epbc/species_conservation.rds", "outputs/tables/qc_filter_flow.csv",
    list.files("outputs/tables", pattern = "^conservation_.*[.]csv$", full.names = TRUE))),
  script_md5 = tools::md5sum(c("tests/validate_conservation_retention.R",
    "R/summary/build_conservation_retention.R", "R/pipeline_helpers.R",
    "R/source_integrity.R", "config/source_checksums.csv"))), evidence_path)
