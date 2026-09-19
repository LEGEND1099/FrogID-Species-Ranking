# Validate the EDA handoff aggregates against source rows and final RDS objects.
# These checks prepare data only; they do not perform exploratory analysis.
source("R/pipeline_helpers.R")

evidence_path <- "data/interim/validation/summary_validation.rds"
if (file.exists(evidence_path)) unlink(evidence_path)
assert <- function(condition, description) {
  if (!isTRUE(condition)) stop(description, call. = FALSE)
}
same_numeric <- function(actual, expected, description) {
  assert(isTRUE(all.equal(as.numeric(actual), as.numeric(expected),
                          check.attributes = FALSE, tolerance = 1e-10)), description)
}
read_summary <- function(name, required) {
  path <- file.path("outputs/tables", paste0(name, ".csv"))
  assert(file.exists(path), paste("Missing summary:", path))
  x <- read_csv(path, show_col_types = FALSE, progress = FALSE)
  assert(nrow(problems(x)) == 0L && all(required %in% names(x)),
         paste("Invalid schema:", name))
  # Geographic summaries may contain broad extrema; event-level locations and
  # identifiers are never appropriate columns in the committed handoff tables.
  assert(!any(names(x) %in% c("eventID", "occurrenceID", "recordedBy",
                             "decimalLatitude", "decimalLongitude",
                             "latitude", "longitude", "eventTime")),
         paste("Sensitive event-level column in public summary:", name))
  x
}
check_dataset_labels <- function(x, expected, label, unique = FALSE) {
  assert(setequal(x$dataset, expected) && (!unique || !anyDuplicated(x$dataset)),
         paste("Missing or duplicated dataset labels in", label))
}

message("Checking source-based EDA handoff counts and non-sensitive table schemas...")
raw <- read_frogid()
clean <- readRDS("data/interim/frogid/clean_events.rds")
primary <- readRDS("data/processed/frog_primary_multiclass.rds")
multi <- readRDS("data/processed/frog_multispecies_extension.rds")
primary_predictors <- readRDS("data/processed/frog_primary_predictors.rds")
multi_predictors <- readRDS("data/processed/frog_multispecies_predictors.rds")
species <- readRDS("data/processed/species_metadata.rds")
environment <- readRDS("data/interim/environmental/event_environment.rds")
raw_events <- raw[!duplicated(raw$eventID), ]
raw_events$eventDate <- as.Date(raw_events$eventDate)
datasets <- list(raw = raw_events, clean = clean, primary = primary, multispecies = multi)
environmental <- c(paste0("BIO", 1:19), "elevation", "climatological_tavg_event_month",
                   "climatological_prec_event_month")
temporal <- c("month", "day_of_year", "month_sin", "month_cos",
              "day_of_year_sin", "day_of_year_cos")
geographic <- c("decimalLatitude", "decimalLongitude")
expected_predictors <- c(geographic, temporal, environmental)
assert(ncol(primary_predictors) == 30L && setequal(names(primary_predictors), expected_predictors),
       "The primary matrix differs from the 30 expected predictors")

classes <- read_summary("class_distribution", c("scientificName", "event_count",
  "percent_primary", "cumulative_percent_primary", "rank"))
class_counts <- table(primary$scientificName)
assert(nrow(classes) == 18L && !anyDuplicated(classes$scientificName) &&
         setequal(classes$scientificName, names(class_counts)) &&
         all(diff(classes$event_count) <= 0), "Class table is incomplete or incorrectly ranked")
same_numeric(classes$event_count, class_counts[classes$scientificName],
             "Selected class counts disagree with the primary target")
same_numeric(classes$rank, seq_len(nrow(classes)), "Class rank is not consecutive")
same_numeric(classes$percent_primary, 100 * classes$event_count / nrow(primary),
             "Class percentages disagree with primary dimensions")
same_numeric(classes$cumulative_percent_primary, cumsum(classes$percent_primary),
             "Cumulative class percentages disagree with class shares")
assert(sum(classes$event_count) == nrow(primary) && min(classes$event_count) >= 2000L &&
         all(species$threshold_used == 2000L) &&
         setequal(classes$scientificName, species$scientificName[species$selected]),
       "Class summary no longer matches the objective frozen selection")

dates <- read_summary("date_range_summary", c("dataset", "n_events", "date_min", "date_max",
                                             "calendar_years", "missing_dates"))
