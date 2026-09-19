# Aggregate preparation for future conservation/geoprivacy EDA. No event IDs,
# observer IDs, or point coordinates are written to public outputs.
source("R/pipeline_helpers.R")

build_conservation_retention <- function() {
  raw <- read_frogid()
  clean <- readRDS("data/interim/frogid/clean_events.rds")
  lookup <- readRDS("data/interim/epbc/species_conservation.rds")
  cohort <- read_csv("outputs/tables/species_cohort.csv", show_col_types = FALSE)
  previous_flow <- read_csv("outputs/tables/qc_filter_flow.csv", show_col_types = FALSE)
  epbc_manifest <- read_csv("data/raw/epbc/source_manifest.csv",
                            col_types = cols(.default = col_character()))
  verify_source(file.path("data/raw/epbc", epbc_manifest$local_filename))
  stopifnot(!anyDuplicated(lookup$scientificName),
            setequal(lookup$scientificName, raw$scientificName),
            is.logical(lookup$epbc_listed), !any(lookup$epbc_listed %in% FALSE),
            identical(is.na(lookup$epbc_listed), is.na(lookup$epbc_category)),
            !anyDuplicated(clean$eventID))

  group_listed <- "confirmed_EPBC_listed"
  group_unresolved <- "not_confirmed_listed_or_unresolved"
  lookup$conservation_group <- ifelse(lookup$epbc_listed %in% TRUE,
                                       group_listed, group_unresolved)
  # A scope contains recordings with at least one member taxon. Mixed-category
  # recordings belong to several scopes, so scope event totals are non-additive.
  event_ids <- unique(raw$eventID)
  event_index <- match(raw$eventID, event_ids)
  event_row_counts <- tabulate(event_index, nbins = length(event_ids))
  pairs <- raw |> distinct(eventID, scientificName)
  pairs$event_index <- match(pairs$eventID, event_ids)
  n_species <- tabulate(pairs$event_index, nbins = length(event_ids))
  parsed_dates <- as.Date(raw$eventDate, format = "%Y-%m-%d")
  row_checks <- list(
    complete_species = !is.na(raw$scientificName) & nzchar(trimws(raw$scientificName)),
    valid_coordinates = valid_coordinates(raw$decimalLatitude, raw$decimalLongitude),
    positive_uncertainty_at_most_1000m = valid_uncertainty(raw$coordinateUncertaintyInMeters),
    open_geoprivacy = !is.na(raw$geoprivacy) & raw$geoprivacy == "open",
    no_data_generalization = !is.na(raw$dataGeneralizations) &
      raw$dataGeneralizations == "No data generalization",
    valid_event_date = !is.na(parsed_dates) &
      format(parsed_dates, "%Y-%m-%d") == raw$eventDate
  )
  event_checks <- lapply(row_checks, function(ok) {
    bad_events <- unique(event_index[is.na(ok) | !ok])
    !seq_along(event_ids) %in% bad_events
  })
  clean_mask <- Reduce(`&`, event_checks)
  stopifnot(setequal(event_ids[clean_mask], clean$eventID))

  pairs$raw_single <- n_species[pairs$event_index] == 1L
  pairs$clean <- clean_mask[pairs$event_index]
  pairs$open <- event_checks$open_geoprivacy[pairs$event_index]
  pairs$precision <- event_checks$positive_uncertainty_at_most_1000m[pairs$event_index]
  pairs$no_generalization <- event_checks$no_data_generalization[pairs$event_index]
  counts <- pairs |>
    group_by(scientificName) |>
    summarise(raw_events = n(), raw_single_species_events = sum(raw_single),
              open_location_events = sum(open), precision_eligible_events = sum(precision),
              no_generalization_events = sum(no_generalization),
              clean_events = sum(clean),
              clean_single_species_events = sum(clean & raw_single), .groups = "drop")
  occurrence_counts <- raw |>
    mutate(clean = clean_mask[event_index]) |>
    group_by(scientificName) |>
    summarise(raw_occurrence_rows = n(), clean_occurrence_rows = sum(clean), .groups = "drop")
  percent <- function(numerator, denominator) {
    ifelse(denominator == 0, NA_real_, 100 * numerator / denominator)
  }
  species_retention <- lookup |>
    select(scientificName, epbc_match_status, epbc_listed, epbc_category,
           conservation_group, selected_for_model = selected) |>
    left_join(occurrence_counts, by = "scientificName", relationship = "one-to-one") |>
    left_join(counts, by = "scientificName", relationship = "one-to-one") |>
    mutate(retention_raw_to_clean_percent = percent(clean_events, raw_events),
           retention_raw_single_to_clean_single_percent =
             percent(clean_single_species_events, raw_single_species_events)) |>
    arrange(scientificName)
  species_index <- match(cohort$scientificName, species_retention$scientificName)
  stopifnot(nrow(species_retention) == 216L, !anyDuplicated(species_retention$scientificName),
            identical(species_retention$selected_for_model[species_index], cohort$selected),
            all(species_retention$clean_single_species_events[species_index] ==
                  cohort$clean_single_species_events),
            sum(species_retention$raw_occurrence_rows) == nrow(raw),
            sum(species_retention$clean_occurrence_rows) == sum(event_row_counts[clean_mask]),
            sum(species_retention$raw_single_species_events) == sum(n_species == 1L),
            sum(species_retention$clean_single_species_events) == sum(clean_mask & n_species == 1L))

  # Category event totals use set unions, never sums of species event totals.
  summary_for_names <- function(taxon_names) {
    idx <- unique(pairs$event_index[pairs$scientificName %in% taxon_names])
    rows <- raw$scientificName %in% taxon_names
    tibble(species_count = length(taxon_names),
           raw_occurrence_rows = sum(rows),
           clean_occurrence_rows = sum(rows & clean_mask[event_index]),
           raw_events = length(idx), clean_events = sum(clean_mask[idx]),
           raw_single_species_events = sum(n_species[idx] == 1L),
           clean_single_species_events = sum(clean_mask[idx] & n_species[idx] == 1L),
           retention_percent = percent(sum(clean_mask[idx]), length(idx)),
           selected_species_count = sum(species_retention$selected_for_model[
             match(taxon_names, species_retention$scientificName)]))
  }
  category_keys <- species_retention |>
    transmute(conservation_group, epbc_category = coalesce(epbc_category, group_unresolved)) |>
    distinct() |>
    arrange(conservation_group, epbc_category)
  category_retention <- bind_rows(lapply(seq_len(nrow(category_keys)), function(i) {
    key <- category_keys[i, ]
    names_in_category <- species_retention$scientificName[
      species_retention$conservation_group == key$conservation_group &
        coalesce(species_retention$epbc_category, group_unresolved) == key$epbc_category]
    bind_cols(key, summary_for_names(names_in_category))
  })) |>
    mutate(event_counting = "distinct_event_union_within_category; categories_may_overlap")
  scope_names <- list(all_events = species_retention$scientificName)
  scope_names[[group_listed]] <- species_retention$scientificName[
    species_retention$conservation_group == group_listed]
  scope_names[[group_unresolved]] <- species_retention$scientificName[
    species_retention$conservation_group == group_unresolved]
  group_retention <- bind_rows(lapply(names(scope_names), function(scope) {
    bind_cols(tibble(scope = scope), summary_for_names(scope_names[[scope]]))
  })) |>
    mutate(event_counting = "distinct_event_union_within_scope; scopes_may_overlap")
  stopifnot(sum(category_retention$species_count) == nrow(species_retention),
            sum(category_retention$raw_occurrence_rows) == nrow(raw),
            sum(category_retention$clean_occurrence_rows) == sum(event_row_counts[clean_mask]),
            sum(category_retention$raw_single_species_events) == sum(n_species == 1L),
            sum(category_retention$clean_single_species_events) == sum(clean_mask & n_species == 1L),
            group_retention$raw_events[group_retention$scope == "all_events"] == length(event_ids),
            group_retention$clean_events[group_retention$scope == "all_events"] == nrow(clean))

  uncertainty <- raw$coordinateUncertaintyInMeters
  independent_failures <- list(
    negative_coordinate_uncertainty = is.finite(uncertainty) & uncertainty < 0,
    zero_coordinate_uncertainty = is.finite(uncertainty) & uncertainty == 0,
    nonpositive_coordinate_uncertainty = is.finite(uncertainty) & uncertainty <= 0,
    uncertainty_over_1000m = is.finite(uncertainty) & uncertainty > 1000,
    nonfinite_or_missing_uncertainty = !is.finite(uncertainty),
    obscured_geoprivacy = !is.na(raw$geoprivacy) & raw$geoprivacy == "obscured",
    not_open_geoprivacy = !row_checks$open_geoprivacy,
    generalised_location = !is.na(raw$dataGeneralizations) &
      raw$dataGeneralizations != "No data generalization",
    missing_generalization_flag = is.na(raw$dataGeneralizations),
    invalid_coordinates = !row_checks$valid_coordinates,
    invalid_dates = is.na(row_checks$valid_event_date) | !row_checks$valid_event_date,
    incomplete_species = !row_checks$complete_species
  )
  exclusion_summary <- bind_rows(lapply(names(scope_names), function(scope) {
    scope_idx <- unique(pairs$event_index[pairs$scientificName %in% scope_names[[scope]]])
    scope_mask <- seq_along(event_ids) %in% scope_idx
    scope_rows <- scope_mask[event_index]
    # Direct failing rows count all co-detected source records in scope events;
    # event failure can originate from any species in the original recording.
    independent <- bind_rows(lapply(names(independent_failures), function(reason) {
      bad_rows <- independent_failures[[reason]] & scope_rows
      bad_rows[is.na(bad_rows)] <- TRUE
      affected <- unique(event_index[bad_rows])
      tibble(scope = scope, count_type = "non_exclusive", reason = reason,
             occurrence_rows = sum(bad_rows), events = length(affected),
             denominator_events = length(scope_idx),
             percent_events = percent(length(affected), length(scope_idx)),
             stage_order = NA_integer_, events_remaining = NA_integer_,
             scope_overlap = "non_exclusive; mixed_taxon_events_overlap_scopes",
             occurrence_basis = "direct_failing_source_rows_in_scope_events")
    }))
    keep <- scope_mask
    sequential <- tibble(scope = scope, count_type = "sequential", reason = "raw_events",
                         occurrence_rows = 0L, events = 0L,
                         denominator_events = length(scope_idx), percent_events = 0,
                         stage_order = 0L, events_remaining = sum(keep),
                         scope_overlap = "non_exclusive; mixed_taxon_events_overlap_scopes",
                         occurrence_basis = "all_source_rows_of_events_excluded_at_this_stage")
    for (i in seq_along(event_checks)) {
      reason <- names(event_checks)[i]
      rejected <- keep & !event_checks[[i]]
      keep <- keep & event_checks[[i]]
      sequential <- bind_rows(sequential,
        tibble(scope = scope, count_type = "sequential", reason = reason,
               occurrence_rows = sum(event_row_counts[rejected]), events = sum(rejected),
               denominator_events = length(scope_idx),
               percent_events = percent(sum(rejected), length(scope_idx)),
               stage_order = i, events_remaining = sum(keep),
               scope_overlap = "non_exclusive; mixed_taxon_events_overlap_scopes",
               occurrence_basis = "all_source_rows_of_events_excluded_at_this_stage"))
    }
    stopifnot(sum(sequential$events) + sum(keep) == length(scope_idx),
              sum(keep) == sum(clean_mask[scope_idx]))
    bind_rows(independent, sequential)
  }))
  # The non-exclusive reason rows overlap: negative/zero are subsets of
  # nonpositive, and privacy/generalisation can overlap excessive uncertainty.
  # Only sequential event exclusions can be added within a scope.
  observed_flow <- exclusion_summary |>
    filter(scope == "all_events", count_type == "sequential")
  flow_index <- match(observed_flow$reason, previous_flow$stage)
  stopifnot(!anyNA(flow_index),
            all(observed_flow$events_remaining == previous_flow$events_remaining[flow_index]),
            all(observed_flow$events == previous_flow$events_excluded[flow_index]))
  diagnostics <- read_csv("outputs/tables/coordinate_uncertainty_diagnostics.csv", show_col_types = FALSE)
  for (kind in c("invalid_negative", "zero_not_usable")) {
    reason <- if (kind == "invalid_negative") "negative_coordinate_uncertainty" else "zero_coordinate_uncertainty"
    observed <- exclusion_summary |>
      filter(scope == "all_events", count_type == "non_exclusive", .data$reason == .env$reason)
    # Row counts are additive across values. Events are deliberately recomputed
    # as a union; the same recording could contain several bad values.
    stopifnot(observed$occurrence_rows == sum(diagnostics$occurrence_rows[diagnostics$problem == kind]))
  }
  outputs <- list(conservation_species_retention = species_retention,
                  conservation_category_retention = category_retention,
                  conservation_group_retention = group_retention,
                  conservation_qc_exclusion_summary = exclusion_summary)
  dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
  for (name in names(outputs)) {
    stopifnot(!any(c("eventID", "occurrenceID", "recordedBy", "decimalLatitude", "decimalLongitude") %in%
                    names(outputs[[name]])))
    write_csv(outputs[[name]], file.path("outputs/tables", paste0(name, ".csv")), na = "NA")
  }
  message("Conservation retention prepared: ", nrow(species_retention), " species; ",
          sum(species_retention$epbc_listed %in% TRUE), " confirmed listed; ",
          sum(species_retention$epbc_listed %in% TRUE & species_retention$clean_events > 0),
          " confirmed listed surviving whole-event QC. Non-exclusive reasons and scopes are labelled.")
  print(category_retention, width = Inf)
  print(group_retention, width = Inf)
  invisible(outputs)
}

if (sys.nframe() == 0L) build_conservation_retention()
