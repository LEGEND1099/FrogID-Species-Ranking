source("R/pipeline_helpers.R")
dir.create("data/interim/frogid", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
message("Reading immutable FrogID source and checking event metadata...")
frog <- read_frogid()
raw_md5 <- unname(tools::md5sum(raw_frogid_path))
stopifnot(!anyNA(frog$eventID), !any(frog$eventID == ""),
          !anyNA(frog$occurrenceID), !anyDuplicated(frog$occurrenceID))
# Unique occurrence IDs also prove that no complete rows are duplicates.
conflicts <- event_metadata_conflicts(frog)
saveRDS(conflicts, "data/interim/frogid/event_metadata_conflicts.rds")
write_csv(conflicts |> count(field, name = "conflicting_events"),
          "outputs/tables/event_metadata_conflict_summary.csv")
stopifnot(nrow(conflicts) == 0L)

# Full original labels are constructed BEFORE any occurrence QC filtering.
species_by_event <- frog |> group_by(eventID) |>
  summarise(species_list = list(sort(unique(scientificName))), .groups = "drop")
species_by_event$n_species <- lengths(species_by_event$species_list)
events <- frog |> distinct(eventID, .keep_all = TRUE) |>
  select(eventID, decimalLatitude, decimalLongitude, eventDate, eventTime, recordedBy,
         coordinateUncertaintyInMeters, geoprivacy, dataGeneralizations) |>
  safe_left_join(species_by_event, by = "eventID")

uncertainty <- frog |> filter(!is.finite(coordinateUncertaintyInMeters) |
                               coordinateUncertaintyInMeters <= 0) |>
  group_by(coordinateUncertaintyInMeters) |>
  summarise(occurrence_rows = n(), events = n_distinct(eventID), .groups = "drop") |>
  mutate(problem = case_when(is.na(coordinateUncertaintyInMeters) ~ "missing",
                            !is.finite(coordinateUncertaintyInMeters) ~ "nonfinite",
                            coordinateUncertaintyInMeters < 0 ~ "invalid_negative",
                            TRUE ~ "zero_not_usable"))
write_csv(uncertainty, "outputs/tables/coordinate_uncertainty_diagnostics.csv")
time_diagnostics <- frog |>
  mutate(format_pattern = gsub("[0-9]", "D", eventTime),
         suffix = sub("^[0-9]{2}:[0-9]{2}:[0-9]{2}", "", eventTime),
         parseable_clock = grepl("^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](UTC|[+-][0-9]{4})$", eventTime)) |>
  group_by(format_pattern, suffix, parseable_clock) |>
  summarise(occurrence_rows = n(), events = n_distinct(eventID), .groups = "drop")
write_csv(time_diagnostics, "outputs/tables/event_time_diagnostics.csv")

parsed_dates <- as.Date(frog$eventDate, format = "%Y-%m-%d")
checks <- list(
  complete_species = !is.na(frog$scientificName) & nzchar(trimws(frog$scientificName)),
  valid_coordinates = valid_coordinates(frog$decimalLatitude, frog$decimalLongitude),
  positive_uncertainty_at_most_1000m = valid_uncertainty(frog$coordinateUncertaintyInMeters),
  open_geoprivacy = !is.na(frog$geoprivacy) & frog$geoprivacy == "open",
  no_data_generalization = !is.na(frog$dataGeneralizations) & frog$dataGeneralizations == "No data generalization",
  valid_event_date = !is.na(parsed_dates) & format(parsed_dates, "%Y-%m-%d") == frog$eventDate)
keep <- rep(TRUE, nrow(events))
flow <- tibble(stage = "raw_events", events_remaining = nrow(events), events_excluded = 0L)
for (stage in names(checks)) {
  bad_ids <- unique(frog$eventID[is.na(checks[[stage]]) | !checks[[stage]]])
  previous <- sum(keep)
  keep <- keep & !events$eventID %in% bad_ids
  flow <- bind_rows(flow, tibble(stage = stage, events_remaining = sum(keep),
                                events_excluded = previous - sum(keep)))
}
clean <- add_calendar_features(events[keep, ])
stopifnot(!anyDuplicated(clean$eventID))
single <- clean |> filter(n_species == 1L)
single$scientificName <- vapply(single$species_list, `[`, character(1), 1L)
counts <- tibble(scientificName = sort(unique(frog$scientificName))) |>
  safe_left_join(single |> count(scientificName, name = "clean_single_species_events"), by = "scientificName") |>
  mutate(clean_single_species_events = coalesce(clean_single_species_events, 0L))
cohort <- select_species(counts)
write_csv(cohort, "outputs/tables/species_cohort.csv")
vocabulary <- cohort$scientificName[cohort$selected]
primary <- single |> filter(scientificName %in% vocabulary)
multi <- clean |> filter(n_species >= 2L)
multi$selected_species_list <- lapply(multi$species_list, intersect, y = vocabulary)
multi$n_selected_species <- lengths(multi$selected_species_list)
multi$all_species_in_vocabulary <- multi$n_selected_species == multi$n_species
multi$recall_at_k_eligible <- multi$all_species_in_vocabulary
relevant_multi <- multi |> filter(n_selected_species > 0L)
flow <- bind_rows(flow,
  tibble(stage = c("clean_single_species_events", "selected_primary_events", "clean_multispecies_events",
                  "selected_relevant_multispecies_events", "recall_at_k_eligible_multispecies_events"),
         events_remaining = c(nrow(single), nrow(primary), nrow(multi), nrow(relevant_multi),
                              sum(relevant_multi$recall_at_k_eligible)), events_excluded = NA_integer_))
write_csv(flow, "outputs/tables/qc_filter_flow.csv")
raw_species_counts <- frog |> distinct(eventID, scientificName) |>
  count(scientificName, name = "raw_events") |>
  safe_left_join(frog |> count(scientificName, name = "raw_occurrence_rows"), by = "scientificName")
write_csv(raw_species_counts, "outputs/tables/species_raw_counts.csv")
saveRDS(clean, "data/interim/frogid/clean_events.rds")
saveRDS(primary, "data/interim/frogid/primary_cohort.rds")
saveRDS(relevant_multi, "data/interim/frogid/multispecies_cohort.rds")
saveRDS(list(raw_md5 = raw_md5, raw_rows = nrow(frog), raw_columns = ncol(frog),
             raw_events = nrow(events), raw_species = n_distinct(frog$scientificName),
             raw_single_events = sum(events$n_species == 1L), raw_multi_events = sum(events$n_species >= 2L),
             clean_events = nrow(clean), clean_single_events = nrow(single),
             primary_events = nrow(primary), multi_events = nrow(relevant_multi),
             metadata_conflicts = nrow(conflicts), vocabulary = vocabulary,
             threshold_used = unique(cohort$threshold_used),
             generated_at = format(Sys.time(), tz = "UTC", usetz = TRUE)),
        "data/interim/frogid/cohort_manifest.rds")
stopifnot(identical(raw_md5, unname(tools::md5sum(raw_frogid_path))))
print(flow, n = Inf)
print(cohort |> filter(selected), n = Inf)
message("Cohorts constructed; source file checksum unchanged.")