years <- read_summary("events_by_year", c("dataset", "year", "events"))
months <- read_summary("events_by_month", c("dataset", "month", "events"))
check_dataset_labels(dates, names(datasets), "date ranges", unique = TRUE)
check_dataset_labels(years, names(datasets), "events by year")
check_dataset_labels(months, names(datasets), "events by month")
for (label in names(datasets)) {
  x <- datasets[[label]]
  event_dates <- as.Date(x$eventDate)
  row <- dates[dates$dataset == label, ]
  assert(row$n_events == nrow(x) && as.Date(row$date_min) == min(event_dates) &&
           as.Date(row$date_max) == max(event_dates) &&
           row$calendar_years == length(unique(format(event_dates, "%Y"))) &&
           row$missing_dates == sum(is.na(event_dates)), paste("Date summary disagrees:", label))
  year_counts <- table(format(event_dates, "%Y"))
  year_rows <- years[years$dataset == label, ]
  assert(!anyDuplicated(year_rows$year) && setequal(as.character(year_rows$year), names(year_counts)),
         paste("Calendar years are omitted or duplicated:", label))
  same_numeric(year_rows$events, year_counts[as.character(year_rows$year)],
               paste("Yearly event counts disagree:", label))
  month_rows <- months[months$dataset == label, ]
  month_counts <- tabulate(as.integer(format(event_dates, "%m")), nbins = 12L)
  assert(nrow(month_rows) == 12L && setequal(month_rows$month, 1:12),
         paste("Month summary does not cover 12 distinct months:", label))
  same_numeric(month_rows$events, month_counts[month_rows$month],
               paste("Monthly event counts disagree:", label))
  assert(sum(year_rows$events) == nrow(x) && sum(month_rows$events) == nrow(x),
         paste("Calendar totals changed the event unit:", label))
}

states <- read_summary("state_distribution", c("stateProvince", "raw_occurrence_rows",
                                               "raw_events", "clean_public_events"))
normalize_state <- function(x) ifelse(is.na(x) | !nzchar(x), "Missing", x)
assert(!anyDuplicated(states$stateProvince), "State distribution duplicates a state")
source_states <- normalize_state(raw$stateProvince)
output_states <- normalize_state(states$stateProvince)
assert(setequal(output_states, unique(source_states)), "State distribution omits supplied states")
count_states <- function(x) as.numeric(table(factor(x, levels = output_states)))
same_numeric(states$raw_occurrence_rows, count_states(source_states),
             "Raw state occurrence counts disagree")
same_numeric(states$raw_events, count_states(normalize_state(raw_events$stateProvince)),
             "Raw state event counts disagree")
same_numeric(states$clean_public_events,
             count_states(normalize_state(raw_events$stateProvince[raw_events$eventID %in% clean$eventID])),
             "Clean public state event counts disagree")
assert(sum(states$raw_events) == nrow(raw_events) && sum(states$clean_public_events) == nrow(clean),
       "State summaries multiply or drop events")

features <- read_summary("feature_summary", c("feature", "feature_group", "n", "missing_n",
  "missing_percent", "mean", "sd", "min", "p25", "median", "p75", "max"))
assert(nrow(features) == 30L && !anyDuplicated(features$feature) &&
         setequal(features$feature, expected_predictors), "Feature summary must contain exactly 30 predictors")
for (i in seq_len(nrow(features))) {
  field <- features$feature[i]
  x <- primary_predictors[[field]]
  group <- if (field %in% geographic) "Geographic" else if (field %in% temporal) "Temporal" else "Environmental"
  assert(tolower(features$feature_group[i]) == tolower(group) && features$n[i] == length(x),
         paste("Incorrect feature group or denominator:", field))
  same_numeric(features$missing_n[i], sum(is.na(x)), paste("Missing values changed:", field))
  same_numeric(features$missing_percent[i], 100 * mean(is.na(x)), paste("Missing percentage changed:", field))
  complete <- x[!is.na(x)]
  expected <- c(mean = mean(complete), sd = stats::sd(complete), min = min(complete),
                p25 = unname(stats::quantile(complete, .25)), median = stats::median(complete),
                p75 = unname(stats::quantile(complete, .75)), max = max(complete))
  for (metric in names(expected)) same_numeric(features[[metric]][i], expected[[metric]],
    paste("Primary numeric summary disagrees:", field, metric))
}

