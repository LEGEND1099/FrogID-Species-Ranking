# Attach current EPBC metadata after the model vocabulary has been frozen.
# A non-match to a threatened-only list is unresolved, not confirmed unlisted.
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tibble)
})

cohort_path <- file.path("outputs", "tables", "species_cohort.csv")
manifest_path <- file.path("data", "raw", "epbc", "source_manifest.csv")
if (!file.exists(cohort_path)) stop("Build and freeze the clean species cohort first.")
if (!file.exists(manifest_path)) stop("Run R/acquisition/download_epbc.R first.")
cohort <- read_csv(cohort_path, show_col_types = FALSE)
stopifnot(all(c("scientificName", "clean_single_species_events", "selected",
                "threshold_used") %in% names(cohort)),
          !anyNA(cohort$scientificName), !anyDuplicated(cohort$scientificName),
          is.logical(cohort$selected), !anyNA(cohort$selected))
manifest <- read_csv(manifest_path, col_types = cols(.default = col_character()))
stopifnot(nrow(manifest) == 1L)
source_path <- file.path("data", "raw", "epbc", manifest$local_filename)
stopifnot(file.exists(source_path),
          unname(tools::md5sum(source_path)) == manifest$md5)
epbc <- read_csv(source_path, col_types = cols(.default = col_character()),
                 na = c("", "-"), show_col_types = FALSE) |>
  filter(Class == "Amphibia")
stopifnot(nrow(epbc) > 0L, !anyNA(epbc[["Scientific Name"]]),
          !anyNA(epbc[["Threatened status"]]))
normalize_name <- function(x) tolower(gsub("[[:space:]]+", " ", trimws(x)))
listed_names <- normalize_name(epbc[["Scientific Name"]])
current_names <- normalize_name(epbc[["Current Scientific Name"]])

# These are the only accepted matches, in order. The official current-name
# column provides authoritative equivalence; it is not a fuzzy synonym search.
match_one <- function(name) {
  candidates <- list(
    exact_listed_name = which(epbc[["Scientific Name"]] == name),
    normalized_listed_name = which(listed_names == normalize_name(name)),
    exact_official_current_name = which(epbc[["Current Scientific Name"]] == name),
    normalized_official_current_name = which(current_names == normalize_name(name))
  )
  hit_type <- names(candidates)[lengths(candidates) > 0L]
  hit <- if (length(hit_type)) candidates[[hit_type[1]]] else integer()
  # A binomial may have listed subspecies without being an exact listed taxon.
  # Record that situation for review, never propagate the subspecies status.
  subordinate_taxa <- epbc[["Scientific Name"]][
    startsWith(listed_names, paste0(normalize_name(name), " ")) |
      (!is.na(current_names) & startsWith(current_names, paste0(normalize_name(name), " ")))
  ]
  matched <- length(hit) == 1L
  row <- if (matched) hit else NA_integer_
  tibble(
    scientificName = name,
    epbc_listed = if (matched) TRUE else NA,
    epbc_category = if (matched) epbc[["Threatened status"]][row] else NA_character_,
    epbc_match_status = if (matched) hit_type[1] else if (length(hit) > 1L) {
      "unresolved_ambiguous_official_name"
    } else if (length(subordinate_taxa)) {
      "unresolved_listed_subspecies_only"
    } else "unmatched_to_official_threatened_list",
    epbc_source_scientific_name = if (matched) epbc[["Scientific Name"]][row] else NA_character_,
    epbc_source_current_name = if (matched) epbc[["Current Scientific Name"]][row] else NA_character_,
    epbc_sprat_taxon_id = if (matched) epbc[["Listed SPRAT TaxonID"]][row] else NA_character_,
    epbc_current_sprat_taxon_id = if (matched) epbc[["Current SPRAT TaxonID"]][row] else NA_character_,
    epbc_profile_url = if (matched) epbc$Profile[row] else NA_character_,
    epbc_listed_subordinate_taxa = if (length(subordinate_taxa)) {
      paste(sort(unique(subordinate_taxa)), collapse = "; ")
    } else NA_character_,
    epbc_source_extracted_date = manifest$source_extracted_date,
    epbc_retrieved_at_utc = manifest$retrieved_at_utc,
    epbc_source_url = manifest$source_url
  )
}
lookup <- bind_rows(lapply(cohort$scientificName, match_one))
metadata <- left_join(cohort, lookup, by = "scientificName", relationship = "one-to-one")
stopifnot(nrow(metadata) == nrow(cohort), !anyDuplicated(metadata$scientificName),
          all(is.na(metadata$epbc_category) == is.na(metadata$epbc_listed)))

interim_dir <- file.path("data", "interim", "epbc")
dir.create(interim_dir, recursive = TRUE, showWarnings = FALSE)
saveRDS(metadata, file.path(interim_dir, "species_conservation.rds"))
write_csv(metadata |>
            filter(is.na(epbc_listed)) |>
            select(scientificName, clean_single_species_events, selected,
                   epbc_listed, epbc_category, epbc_match_status,
                   epbc_listed_subordinate_taxa),
          file.path("outputs", "tables", "epbc_unmatched_species.csv"), na = "NA")

# Every alias mapping used is inspectable and directly supported by a source row.
write_csv(metadata |>
            filter(grepl("official_current_name", epbc_match_status)) |>
            select(scientificName, epbc_source_scientific_name,
                   epbc_source_current_name, epbc_sprat_taxon_id,
                   epbc_current_sprat_taxon_id, epbc_category, epbc_source_url),
          file.path("outputs", "tables", "epbc_authoritative_name_mappings.csv"))
write_csv(metadata |>
            select(scientificName, clean_single_species_events, selected,
                   epbc_listed, epbc_category, epbc_match_status,
                   epbc_source_scientific_name, epbc_source_current_name),
          file.path("outputs", "tables", "species_conservation_summary.csv"), na = "NA")
category_summary <- bind_rows(
  mutate(metadata, cohort = "all_raw_species"),
  metadata |> filter(selected) |> mutate(cohort = "selected_model_species")
) |>
  mutate(epbc_category = coalesce(epbc_category, "Unresolved / no exact listed-name match")) |>
  group_by(cohort, epbc_category) |>
  summarise(species = n(), clean_single_species_events = sum(clean_single_species_events),
            .groups = "drop")
write_csv(category_summary, file.path("outputs", "tables", "epbc_category_counts.csv"))
message("EPBC source: ", manifest$resource_name)
message("Matched listed taxa: ", sum(metadata$epbc_listed %in% TRUE), "/", nrow(metadata))
message("Selected model species: ", sum(metadata$selected), "; matched EPBC-listed: ",
        sum(metadata$selected & metadata$epbc_listed %in% TRUE))
print(category_summary)
