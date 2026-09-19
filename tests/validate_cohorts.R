source("R/pipeline_helpers.R")
stopifnot(identical(valid_uncertainty(c(-2147480, -1, 0, NA, Inf, 1, 1000, 1001)),
                    c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, FALSE)))
stopifnot(identical(valid_coordinates(c(0, NA, 91, 10), c(0, 10, 20, Inf)), c(TRUE, FALSE, FALSE, FALSE)))
counts <- tibble(scientificName = sprintf("Species %02d", 1:30), clean_single_species_events = rep(2000L, 30))
selected <- select_species(counts)
stopifnot(sum(selected$selected) == 25L, all(selected$threshold_used == 2000L),
          identical(selected$scientificName[selected$selected], counts$scientificName[1:25]))
counts$clean_single_species_events <- c(rep(2000L, 10), rep(1000L, 10), rep(999L, 10))
selected <- select_species(counts)
stopifnot(sum(selected$selected) == 20L, all(selected$threshold_used == 1000L))
bad <- tibble(eventID = c("a", "a"), decimalLatitude = c(1, 1), decimalLongitude = c(2, 2),
              eventDate = c("2020-01-01", "2020-01-01"), eventTime = c("12:00:00UTC", NA), recordedBy = c("1", "1"))
stopifnot(nrow(event_metadata_conflicts(bad)) == 1L)
stopifnot(inherits(try(safe_left_join(tibble(eventID="a"), tibble(eventID=c("a","a")), "eventID"), silent=TRUE), "try-error"))
clean <- readRDS("data/interim/frogid/clean_events.rds")
primary <- readRDS("data/interim/frogid/primary_cohort.rds")
multi <- readRDS("data/interim/frogid/multispecies_cohort.rds")
manifest <- readRDS("data/interim/frogid/cohort_manifest.rds")
stopifnot(!anyDuplicated(clean$eventID), all(valid_uncertainty(clean$coordinateUncertaintyInMeters)),
          all(valid_coordinates(clean$decimalLatitude, clean$decimalLongitude)),
          all(clean$geoprivacy == "open"), all(clean$dataGeneralizations == "No data generalization"),
          all(primary$n_species == 1), all(primary$scientificName %in% manifest$vocabulary),
          all(multi$n_species >= 2), all(lengths(multi$species_list) == multi$n_species),
          all(lengths(multi$selected_species_list) > 0),
          identical(multi$all_species_in_vocabulary, multi$n_species == multi$n_selected_species),
          identical(multi$recall_at_k_eligible, multi$all_species_in_vocabulary),
          !any(primary$eventID %in% multi$eventID))
message("Cohort validation passed.")
dir.create("data/interim/validation", recursive = TRUE, showWarnings = FALSE)
saveRDS(list(test = "tests/validate_cohorts.R",
             passed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             artifact_md5 = tools::md5sum(c("data/interim/frogid/clean_events.rds",
               "data/interim/frogid/primary_cohort.rds", "data/interim/frogid/multispecies_cohort.rds",
               "data/interim/frogid/cohort_manifest.rds")),
             script_md5 = tools::md5sum(c("tests/validate_cohorts.R", "R/pipeline_helpers.R",
               "R/cleaning/build_cohorts.R", "R/source_integrity.R"))),
        "data/interim/validation/cohort_validation.rds")