missingness <- read_summary("environmental_missingness",
                            c("dataset", "feature", "n_events", "missing_n", "missing_percent"))
env_datasets <- list(all_clean_events = environment, frog_primary_multiclass = primary,
                    frog_multispecies_extension = multi,
                    multispecies_recall_at_k_eligible = multi[multi$recall_at_k_eligible, ])
check_dataset_labels(missingness, names(env_datasets), "environmental missingness")
missing_rows <- function(x) sum(!stats::complete.cases(x[, environmental]))
for (label in names(env_datasets)) {
  x <- env_datasets[[label]]
  rows <- missingness[missingness$dataset == label, ]
  expected <- c(colSums(is.na(x[, environmental])), any_environmental_feature = missing_rows(x))
  assert(!anyDuplicated(rows$feature) && setequal(rows$feature, names(expected)) &&
           all(rows$n_events == nrow(x)), paste("Incomplete missingness summary:", label))
  same_numeric(rows$missing_n, expected[rows$feature], paste("Incorrect missingness counts:", label))
  same_numeric(rows$missing_percent, 100 * expected[rows$feature] / nrow(x),
               paste("Incorrect missingness percentages:", label))
}

inventory <- read_summary("dataset_inventory", c("dataset", "rows", "columns", "unit", "target",
  "number_of_classes", "predictor_count", "date_min", "date_max", "missing_rows", "purpose",
  "missingness_basis"))
inventory_objects <- list(frog_primary_multiclass = primary, frog_primary_predictors = primary_predictors,
  frog_multispecies_extension = multi, frog_multispecies_predictors = multi_predictors,
  species_metadata = species)
check_dataset_labels(inventory, names(inventory_objects), "dataset inventory", unique = TRUE)
for (label in names(inventory_objects)) {
  x <- inventory_objects[[label]]
  row <- inventory[inventory$dataset == label, ]
  assert(row$rows == nrow(x) && row$columns == ncol(x) &&
           !is.na(row$unit) && nzchar(row$unit) && !is.na(row$purpose) && nzchar(row$purpose) &&
           !is.na(row$missingness_basis) && nzchar(row$missingness_basis),
         paste("Inventory dimensions or descriptions disagree:", label))
  if (label == "species_metadata") {
    assert(row$missing_rows == sum(is.na(species$epbc_listed)),
           "Metadata missingness must quantify explicit unresolved conservation status")
  } else {
    event_source <- if (grepl("primary", label)) primary else multi
    assert(row$predictor_count == 30L && row$number_of_classes == 18L &&
             as.Date(row$date_min) == min(event_source$eventDate) &&
             as.Date(row$date_max) == max(event_source$eventDate) &&
             row$missing_rows == missing_rows(x), paste("Inventory event details disagree:", label))
  }
}
assert(inventory$target[inventory$dataset == "frog_primary_multiclass"] == "scientificName",
       "Primary inventory target is incorrect")

qc <- read_summary("qc_flow_summary", c("stage", "events_remaining", "events_excluded",
  "retained_percent_of_raw", "excluded_percent_of_raw", "excluded_percent_of_previous"))
source_qc <- read_csv("outputs/tables/qc_filter_flow.csv", show_col_types = FALSE)
source_qc <- source_qc[!is.na(source_qc$events_excluded), ]
assert(identical(qc$stage, source_qc$stage), "QC handoff stages differ from the validated sequential flow")
same_numeric(qc$events_remaining, source_qc$events_remaining, "QC remaining counts disagree")
same_numeric(qc$events_excluded, source_qc$events_excluded, "QC exclusions disagree")
same_numeric(qc$retained_percent_of_raw, 100 * qc$events_remaining / nrow(raw_events),
             "QC retained percentages disagree")
same_numeric(qc$excluded_percent_of_raw, 100 * qc$events_excluded / nrow(raw_events),
             "QC stage exclusion percentages disagree")
previous <- c(nrow(raw_events), head(qc$events_remaining, -1L))
same_numeric(qc$excluded_percent_of_previous, 100 * qc$events_excluded / previous,
             "QC previous-stage percentages disagree")
assert(tail(qc$events_remaining, 1L) == nrow(clean) &&
         sum(qc$events_excluded) == nrow(raw_events) - nrow(clean),
       "Sequential QC handoff does not reconcile raw and clean events")

