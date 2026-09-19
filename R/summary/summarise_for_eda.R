# Deterministic, non-sensitive handoff descriptives only. No imputation, scaling,
# balancing, feature removal, EDA plots, or statistical/model fitting.
source("R/pipeline_helpers.R")

summarise_for_eda <- function() {
  raw <- read_frogid()
  clean <- readRDS("data/interim/frogid/clean_events.rds")
  primary <- readRDS("data/processed/frog_primary_multiclass.rds")
  multi <- readRDS("data/processed/frog_multispecies_extension.rds")
  primary_predictors <- readRDS("data/processed/frog_primary_predictors.rds")
  multi_predictors <- readRDS("data/processed/frog_multispecies_predictors.rds")
  species <- readRDS("data/processed/species_metadata.rds")
  environment <- readRDS("data/interim/environmental/event_environment.rds")
  environmental_validation <- readRDS("data/interim/environmental/integration_validation.rds")
  coordinate_cache <- readRDS("data/interim/environmental/coordinate_environment_cache.rds")
  manifest <- readRDS("data/interim/frogid/cohort_manifest.rds")
  wc_manifest <- readRDS("data/raw/worldclim/acquisition_manifest.rds")
  epbc_manifest <- read_csv("data/raw/epbc/source_manifest.csv",
                            col_types = cols(.default = col_character()))
  official_epbc <- read_csv(file.path("data/raw/epbc", epbc_manifest$local_filename),
                            col_types = cols(.default = col_character()), na = c("", "-"))
  pins <- read_csv("config/source_checksums.csv", col_types = cols(.default = col_character()))
  invisible(lapply(pins$file, verify_source))
  cohort <- read_csv("outputs/tables/species_cohort.csv", show_col_types = FALSE)
  flow <- read_csv("outputs/tables/qc_filter_flow.csv", show_col_types = FALSE)
  missingness <- read_csv("outputs/tables/environmental_missingness.csv", show_col_types = FALSE)
  conservation_species <- read_csv("outputs/tables/conservation_species_retention.csv", show_col_types = FALSE)
  conservation_category <- read_csv("outputs/tables/conservation_category_retention.csv", show_col_types = FALSE)
  conservation_groups <- read_csv("outputs/tables/conservation_group_retention.csv", show_col_types = FALSE)
  exclusions <- read_csv("outputs/tables/conservation_qc_exclusion_summary.csv", show_col_types = FALSE)
  features <- attr(primary, "predictor_columns")
  environmental_features <- c(paste0("BIO", 1:19), "elevation",
                              "climatological_tavg_event_month", "climatological_prec_event_month")
  geographic_features <- c("decimalLatitude", "decimalLongitude")
  temporal_features <- c("month", "day_of_year", "month_sin", "month_cos",
                         "day_of_year_sin", "day_of_year_cos")
  stopifnot(length(features) == 30L,
            identical(features, c(geographic_features, temporal_features, environmental_features)),
            identical(names(primary_predictors), features),
            identical(names(multi_predictors), features),
            !anyDuplicated(clean$eventID), !anyDuplicated(primary$eventID),
            !anyDuplicated(multi$eventID), nrow(coordinate_cache$values) ==
              environmental_validation$n_unique_coordinates)

  raw_pairs <- raw |> distinct(eventID, scientificName)
  raw_structure <- raw_pairs |> count(eventID, name = "n_species")
  # State labels are joined only after validating one supplied value per event.
  state_pairs <- raw |> distinct(eventID, stateProvince)
  stopifnot(!anyDuplicated(state_pairs$eventID))
  raw_events <- raw |>
    distinct(eventID, .keep_all = TRUE) |>
    select(eventID, eventDate, decimalLatitude, decimalLongitude, stateProvince) |>
    left_join(raw_structure, by = "eventID", relationship = "one-to-one")
  raw_events$eventDate <- as.Date(raw_events$eventDate, format = "%Y-%m-%d")
  datasets <- list(raw = raw_events, clean = clean, primary = primary, multispecies = multi)
  class_distribution <- primary |>
    count(scientificName, name = "event_count") |>
    arrange(desc(event_count), scientificName) |>
    mutate(percent_primary = 100 * event_count / nrow(primary),
           cumulative_percent_primary = cumsum(percent_primary), rank = row_number())
  selected <- cohort[cohort$selected, ]
  selected_index <- match(class_distribution$scientificName, selected$scientificName)
  stopifnot(nrow(class_distribution) == 18L, !anyNA(selected_index),
            identical(class_distribution$scientificName, manifest$vocabulary),
            all(class_distribution$event_count == selected$clean_single_species_events[selected_index]),
            sum(class_distribution$event_count) == nrow(primary))
  date_range_summary <- bind_rows(lapply(names(datasets), function(label) {
    dates <- datasets[[label]]$eventDate
    tibble(dataset = label, n_events = length(dates),
           date_min = as.character(min(dates, na.rm = TRUE)),
           date_max = as.character(max(dates, na.rm = TRUE)),
           calendar_years = n_distinct(format(dates[!is.na(dates)], "%Y")),
           missing_dates = sum(is.na(dates)))
  }))
  events_by_year <- bind_rows(lapply(names(datasets), function(label) {
    tibble(year = as.integer(format(datasets[[label]]$eventDate, "%Y"))) |>
      count(year, name = "events") |>
      mutate(dataset = label, .before = 1)
  }))
  events_by_month <- bind_rows(lapply(names(datasets), function(label) {
    months <- as.integer(format(datasets[[label]]$eventDate, "%m"))
    tibble(dataset = label, month = 1:12, events = tabulate(months, nbins = 12L))
  }))
  for (label in names(datasets)) {
    stopifnot(sum(events_by_year$events[events_by_year$dataset == label]) == nrow(datasets[[label]]),
              sum(events_by_month$events[events_by_month$dataset == label]) == nrow(datasets[[label]]))
  }
  state_distribution <- raw |>
    mutate(stateProvince = coalesce(stateProvince, "(missing)")) |>
    group_by(stateProvince) |>
    summarise(raw_occurrence_rows = n(), raw_events = n_distinct(eventID),
              clean_public_events = n_distinct(eventID[eventID %in% clean$eventID]), .groups = "drop") |>
    arrange(desc(clean_public_events), stateProvince)
  stopifnot(sum(state_distribution$raw_occurrence_rows) == nrow(raw),
            sum(state_distribution$raw_events) == nrow(raw_events),
            sum(state_distribution$clean_public_events) == nrow(clean))
  public_datasets <- list(clean = clean, primary = primary, multispecies = multi)
  geography_summary <- bind_rows(lapply(names(public_datasets), function(label) {
    x <- public_datasets[[label]]
    tibble(dataset = label, events = nrow(x),
           unique_coordinates = nrow(unique(x[c("decimalLatitude", "decimalLongitude")])),
           min_latitude_broad = floor(min(x$decimalLatitude)),
           max_latitude_broad = ceiling(max(x$decimalLatitude)),
           min_longitude_broad = floor(min(x$decimalLongitude)),
           max_longitude_broad = ceiling(max(x$decimalLongitude)))
  }))
  event_species <- list(raw = raw_events$n_species, clean = clean$n_species,
                       primary = rep(1L, nrow(primary)), multispecies = multi$n_species)
  event_structure_summary <- bind_rows(lapply(names(event_species), function(label) {
    n <- event_species[[label]]
    tibble(dataset = label, n_events = length(n), single_species_events = sum(n == 1L),
           multispecies_events = sum(n >= 2L), max_species_per_event = max(n),
           recall_at_k_eligible_events = if (label == "multispecies") {
             sum(multi$recall_at_k_eligible)
           } else NA_integer_)
  }))
  species_per_event_distribution <- bind_rows(lapply(names(event_species), function(label) {
    tibble(n_species = event_species[[label]]) |>
      count(n_species, name = "events") |>
      mutate(dataset = label, percent_events = 100 * events / sum(events), .before = 1)
  })) |>
    select(dataset, n_species, events, percent_events)
  qc_flow_summary <- flow |>
    filter(!is.na(events_excluded)) |>
    mutate(retained_percent_of_raw = 100 * events_remaining / nrow(raw_events),
           excluded_percent_of_raw = 100 * events_excluded / nrow(raw_events),
           excluded_percent_of_previous = if_else(stage == "raw_events", 0,
             100 * events_excluded / lag(events_remaining)))
  stopifnot(tail(qc_flow_summary$events_remaining, 1L) == nrow(clean),
            sum(qc_flow_summary$events_excluded) + nrow(clean) == nrow(raw_events))
  feature_summary <- bind_rows(lapply(features, function(feature) {
    values <- primary_predictors[[feature]]
    usable <- values[!is.na(values)]
    stopifnot(is.numeric(values), all(is.finite(usable)))
    q <- if (length(usable)) quantile(usable, probs = c(0, .25, .5, .75, 1), names = FALSE) else rep(NA_real_, 5)
    group <- if (feature %in% geographic_features) "geographic" else if (feature %in% temporal_features) {
      "temporal"
    } else "environmental"
    tibble(feature = feature, feature_group = group, n = length(values),
           missing_n = sum(is.na(values)), missing_percent = 100 * mean(is.na(values)),
           mean = if (length(usable)) mean(usable) else NA_real_,
           sd = if (length(usable) > 1L) sd(usable) else NA_real_,
           min = q[1], p25 = q[2], median = q[3], p75 = q[4], max = q[5])
  }))
  env_missing <- function(x) sum(!complete.cases(x[environmental_features]))
  for (label in c("all_clean_events", "frog_primary_multiclass", "frog_multispecies_extension")) {
    x <- switch(label, all_clean_events = environment, frog_primary_multiclass = primary,
                frog_multispecies_extension = multi)
    report <- missingness[missingness$dataset == label & missingness$feature == "any_environmental_feature", ]
    stopifnot(nrow(report) == 1L, report$missing_n == env_missing(x), report$n_events == nrow(x))
  }
  inventory_row <- function(label, x, dates, unit, target, classes, predictor_count,
                            missing_rows, purpose, missingness_basis) {
    tibble(dataset = label, rows = nrow(x), columns = ncol(x), unit = unit, target = target,
           number_of_classes = classes, predictor_count = predictor_count,
           date_min = if (is.null(dates)) NA_character_ else as.character(min(dates)),
           date_max = if (is.null(dates)) NA_character_ else as.character(max(dates)),
           missing_rows = missing_rows, purpose = purpose, missingness_basis = missingness_basis)
  }
  dataset_inventory <- bind_rows(
    inventory_row("frog_primary_multiclass", primary, primary$eventDate,
      "one clean single-species recording event", "scientificName", 18L, 30L,
      env_missing(primary), "primary 18-class classification",
      "at_least_one_environmental_feature_missing"),
    inventory_row("frog_primary_predictors", primary_predictors, primary$eventDate,
      "primary recording; row-aligned predictors", NA_character_, 18L, 30L,
      env_missing(primary_predictors), "predictors only; target in aligned primary dataset",
      "at_least_one_environmental_feature_missing"),
    inventory_row("frog_multispecies_extension", multi, multi$eventDate,
      "clean recording with >=2 original species and >=1 selected species", "species_list", 18L, 30L,
      env_missing(multi), "future Top-k / Recall@k evaluation",
      "at_least_one_environmental_feature_missing"),
    inventory_row("frog_multispecies_predictors", multi_predictors, multi$eventDate,
      "extension recording; row-aligned predictors", NA_character_, 18L, 30L,
      env_missing(multi_predictors), "predictors only; targets in aligned extension dataset",
      "at_least_one_environmental_feature_missing"),
    inventory_row("species_metadata", species, NULL, "one supplied raw scientific name",
      NA_character_, NA_integer_, 0L, sum(is.na(species$epbc_listed)),
      "taxonomy/cohort/conservation lookup; 216 names, 18 selected",
      "unresolved_or_not_confirmed_EPBC_listing"))
  epbc_source_category_counts <- bind_rows(
    official_epbc |> count(epbc_category = .data[["Threatened status"]], name = "taxa") |>
      mutate(source_scope = "all_source_taxa", .before = 1),
    official_epbc |> filter(Class == "Amphibia") |>
      count(epbc_category = .data[["Threatened status"]], name = "taxa") |>
      mutate(source_scope = "amphibian_taxa", .before = 1))
  event_time_summary <- raw |>
    mutate(format_pattern = gsub("[0-9]", "D", eventTime),
           suffix = sub("^[0-9]{2}:[0-9]{2}:[0-9]{2}", "", eventTime)) |>
    group_by(format_pattern, suffix) |>
    summarise(occurrence_rows = n(), events = n_distinct(eventID), .groups = "drop")
  tables <- list(class_distribution = class_distribution, date_range_summary = date_range_summary,
                 events_by_year = events_by_year, events_by_month = events_by_month,
                 state_distribution = state_distribution, geography_summary = geography_summary,
                 event_structure_summary = event_structure_summary,
                 species_per_event_distribution = species_per_event_distribution,
                 qc_flow_summary = qc_flow_summary, feature_summary = feature_summary,
                 dataset_inventory = dataset_inventory,
                 epbc_source_category_counts = epbc_source_category_counts,
                 event_time_summary = event_time_summary)
  dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)

  for (name in names(tables)) {
    write_csv(
      tables[[name]],
      file.path("outputs", "tables", paste0(name, ".csv")),
      na = "NA"
    )
  }

  # Independently validate the freshly generated aggregate tables before the
  # readiness gate consumes their validation evidence.
  source(
    "tests/validate_summary_data.R",
    local = new.env(parent = globalenv())
  )

  # Small Markdown writer: no reporting package is needed or added to renv.
  fmt <- function(x, digits = 4L) {
    if (inherits(x, "Date")) return(as.character(x))
    if (is.numeric(x)) return(vapply(x, function(value) {
      if (is.na(value)) "NA" else format(round(value, digits), big.mark = ",",
                                        scientific = FALSE, trim = TRUE)
    }, character(1)))
    ifelse(is.na(x), "NA", as.character(x))
  }
  md_table <- function(x) {
    if (!nrow(x)) return("No rows.")
    cells <- lapply(x, function(col) gsub("[|]", " / ", gsub("[\r\n]+", " ", fmt(col))))
    lines <- vapply(seq_len(nrow(x)), function(i) {
      paste0("| ", paste(vapply(cells, `[`, character(1), i), collapse = " | "), " |")
    }, character(1))
    c(paste0("| ", paste(names(x), collapse = " | "), " |"),
      paste0("| ", paste(rep("---", ncol(x)), collapse = " | "), " |"), lines)
  }
  report <- character()
  add <- function(...) report <<- c(report, unlist(list(...), use.names = FALSE), "")
  processed_evidence <- readRDS("data/interim/validation/processed_validation.rds")
  f <- function(x) fmt(x)[1]
  listed_species <- conservation_species[conservation_species$epbc_listed %in% TRUE, ]
  listed_union <- conservation_groups[conservation_groups$scope == "confirmed_EPBC_listed", ]
  listed_qc <- exclusions[exclusions$scope == "confirmed_EPBC_listed" &
                           exclusions$count_type == "non_exclusive", ]
  primary_missing <- env_missing(primary)
  multi_missing <- env_missing(multi)
  clean_missing <- env_missing(environment)
  add("# FrogID STAT5003 data summary",
      "This reproducible handoff certifies data preparation and supplies the requested descriptive aggregates for future EDA. No EDA plots, statistical models, machine-learning models, imputation, scaling, class balancing, or correlated-feature removal have been performed.",
      paste0("Processed validation timestamp (UTC): **", processed_evidence$passed_utc, "**. ",
             "Readiness checks at the end are evaluated against the current files and Git state."),
      'Research framing: "To what extent can environmental, seasonal and geographic context rank Australian frog species detected in FrogID recordings, and how do public geoprivacy protections constrain the applicability of such models to threatened species?"')
  add("## SOURCE / PROVENANCE", "### FrogID",
      "Release: Australian Museum FrogID Dataset 6; supplied datasetName values: ",
      paste0("`", paste(sort(unique(raw$datasetName)), collapse = "`, `"), "`."),
      paste0("Source: [FrogID Dataset 6 CSV](", pins$source_url[pins$source == "frogid_dataset6"], ")."),
      paste0("Raw rows **", f(nrow(raw)), "**; columns **", f(ncol(raw)), "**; unique events **", f(nrow(raw_events)),
             "**; unique occurrence IDs **", f(n_distinct(raw$occurrenceID)), "**; supplied scientific names **",
             f(n_distinct(raw$scientificName)), "**. No duplicate occurrence IDs, exact duplicate rows, or event metadata conflicts were found by validation."),
      paste0("Raw dates: **", min(raw_events$eventDate), " to ", max(raw_events$eventDate), "**. ",
             "Broad coordinate bounds (rounded outward to whole degrees): latitude ", floor(min(raw$decimalLatitude)),
             " to ", ceiling(max(raw$decimalLatitude)), "; longitude ", floor(min(raw$decimalLongitude)),
             " to ", ceiling(max(raw$decimalLongitude)), ". These are bounding limits, not published point locations."),
      "Published release descriptions state 226 species, while the supplied CSV contains 216 distinct scientificName strings. The exact ten-name discrepancy remains unresolved; public suppression/taxonomy documentation does not prove a complete reconciliation. The analysis uses observed names and invents no records. See [source investigation](frogid-source-investigation.md). No ALA occurrence data were added.",
      "Supplied stateProvince values/counts (raw event counts use distinct recordings):", md_table(state_distribution),
      "Supplied eventTime formats:", md_table(event_time_summary))
  add("### WorldClim",
      "WorldClim **2.1**, **Australia (AUS)**, **30 arc-second** (1/120 degree), reference period **1970-2000**. CRS: **WGS84 / EPSG:4326**. Raster extent: longitude **112.5 to 159.5**, latitude **-55.5 to -9**; each raster grid has **5,580 rows x 5,640 columns**.",
      "Variables: BIO1-BIO19 (19 layers), elevation (1), monthly mean temperature/tavg (12), and monthly precipitation/prec (12): **44 source layers**. Final event features use all 19 BIO variables, elevation, and the tavg/prec layer for the supplied event month: **22 environmental features**.",
      md_table(wc_manifest |> select(variable, worldclim_version, reference_period, country,
                                    resolution_arcseconds, n_layers, retrieval_utc)),
      paste0("Extraction used one row per unique clean coordinate: **", f(nrow(coordinate_cache$coordinates)),
             " coordinates**, mapped to **", f(nrow(environment)), " events**. Cache verification compares exact coordinates, ",
             "layer structure and source checksums. Latest integration reused the validated cache: **",
             ifelse(isTRUE(environmental_validation$extraction_cache_used), "yes", "no (cache was created)"), "**."),
      "WorldClim provides climatology, not weather observed on the recording date. Source temperature values retain WorldClim 2.1 published units; no legacy temperature rescaling or raster interpolation is applied. [Source details and units](worldclim-source.md).")
  add("### EPBC",
      paste0("Agency: **", epbc_manifest$publisher, "**. Source: DCCEEW Species Profile and Threats Database (SPRAT), ",
             "[official Threatened Species State Lists CSV](", epbc_manifest$source_url, ")."),
      paste0("Retrieved (UTC): **", epbc_manifest$retrieved_at_utc, "**; source extraction: **", epbc_manifest$source_extracted_date,
             "**. Source rows: **", f(nrow(official_epbc)), "**; amphibian rows: **",
             f(sum(official_epbc$Class == "Amphibia", na.rm = TRUE)), "**."),
      "Official source category counts (whole source and amphibian subset are separate scopes):", md_table(epbc_source_category_counts),
      paste0("FrogID exact listed-name matches: **", sum(species$epbc_match_status == "exact_listed_name"),
             "**; normalized listed-name matches: **", sum(species$epbc_match_status == "normalized_listed_name"),
             "**; official current-name matches: **", sum(grepl("official_current_name", species$epbc_match_status)),
             "**; names not confirmed listed or unresolved: **", sum(is.na(species$epbc_listed)), "**."),
      "The source is a threatened-species list, not a complete checklist. A non-match remains epbc_listed=NA, with its explicit match status; it is never relabelled non-threatened. Current source status is context, not reconstructed status at the 2017-2023 recording dates. [EPBC provenance and matching rules](epbc-source.md).",
      "### Frozen source checksums", md_table(pins |> select(source, file, md5)),
      "All six files are verified against the committed config/source_checksums.csv before this report is generated. WorldClim source URLs/geometry and EPBC provenance are retained in the acquisition metadata tables.")
  add("## QC FLOW",
      "An event is rejected if any original occurrence row fails a condition. The following stages are sequential; excluded events sum to the total loss. Percent retained/excluded of raw uses the original event count; the final column uses the immediately preceding stage.",
      md_table(qc_flow_summary),
      paste0("Final clean events: **", f(nrow(clean)), "**; excluded: **", f(nrow(raw_events) - nrow(clean)),
             "**; retained: **", f(100 * nrow(clean) / nrow(raw_events)), "%**."),
      "Independent QC reason counts below are **non-exclusive**. Negative and zero uncertainty are subsets of nonpositive uncertainty. Privacy/generalisation can overlap excessive uncertainty, so these rows must not be summed. The precision filter occurs before privacy in the sequential flow; zero later exclusions do not imply no privacy effect.",
      md_table(exclusions |> filter(scope == "all_events", count_type == "non_exclusive") |>
                 select(reason, occurrence_rows, events, percent_events)))
  add("## EVENT STRUCTURE", md_table(event_structure_summary),
      "Primary recordings contain exactly one original species, selected by the frozen vocabulary. The extension retains complete original species lists and their selected-species intersections. Full-target Recall@k eligibility requires every original species to belong to the vocabulary.",
      "Species-per-event distribution (original labels; no truncation):", md_table(species_per_event_distribution))
  add("## SPECIES / CLASS SUMMARY",
      paste0("Raw supplied scientific names: **", n_distinct(raw$scientificName), "**; clean scientific names: **",
             length(unique(unlist(clean$species_list, use.names = FALSE))), "**; selected model classes: **",
             nrow(class_distribution), "**. Objective threshold: **>=", f(unique(cohort$threshold_used)),
             " clean single-species events**; selection was frozen before EPBC integration."),
      md_table(class_distribution),
      paste0("Largest class **", f(max(class_distribution$event_count)), "**; smallest **", f(min(class_distribution$event_count)),
             "**; median **", f(median(class_distribution$event_count)), "**; max/min imbalance ratio **",
             f(max(class_distribution$event_count) / min(class_distribution$event_count)), "**."),
      paste0("Largest-class share: **", f(class_distribution$percent_primary[1]), "%**; cumulative top 3: **",
             f(sum(head(class_distribution$percent_primary, 3))), "%**; cumulative top 5: **",
             f(sum(head(class_distribution$percent_primary, 5))), "%**. No balancing has been performed."))
  add("## DATE / TIME SUMMARY", md_table(date_range_summary),
      "Counts refer to distinct recording events. Calendar year and month use the supplied eventDate.",
      "Events by year:", md_table(events_by_year), "Events by month:", md_table(events_by_month),
      "eventTime mixes UTC clocks and explicit UTC offsets. UTC clock fields are not uniformly local time, and the pipeline does not reconstruct a common local timezone/date. local_hour is therefore omitted. The six temporal predictors use only the supplied date and correctly account for leap years in annual phase.")
  add("## GEOGRAPHIC SUMMARY",
      "Clean/public recordings only. Bounds are rounded outward to whole degrees; no event IDs, observer IDs, exact sensitive locations, or point-coordinate pairs are published.",
      md_table(geography_summary),
      "Clean/public stateProvince event counts:", md_table(state_distribution |> select(stateProvince, clean_public_events)),
      "Coordinates were supplied consistently within each event; stateProvince mapping is checked for one value per event before aggregate counting.")
  add("## FEATURE SUMMARY",
      paste0("Geographic (2): `", paste(geographic_features, collapse = "`, `"), "`. Latitude/longitude retain their original decimalLatitude/decimalLongitude field names."),
      paste0("Temporal (6): `", paste(temporal_features, collapse = "`, `"), "`."),
      paste0("Environmental (22): `", paste(environmental_features, collapse = "`, `"), "`."),
      "The positive predictor whitelist contains exactly 30 numeric columns. It excludes target labels, IDs, observer identity, QC/privacy flags, eventDate, conservation fields, and target-derived counts. Conservation status is evaluation/context metadata and never a predictor.",
      "PRIMARY numeric summaries: n is the total primary row count; mean/SD/quantiles use available values. Standard deviation is sample SD and quartiles use R's default type-7 quantile. Geographic statistics describe clean/public positions only and do not publish point pairs.",
      md_table(feature_summary),
      "No missing values have been imputed, no features scaled, and no correlated features removed. Those are later EDA/modelling decisions.")
  add("## MISSINGNESS SUMMARY",
      paste0("Primary environmental NA events: **", f(primary_missing), " / ", f(nrow(primary)), " (",
             f(100 * primary_missing / nrow(primary)), "%)**; extension: **", f(multi_missing), " / ", f(nrow(multi)), " (",
             f(100 * multi_missing / nrow(multi)), "%)**; all clean: **", f(clean_missing), " / ", f(nrow(clean)), " (",
             f(100 * clean_missing / nrow(clean)), "%)**."),
      "**No NA rows were silently dropped.** Every cohort event remains in its integrated dataset and predictor companion. Per-feature environmental missingness is reported below; geographic/temporal missingness is in the feature summary.",
      md_table(missingness),
      "Source-cell diagnostics remain in environmental_na_diagnostics.csv and worldclim_na_neighbourhood.csv. An inside-extent NA or nearby valid cell does not authorize moving a point or filling an NA. Final preprocessing decisions remain for EDA and training/evaluation design.")
  add("## CONSERVATION SUMMARY",
      "Confirmed EPBC-listed FrogID taxa by their exact official category, plus explicitly unresolved/not-confirmed names:",
      md_table(conservation_category |> select(-event_counting)),
      "Category event counts are distinct unions within category and can overlap across categories. Conservation group totals below also use event unions, never sums of species-event totals. Occurrence counts here refer to focal taxon rows.",
      md_table(conservation_groups |> select(-event_counting)),
      paste0("Confirmed listed species: **", nrow(listed_species), "**; listed species surviving QC: **",
             sum(listed_species$clean_events > 0), "**; listed species selected for modelling: **",
             sum(listed_species$selected_for_model), "**; unresolved/not-confirmed names: **",
             sum(is.na(species$epbc_listed)), "**."),
      paste0("Listed taxa contribute **", f(listed_union$raw_occurrence_rows), " raw records across ", f(listed_union$raw_events),
             " distinct recordings**, including **", f(listed_union$raw_single_species_events),
             " single-species recordings**. After whole-event QC these become **", f(listed_union$clean_occurrence_rows),
             " records / ", f(listed_union$clean_events), " events / ", f(listed_union$clean_single_species_events), " singles**."),
      "Non-exclusive reasons for recordings containing a confirmed listed taxon (row counts include all co-detected source records in those recordings):",
      md_table(listed_qc |> select(reason, occurrence_rows, events, percent_events)),
      "The aggregate preparation data support later EDA quantifying public geoprivacy/QC retention and exclusion of confirmed listed taxa. The current 18-class vocabulary contains no confirmed listed species, so it cannot support a threatened-class predictive subgroup evaluation. This is not evidence that unmatched selected species are non-threatened. Subspecies-only matches remain unresolved and are documented in epbc_unmatched_species.csv; objective class selection is unchanged.")
  add("## FINAL DATASET INVENTORY", md_table(dataset_inventory),
      "For the four event/predictor datasets, missing_rows counts events missing at least one environmental predictor. For species_metadata, it counts unresolved/not-confirmed EPBC listing rows. Predictor companions contain no target column and align row-for-row with their corresponding labelled dataset. number_of_classes=18 refers to the selected model vocabulary; the extension's complete original labels may also contain unselected taxa.",
      "PRIMARY TARGET: **scientificName**",
      "PRIMARY UNIT: **one clean single-species FrogID recording event**",
      "PRIMARY CLASSES: **18**",
      "PRIMARY PREDICTORS: **30**",
      "MULTISPECIES UNIT: **one clean recording with >=2 original detected species and >=1 selected species**",
      "MULTISPECIES PURPOSE: **future Top-k / Recall@k evaluation**",
      paste0("The extension contains **", length(unique(unlist(multi$species_list, use.names = FALSE))),
             " distinct original species labels**; **", f(sum(multi$recall_at_k_eligible)),
             " recordings** have all original targets in the 18-class vocabulary."),
      "Prepared RDS files:",
      paste0("- `data/processed/", dataset_inventory$dataset, ".rds`"),
      "Key public handoff tables:", paste0("- `outputs/tables/", names(tables), ".csv`"),
      "- `outputs/tables/environmental_missingness.csv`",
      "- `outputs/tables/conservation_species_retention.csv`",
      "- `outputs/tables/conservation_category_retention.csv`",
      "- `outputs/tables/conservation_group_retention.csv`",
      "- `outputs/tables/conservation_qc_exclusion_summary.csv`",
      "Reproduction instructions and validation evidence: [data pipeline](data-pipeline.md).")

  # Keep this checklist last in both the saved Markdown and console output.
  source("R/summary/check_readiness.R")
  readiness <- check_readiness()
  stopifnot(all(c("check", "status", "detail") %in% names(readiness)),
            all(readiness$status %in% c("PASS", "FAIL")))
  write_csv(readiness, "outputs/tables/eda_readiness.csv", na = "NA")
  add("## EDA READINESS CHECK",
      "PASS is recorded only for checks actually verified against the current inputs, validation evidence, renv environment, and Git state. A later edit requires regenerating this checklist.",
      paste0("[", readiness$status, "] ", readiness$check, " - ", readiness$detail))
  dir.create("docs", recursive = TRUE, showWarnings = FALSE)
  writeLines(report, "docs/data-summary.md", useBytes = TRUE)
  cat(paste(report, collapse = "\n"), "\n", sep = "")
  invisible(list(tables = tables, readiness = readiness, report = report))
}

if (sys.nframe() == 0L) summarise_for_eda()
