# Extract environmental context once per distinct clean coordinate, then map to
# eventID. This script never drops events, interpolates NA cells, or fits models.
source(file.path("R", "acquisition", "download_worldclim.R"))

worldclim_na_neighbourhood <- function(diagnostics, elevation) {
  # Inspect the eight neighbouring source cells solely to diagnose land-mask
  # boundaries. This never changes extracted event values or fills missing data.
  cells <- terra::cellFromXY(elevation,
                            as.matrix(diagnostics[, c("decimalLongitude", "decimalLatitude")]))
  diagnostics$valid_elevation_in_adjacent_cell <- rep(NA, nrow(diagnostics))
  valid_cells <- unique(cells[!is.na(cells)])
  if (length(valid_cells)) {
    neighbours <- terra::adjacent(elevation, cells = valid_cells,
                                  directions = 8, pairs = TRUE, include = FALSE)
    neighbour_cells <- unique(neighbours[, "to"])
    neighbour_values <- terra::extract(elevation, neighbour_cells)[, 1]
    has_data <- !is.na(neighbour_values[match(neighbours[, "to"], neighbour_cells)])
    nearby_data <- tapply(has_data, neighbours[, "from"], any)
    diagnostics$valid_elevation_in_adjacent_cell <-
      as.logical(nearby_data[match(as.character(cells), names(nearby_data))])
  }
  diagnostic_class <- ifelse(is.na(cells), "outside_extent",
    ifelse(diagnostics$valid_elevation_in_adjacent_cell,
           "NA_cell_adjacent_to_valid_source_cell",
           "NA_cell_without_valid_immediate_neighbour"))
  summary <- as.data.frame(table(diagnostic_class), stringsAsFactors = FALSE)
  names(summary) <- c("source_cell_context", "n_missing_events")
  summary$percent_missing_events <- 100 * summary$n_missing_events / nrow(diagnostics)
  utils::write.csv(summary,
                   file.path("outputs", "tables", "worldclim_na_neighbourhood.csv"),
                   row.names = FALSE)
  diagnostics
}