structure <- read_summary("event_structure_summary", c("dataset", "n_events", "single_species_events",
  "multispecies_events", "max_species_per_event", "recall_at_k_eligible_events"))
distribution <- read_summary("species_per_event_distribution", c("dataset", "n_species", "events",
                                                                 "percent_events"))
raw_pairs <- unique(raw[c("eventID", "scientificName")])
species_counts <- list(raw = as.integer(table(raw_pairs$eventID)), clean = clean$n_species,
                       primary = rep(1L, nrow(primary)), multispecies = multi$n_species)
check_dataset_labels(structure, names(species_counts), "event structure", unique = TRUE)
check_dataset_labels(distribution, names(species_counts), "species per event")
for (label in names(species_counts)) {
  counts <- species_counts[[label]]
  row <- structure[structure$dataset == label, ]
  assert(row$n_events == length(counts) && row$single_species_events == sum(counts == 1L) &&
           row$multispecies_events == sum(counts >= 2L) && row$max_species_per_event == max(counts),
         paste("Event structure disagrees with original species sets:", label))
  rows <- distribution[distribution$dataset == label, ]
  expected <- table(counts)
  assert(!anyDuplicated(rows$n_species) && setequal(as.character(rows$n_species), names(expected)),
         paste("Species-per-event bins are incomplete:", label))
  same_numeric(rows$events, expected[as.character(rows$n_species)],
               paste("Species-per-event frequencies disagree:", label))
  same_numeric(rows$percent_events, 100 * rows$events / length(counts),
               paste("Species-per-event percentages disagree:", label))
}
assert(structure$recall_at_k_eligible_events[structure$dataset == "multispecies"] ==
         sum(multi$recall_at_k_eligible), "Recall@k summary count disagrees")

geography <- read_summary("geography_summary", c("dataset", "events", "unique_coordinates",
  "min_latitude_broad", "max_latitude_broad", "min_longitude_broad", "max_longitude_broad"))
check_dataset_labels(geography, c("clean", "primary", "multispecies"), "public geography", unique = TRUE)
for (label in geography$dataset) {
  x <- datasets[[label]]
  row <- geography[geography$dataset == label, ]
  assert(row$events == nrow(x) &&
           row$unique_coordinates == nrow(unique(x[c("decimalLatitude", "decimalLongitude")])),
         paste("Public geographic summary cardinality disagrees:", label))
  bounds <- c(min_latitude_broad = floor(min(x$decimalLatitude)),
              max_latitude_broad = ceiling(max(x$decimalLatitude)),
              min_longitude_broad = floor(min(x$decimalLongitude)),
              max_longitude_broad = ceiling(max(x$decimalLongitude)))
  for (field in names(bounds)) same_numeric(row[[field]], bounds[[field]],
    paste("Geographic extrema must be outward-rounded broad degrees:", label, field))
}

# Successful evidence fingerprints the tested objects, summaries and relevant
# code. The Markdown report/readiness table are intentionally excluded: the
# report consumes this evidence, so hashing it would create a circular check.
summary_names <- c("class_distribution", "date_range_summary", "events_by_year", "events_by_month",
  "state_distribution", "feature_summary", "dataset_inventory", "environmental_missingness",
  "qc_flow_summary", "event_structure_summary", "species_per_event_distribution", "geography_summary")
artifact_paths <- c(raw_frogid_path, "data/interim/frogid/clean_events.rds",
  "data/interim/environmental/event_environment.rds",
  file.path("data/processed", paste0(names(inventory_objects), ".rds")),
  file.path("outputs/tables", paste0(summary_names, ".csv")), "outputs/tables/qc_filter_flow.csv")
script_paths <- c("tests/validate_summary_data.R", "R/summary/summarise_for_eda.R",
                  "R/pipeline_helpers.R", "R/source_integrity.R", "config/source_checksums.csv")
dir.create(dirname(evidence_path), recursive = TRUE, showWarnings = FALSE)
saveRDS(list(test = "tests/validate_summary_data.R", passed = TRUE,
             passed_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             artifact_md5 = tools::md5sum(artifact_paths),
             script_md5 = tools::md5sum(script_paths)), evidence_path)
message("Summary validation passed: 18 classes; 30 unmodified numeric predictors; source-based dates, events, states, QC, missingness, inventory and broad public geography.")
