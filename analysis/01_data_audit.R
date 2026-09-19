# EDA-01: Data audit / sanity check
#
# Purpose:
# Confirm that the certified processed datasets entering EDA still have the
# expected dimensions, classes, predictors, types, alignment and missingness.
#
# This script does NOT clean, impute, scale, filter or otherwise modify data.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tibble)
})

# -------------------------------------------------------------------------
# Inputs
# -------------------------------------------------------------------------

paths <- c(
  primary = "data/processed/frog_primary_multiclass.rds",
  primary_predictors = "data/processed/frog_primary_predictors.rds",
  multispecies = "data/processed/frog_multispecies_extension.rds",
  multispecies_predictors = "data/processed/frog_multispecies_predictors.rds",
  species_metadata = "data/processed/species_metadata.rds"
)

missing_files <- paths[!file.exists(paths)]

if (length(missing_files)) {
  stop(
    "Missing processed EDA input(s): ",
    paste(missing_files, collapse = ", "),
    "\nRun the certified data-preparation pipeline first.",
    call. = FALSE
  )
}

primary <- readRDS(paths["primary"])
primary_predictors <- readRDS(paths["primary_predictors"])
multi <- readRDS(paths["multispecies"])
multi_predictors <- readRDS(paths["multispecies_predictors"])
species <- readRDS(paths["species_metadata"])


# -------------------------------------------------------------------------
# Expected predictor structure
# -------------------------------------------------------------------------

geographic_features <- c(
  "decimalLatitude",
  "decimalLongitude"
)

temporal_features <- c(
  "month",
  "day_of_year",
  "month_sin",
  "month_cos",
  "day_of_year_sin",
  "day_of_year_cos"
)