integrate_worldclim <- function() {
  input <- file.path("data", "interim", "frogid", "clean_events.rds")
  if (!file.exists(input)) stop("Run FrogID cohort construction first: ", input)
  events <- readRDS(input)
  required <- c("eventID", "decimalLatitude", "decimalLongitude", "month")
  stopifnot(all(required %in% names(events)), nrow(events) > 0L,
            !anyNA(events$eventID), !anyDuplicated(events$eventID),
            all(is.finite(events$decimalLongitude)),
            all(is.finite(events$decimalLatitude)),
            all(abs(events$decimalLongitude) <= 180),
            all(abs(events$decimalLatitude) <= 90),
            all(is.na(events$month) | events$month %in% seq_len(12L)))
  acquired <- acquire_worldclim()
  rasters <- acquired$rasters
  names(rasters$bio) <- paste0("BIO", seq_len(19L))
  names(rasters$elev) <- "elevation"
  names(rasters$tavg) <- paste0("tavg_month_", seq_len(12L))
  names(rasters$prec) <- paste0("prec_month_", seq_len(12L))
  raster_stack <- c(rasters$bio, rasters$elev, rasters$tavg, rasters$prec)
  stopifnot(terra::nlyr(raster_stack) == 44L)

  output_dir <- file.path("data", "interim", "environmental")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  coord_columns <- c("decimalLongitude", "decimalLatitude")
  all_coordinates <- as.data.frame(events[, coord_columns])
  coordinates <- unique(all_coordinates)
  rownames(coordinates) <- NULL
  coordinate_key <- function(x) paste(sprintf("%.17g", x$decimalLongitude),
                                     sprintf("%.17g", x$decimalLatitude), sep = "|")
  unique_key <- coordinate_key(coordinates)
  stopifnot(!anyDuplicated(unique_key))
  coordinate_index <- match(coordinate_key(all_coordinates), unique_key)
  stopifnot(!anyNA(coordinate_index),
            identical(all_coordinates$decimalLongitude,
                      coordinates$decimalLongitude[coordinate_index]),
            identical(all_coordinates$decimalLatitude,
                      coordinates$decimalLatitude[coordinate_index]))

  # A source/coordinate-validated cache prevents repeat extraction on reruns.
  cache_file <- file.path(output_dir, "coordinate_environment_cache.rds")
  raster_md5 <- stats::setNames(acquired$metadata$md5, acquired$metadata$variable)
  cache <- if (file.exists(cache_file)) readRDS(cache_file) else NULL
  cache_valid <- !is.null(cache) && identical(cache$coordinates, coordinates) &&
    identical(cache$raster_md5, raster_md5) &&
    identical(names(cache$values), names(raster_stack)) &&
    nrow(cache$values) == nrow(coordinates)
  if (cache_valid) {
    values <- cache$values
    message("Using verified coordinate extraction cache.")
  } else {
    message("Extracting 44 layers for ", nrow(coordinates),
            " unique coordinates representing ", nrow(events), " events.")
    # Matrix coordinates are longitude, latitude in the validated raster CRS.
    # method='simple' returns the containing grid cell, without interpolation.
    values <- terra::extract(raster_stack, as.matrix(coordinates), method = "simple")
    stopifnot(nrow(values) == nrow(coordinates),
              identical(names(values), names(raster_stack)))
    saveRDS(list(coordinates = coordinates, values = values,
                 raster_md5 = raster_md5,
                 extraction_method = "simple containing cell; no interpolation",
                 extracted_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
            cache_file)
  }
  bio_columns <- paste0("BIO", seq_len(19L))
  environment <- data.frame(eventID = as.character(events$eventID),
                            values[coordinate_index, c(bio_columns, "elevation")],
                            row.names = NULL, check.names = FALSE)
  monthly_value <- function(prefix) {
    out <- rep(NA_real_, nrow(events))
    valid <- which(!is.na(events$month))
    monthly_matrix <- as.matrix(values[, paste0(prefix, seq_len(12L))])
    out[valid] <- monthly_matrix[cbind(coordinate_index[valid], events$month[valid])]
    out
  }
  environment$climatological_tavg_event_month <- monthly_value("tavg_month_")
  environment$climatological_prec_event_month <- monthly_value("prec_month_")
  feature_names <- c(bio_columns, "elevation", "climatological_tavg_event_month",
                     "climatological_prec_event_month")
  stopifnot(nrow(environment) == nrow(events), !anyDuplicated(environment$eventID),
            identical(environment$eventID, as.character(events$eventID)),
            identical(names(environment), c("eventID", feature_names)),
            all(vapply(environment[, feature_names], function(x)
              all(is.na(x) | is.finite(x)), logical(1))))
  saveRDS(environment, file.path(output_dir, "event_environment.rds"))

  missing_matrix <- is.na(environment[, feature_names])
  missing_n <- colSums(missing_matrix)
  any_missing <- rowSums(missing_matrix) > 0L
  missingness <- data.frame(
    dataset = "all_clean_events",
    feature = c(feature_names, "any_environmental_feature"),
    n_events = nrow(events), missing_n = c(missing_n, sum(any_missing)),
    missing_percent = 100 * c(missing_n, sum(any_missing)) / nrow(events),
    row.names = NULL
  )
  utils::write.csv(missingness,
                   file.path("outputs", "tables", "environmental_missingness.csv"),
                   row.names = FALSE)

  # Investigate NA sources without exposing coordinates or IDs in public tables.
  coordinate_cells <- terra::cellFromXY(raster_stack, as.matrix(coordinates))
  outside <- is.na(coordinate_cells)[coordinate_index]
  source_na <- rowSums(is.na(values)) > 0L
  reason <- rep("complete_environment", nrow(events))
  reason[any_missing & !outside] <- "source_NA_inside_extent"
  reason[any_missing & !outside & !source_na[coordinate_index] &
           is.na(events$month)] <- "missing_event_month_only"
  reason[any_missing & outside] <- "outside_AUS_raster_extent"
  diagnostics <- as.data.frame(table(reason), stringsAsFactors = FALSE)
  names(diagnostics) <- c("reason", "n_events")
  diagnostics$percent_events <- 100 * diagnostics$n_events / nrow(events)
  utils::write.csv(diagnostics,
                   file.path("outputs", "tables", "environmental_na_diagnostics.csv"),
                   row.names = FALSE)
  missing_variables <- vapply(which(any_missing), function(i)
    paste(feature_names[missing_matrix[i, ]], collapse = ";"), character(1))
  private_diagnostics <- data.frame(
    eventID = events$eventID[any_missing], all_coordinates[any_missing, ],
    month = events$month[any_missing], reason = reason[any_missing],
    missing_variables = missing_variables, row.names = NULL
  )
  private_diagnostics <- worldclim_na_neighbourhood(private_diagnostics, rasters$elev)
  saveRDS(private_diagnostics,
          file.path(output_dir, "event_environment_na_diagnostics.rds"))
  source_missingness <- data.frame(
    source_layer = names(values), n_unique_coordinates = nrow(values),
    missing_coordinates = colSums(is.na(values)), row.names = NULL
  )
  utils::write.csv(source_missingness,
                   file.path("outputs", "tables", "worldclim_source_missingness.csv"),
                   row.names = FALSE)
  validation <- list(
    input_md5 = unname(tools::md5sum(input)), raster_md5 = raster_md5,
    n_clean_events = nrow(events), n_unique_coordinates = nrow(coordinates),
    n_extraction_rows = nrow(values), n_event_environment_rows = nrow(environment),
    extraction_cache_used = cache_valid, feature_names = feature_names,
    eventID = environment$eventID, coordinate_index = coordinate_index,
    any_missing_events = sum(any_missing),
    validation_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
  saveRDS(validation, file.path(output_dir, "integration_validation.rds"))
  summary <- data.frame(
    measure = c("clean_events", "unique_coordinates", "coordinate_extraction_rows",
                "event_environment_rows", "environmental_features", "events_any_NA"),
    value = c(nrow(events), nrow(coordinates), nrow(values), nrow(environment),
              length(feature_names), sum(any_missing))
  )
  utils::write.csv(summary,
                   file.path("outputs", "tables", "worldclim_extraction_summary.csv"),
                   row.names = FALSE)
  message(sprintf("WorldClim integration: %s events, %s unique coordinates; %s events (%.4f%%) with >=1 NA. No events dropped.",
                  nrow(events), nrow(coordinates), sum(any_missing),
                  100 * mean(any_missing)))
  invisible(environment)
}

if (sys.nframe() == 0L) integrate_worldclim()
