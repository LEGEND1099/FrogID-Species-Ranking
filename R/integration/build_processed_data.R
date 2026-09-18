# Materialise final analysis tables and explicitly separate predictor matrices.
source("R/pipeline_helpers.R")
primary <- readRDS("data/interim/frogid/primary_cohort.rds")
multi <- readRDS("data/interim/frogid/multispecies_cohort.rds")
environment <- readRDS("data/interim/environmental/event_environment.rds")
species <- readRDS("data/interim/epbc/species_conservation.rds")
frozen <- read_csv("outputs/tables/species_cohort.csv", show_col_types = FALSE)
stopifnot(identical(species$scientificName, frozen$scientificName),
          identical(species$selected, frozen$selected),
          identical(species$clean_single_species_events, frozen$clean_single_species_events))
environment_fields <- c(paste0("BIO", 1:19), "elevation",
                        "climatological_tavg_event_month", "climatological_prec_event_month")
temporal_fields <- c("month", "day_of_year", "month_sin", "month_cos",
                     "day_of_year_sin", "day_of_year_cos")
predictor_fields <- c("decimalLatitude", "decimalLongitude", temporal_fields, environment_fields)
row_counts <- tibble(stage = "pre_join", primary_rows = nrow(primary), multispecies_rows = nrow(multi))
stopifnot(all(c(primary$eventID, multi$eventID) %in% environment$eventID))
primary <- safe_left_join(primary, environment, by = "eventID")
multi <- safe_left_join(multi, environment, by = "eventID")
row_counts <- bind_rows(row_counts, tibble(stage = "after_environment", primary_rows = nrow(primary), multispecies_rows = nrow(multi)))
primary <- safe_left_join(primary, species |> select(scientificName, epbc_listed, epbc_category, epbc_match_status), by = "scientificName")
# Multi-species conservation stays in the species lookup; scalar event labels
# would misrepresent recordings containing several different target species.
row_counts <- bind_rows(row_counts, tibble(stage = "after_conservation", primary_rows = nrow(primary), multispecies_rows = nrow(multi)))
stopifnot(length(unique(row_counts$primary_rows)) == 1L,
          length(unique(row_counts$multispecies_rows)) == 1L)
primary <- primary |> select(eventID, scientificName, eventDate, all_of(predictor_fields),
                             epbc_listed, epbc_category, epbc_match_status)
multi <- multi |> select(eventID, eventDate, species_list, n_species, selected_species_list,
                         n_selected_species, all_species_in_vocabulary, recall_at_k_eligible,
                         all_of(predictor_fields))
species <- safe_left_join(species, read_csv("outputs/tables/species_raw_counts.csv", show_col_types = FALSE), by = "scientificName")
attr(primary, "predictor_columns") <- predictor_fields
attr(multi, "predictor_columns") <- predictor_fields
attr(primary, "target_column") <- "scientificName"
attr(multi, "target_column") <- "species_list"
attr(primary, "identifier_column") <- attr(multi, "identifier_column") <- "eventID"
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
saveRDS(primary, "data/processed/frog_primary_multiclass.rds")
saveRDS(multi, "data/processed/frog_multispecies_extension.rds")
saveRDS(species, "data/processed/species_metadata.rds")
# These companion tables contain predictors ONLY, aligned row-for-row with the
# named analysis datasets; no target, event ID, QC, observer or EPBC metadata.
primary_predictors <- as_tibble(primary[predictor_fields])
multi_predictors <- as_tibble(multi[predictor_fields])
saveRDS(primary_predictors, "data/processed/frog_primary_predictors.rds")
saveRDS(multi_predictors, "data/processed/frog_multispecies_predictors.rds")
saveRDS(row_counts, "data/interim/frogid/integration_row_counts.rds")
write_csv(row_counts, "outputs/tables/integration_row_counts.csv")

dimension_row <- function(dataset, x, unit) tibble(dataset = dataset, rows = nrow(x), columns = ncol(x), unit = unit)
dimensions <- bind_rows(
  dimension_row("frog_primary_multiclass", primary, "selected clean single-species recording"),
  dimension_row("frog_multispecies_extension", multi, "clean multi-species recording with selected-species overlap"),
  dimension_row("species_metadata", species, "raw scientific name"),
  dimension_row("frog_primary_predictors", primary_predictors, "primary recording, predictors only"),
  dimension_row("frog_multispecies_predictors", multi_predictors, "extension recording, predictors only"),
  dimension_row("multispecies_recall_at_k_eligible", multi[multi$recall_at_k_eligible, ], "all original species in vocabulary"))
write_csv(dimensions, "outputs/tables/dataset_dimensions.csv")

missingness <- function(x, dataset) {
  n_missing <- colSums(is.na(x[environment_fields]))
  tibble(dataset = dataset, feature = c(environment_fields, "any_environmental_feature"),
         n_events = nrow(x), missing_n = c(n_missing, sum(!complete.cases(x[environment_fields]))),
         missing_percent = 100 * missing_n / n_events)
}
write_csv(bind_rows(missingness(environment, "all_clean_events"),
                    missingness(primary, "frog_primary_multiclass"),
                    missingness(multi, "frog_multispecies_extension"),
                    missingness(multi[multi$recall_at_k_eligible, ], "multispecies_recall_at_k_eligible")),
          "outputs/tables/environmental_missingness.csv")
roles <- bind_rows(
  tibble(column = predictor_fields, role = "predictor",
         interpretation = c("public un-generalised latitude", "public un-generalised longitude",
                            rep("calendar feature from supplied eventDate", 6),
                            rep("WorldClim 2.1 climatology (1970-2000)", 19),
                            "WorldClim elevation (metres)",
                            "1970-2000 climatological mean temperature for recording month (degrees C)",
                            "1970-2000 climatological precipitation for recording month (mm)")),
  tibble(column = c("scientificName", "species_list", "selected_species_list", "eventID", "eventDate",
                    "epbc_listed", "epbc_category", "epbc_match_status", "n_species", "n_selected_species",
                    "all_species_in_vocabulary", "recall_at_k_eligible"),
         role = c(rep("target_or_target_metadata", 3), "identifier", "audit_date", rep("evaluation_metadata", 7)),
         interpretation = "excluded from predictor matrices"))
write_csv(roles, "outputs/tables/feature_roles.csv")
print(dimensions, width = Inf)
message("Final datasets written with 30 whitelisted predictors; no environmental NA rows dropped.")