environmental_features <- c(
  paste0("BIO", 1:19),
  "elevation",
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

expected_predictors <- c(
  geographic_features,
  temporal_features,
  environmental_features
)

stopifnot(
  length(expected_predictors) == 30L,
  length(geographic_features) == 2L,
  length(temporal_features) == 6L,
  length(environmental_features) == 22L
)


# -------------------------------------------------------------------------
# Certified-dataset sanity checks
# -------------------------------------------------------------------------

stopifnot(
  nrow(primary) == 247406L,
  ncol(primary) == 36L,

  nrow(multi) == 213675L,
  ncol(multi) == 38L,

  nrow(primary_predictors) == 247406L,
  ncol(primary_predictors) == 30L,

  nrow(multi_predictors) == 213675L,
  ncol(multi_predictors) == 30L,

  nrow(species) == 216L
)

# Event identifiers must still be unique.
stopifnot(
  !anyNA(primary$eventID),
  !anyDuplicated(primary$eventID),
  !anyNA(multi$eventID),
  !anyDuplicated(multi$eventID)
)

# Target vocabulary must still contain the same 18 objectively selected species.
primary_classes <- sort(unique(primary$scientificName))
selected_classes <- sort(species$scientificName[species$selected])

stopifnot(
  length(primary_classes) == 18L,
  length(selected_classes) == 18L,
  identical(primary_classes, selected_classes),
  !anyNA(primary$scientificName)
)

# Predictor whitelist must be exactly the certified 30 columns.
stopifnot(
  identical(attr(primary, "predictor_columns"), expected_predictors),
  identical(attr(multi, "predictor_columns"), expected_predictors),
  identical(names(primary_predictors), expected_predictors),
  identical(names(multi_predictors), expected_predictors)
)

# Predictor-only objects must still line up row-for-row with their labelled data.
stopifnot(
  identical(
    as.data.frame(primary[expected_predictors]),
    as.data.frame(primary_predictors)
  ),
  identical(
    as.data.frame(multi[expected_predictors]),
    as.data.frame(multi_predictors)
  )
)

# Every model predictor must be numeric.
stopifnot(
  all(vapply(primary_predictors, is.numeric, logical(1))),
  all(vapply(multi_predictors, is.numeric, logical(1)))
)

# Identifier / target / date fields should not be missing in the primary data.
stopifnot(
  !anyNA(primary$eventID),
  !anyNA(primary$scientificName),
  !anyNA(primary$eventDate)
)

# Geographic and calendar predictors should be complete.
stopifnot(
  !anyNA(primary[c(geographic_features, temporal_features)]),
  !anyNA(multi[c(geographic_features, temporal_features)])
)

# Confirm known environmental missingness before deeper EDA-06 investigation.
primary_environmental_na <- sum(
  !complete.cases(primary[environmental_features])
)

multi_environmental_na <- sum(
  !complete.cases(multi[environmental_features])
)

stopifnot(
  primary_environmental_na == 4806L,
  multi_environmental_na == 2009L
)


# -------------------------------------------------------------------------
# Output 1: dataset overview
# -------------------------------------------------------------------------

dataset_overview <- bind_rows(
  tibble(
    dataset = "frog_primary_multiclass",
    file = paths["primary"],
    rows = nrow(primary),
    columns = ncol(primary),
    unique_events = n_distinct(primary$eventID),
    target_classes = n_distinct(primary$scientificName),
    predictor_columns = length(expected_predictors),
    rows_with_environmental_NA = primary_environmental_na
  ),
  tibble(
    dataset = "frog_primary_predictors",
    file = paths["primary_predictors"],
    rows = nrow(primary_predictors),
    columns = ncol(primary_predictors),
    unique_events = NA_integer_,
    target_classes = NA_integer_,
    predictor_columns = ncol(primary_predictors),
    rows_with_environmental_NA =
      sum(!complete.cases(primary_predictors[environmental_features]))
  ),
  tibble(
    dataset = "frog_multispecies_extension",
    file = paths["multispecies"],
    rows = nrow(multi),
    columns = ncol(multi),
    unique_events = n_distinct(multi$eventID),
    target_classes =
      length(unique(unlist(multi$species_list, use.names = FALSE))),
    predictor_columns = length(expected_predictors),
    rows_with_environmental_NA = multi_environmental_na
  ),
  tibble(
    dataset = "frog_multispecies_predictors",
    file = paths["multispecies_predictors"],
    rows = nrow(multi_predictors),
    columns = ncol(multi_predictors),
    unique_events = NA_integer_,
    target_classes = NA_integer_,
    predictor_columns = ncol(multi_predictors),
    rows_with_environmental_NA =
      sum(!complete.cases(multi_predictors[environmental_features]))
  ),
  tibble(
    dataset = "species_metadata",
    file = paths["species_metadata"],
    rows = nrow(species),
    columns = ncol(species),
    unique_events = NA_integer_,
    target_classes = sum(species$selected),
    predictor_columns = NA_integer_,
    rows_with_environmental_NA = NA_integer_
  )
)


# -------------------------------------------------------------------------
# Output 2: predictor names / groups / R types
# -------------------------------------------------------------------------

feature_group <- case_when(
  expected_predictors %in% geographic_features ~ "geographic",
  expected_predictors %in% temporal_features ~ "temporal",
  expected_predictors %in% environmental_features ~ "environmental",
  TRUE ~ "unexpected"
)

predictor_types <- tibble(
  position = seq_along(expected_predictors),
  feature = expected_predictors,
  feature_group = feature_group,
  primary_R_type = vapply(
    primary_predictors,
    typeof,
    character(1)
  ),
  multispecies_R_type = vapply(
    multi_predictors,
    typeof,
    character(1)
  ),
  primary_numeric = vapply(
    primary_predictors,
    is.numeric,
    logical(1)
  ),
  multispecies_numeric = vapply(
    multi_predictors,
    is.numeric,
    logical(1)
  )
)

stopifnot(
  all(predictor_types$feature_group != "unexpected"),
  all(predictor_types$primary_numeric),
  all(predictor_types$multispecies_numeric)
)


# -------------------------------------------------------------------------
# Output 3: per-column missingness overview
# -------------------------------------------------------------------------

column_missingness <- function(x, dataset_name) {

  missing_n <- vapply(
    x,
    function(column) sum(is.na(column)),
    integer(1)
  )

  tibble(
    dataset = dataset_name,
    column = names(x),
    rows = nrow(x),
    missing_n = missing_n,
    missing_percent = 100 * missing_n / nrow(x)
  )
}

missingness_overview <- bind_rows(
  column_missingness(primary, "frog_primary_multiclass"),
  column_missingness(multi, "frog_multispecies_extension"),
  column_missingness(species, "species_metadata")
)


# -------------------------------------------------------------------------
# Save non-sensitive EDA-01 outputs
# -------------------------------------------------------------------------

dir.create(
  "outputs/tables",
  recursive = TRUE,
  showWarnings = FALSE
)

write_csv(
  dataset_overview,
  "outputs/tables/eda_dataset_overview.csv",
  na = "NA"
)

write_csv(
  predictor_types,
  "outputs/tables/eda_predictor_types.csv",
  na = "NA"
)

write_csv(
  missingness_overview,
  "outputs/tables/eda_missingness_overview.csv",
  na = "NA"
)


# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-01 DATA AUDIT\n")
cat("============================================================\n\n")

print(dataset_overview, width = Inf)

cat("\nPredictor groups:\n")
print(
  predictor_types |>
    count(feature_group, name = "predictors"),
  width = Inf
)

cat("\nColumns containing missing values:\n")

missing_columns <- missingness_overview |>
  filter(missing_n > 0L) |>
  arrange(dataset, desc(missing_percent), column)

if (nrow(missing_columns)) {
  print(missing_columns, n = Inf, width = Inf)
} else {
  cat("None.\n")
}

cat("\nCertified class vocabulary:\n")
cat(paste(primary_classes, collapse = ", "), "\n")

cat("\nEDA-01 PASSED\n")
cat(
  "5 processed objects checked; 18 primary classes; ",
  "30 aligned numeric predictors; certified environmental missingness preserved.\n",
  sep = ""
)
cat("No data were modified, filtered, imputed, scaled or balanced.\n")