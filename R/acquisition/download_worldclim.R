# Country-specific WorldClim 2.1, exactly 30 arc-seconds. Run from repo root.
# Sourceable: the integration script reuses acquisition and validation functions.

worldclim_specification <- function() {
  data.frame(variable = c("bio", "elev", "tavg", "prec"),
             expected_layers = c(19L, 1L, 12L, 12L), stringsAsFactors = FALSE)
}

worldclim_filename <- function(variable) {
  file.path("data", "raw", "worldclim", "climate", "wc2.1_country",
            paste0("AUS_wc2.1_30s_", variable, ".tif"))
}

validate_worldclim_raster <- function(r, variable, expected_layers) {
  stopifnot(inherits(r, "SpatRaster"), terra::nlyr(r) == expected_layers,
            all(abs(terra::res(r) - 1 / 120) < 1e-10),
            terra::is.lonlat(r), terra::same.crs(r, "EPSG:4326"))
  if (variable != "elev") {
    layer_number <- suppressWarnings(as.integer(sub(".*_", "", names(r))))
    if (!identical(layer_number, seq_len(expected_layers))) {
      stop("Unexpected WorldClim layer order for ", variable, ": ",
           paste(names(r), collapse = "; "))
    }
  }
  invisible(TRUE)
}

acquire_worldclim <- function() {
  # Windows GIS applications can set incompatible machine-wide PROJ/GDAL paths.
  # Prefer terra's bundled databases for this R process only, when provided.
  if (.Platform$OS.type == "windows") {
    proj_directory <- system.file("proj", package = "terra")
    gdal_directory <- system.file("gdal", package = "terra")
    if (nzchar(proj_directory) && file.exists(file.path(proj_directory, "proj.db"))) {
      Sys.setenv(PROJ_LIB = proj_directory, PROJ_DATA = proj_directory)
    }
    if (nzchar(gdal_directory)) Sys.setenv(GDAL_DATA = gdal_directory)
  }
  stopifnot(requireNamespace("terra", quietly = TRUE),
            requireNamespace("geodata", quietly = TRUE))
  options(timeout = max(3600, getOption("timeout", 60)))
  raw_dir <- file.path("data", "raw", "worldclim")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path("outputs", "tables"), recursive = TRUE, showWarnings = FALSE)
  manifest_path <- file.path(raw_dir, "acquisition_manifest.rds")
  previous <- if (file.exists(manifest_path)) readRDS(manifest_path) else NULL
  spec <- worldclim_specification()
  metadata <- vector("list", nrow(spec))
  rasters <- vector("list", nrow(spec))
  names(rasters) <- spec$variable
  for (i in seq_len(nrow(spec))) {
    variable <- spec$variable[i]
    filename <- worldclim_filename(variable)
    already_present <- file.exists(filename)
    message("Loading/acquiring WorldClim AUS 2.1 30s: ", variable)
    r <- geodata::worldclim_country(
      country = "AUS", var = variable, path = raw_dir, version = "2.1",
      method = "libcurl", quiet = FALSE
    )
    if (is.null(r) || !file.exists(filename)) {
      stop("WorldClim acquisition failed for ", variable,
           ". No alternative resolution will be substituted.")
    }
    validate_worldclim_raster(r, variable, spec$expected_layers[i])
    raster_extent <- as.vector(terra::ext(r))
    checksum <- unname(tools::md5sum(filename))
    old <- if (!is.null(previous)) previous[previous$variable == variable, ] else NULL
    retrieval_utc <- if (!is.null(old) && nrow(old) == 1L &&
                         identical(old$md5, checksum)) old$retrieval_utc else
      format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    metadata[[i]] <- data.frame(
      variable = variable,
      source_url = paste0("https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/",
                          basename(filename)),
      package_call = sprintf('geodata::worldclim_country(country="AUS", var="%s", path="data/raw/worldclim", version="2.1")', variable),
      worldclim_version = "2.1", reference_period = "1970-2000",
      country = "AUS", resolution_arcseconds = 30,
      retrieval_utc = retrieval_utc,
      retrieval_date_utc = substr(retrieval_utc, 1, 10),
      preexisting_at_first_validation = if (!is.null(old) && nrow(old) == 1L)
        old$preexisting_at_first_validation else already_present,
      file = filename, bytes = file.info(filename)$size, md5 = checksum,
      n_layers = terra::nlyr(r), layer_names = paste(names(r), collapse = ";"),
      crs = terra::crs(r), xmin = raster_extent[1], xmax = raster_extent[2],
      ymin = raster_extent[3], ymax = raster_extent[4],
      x_resolution_degrees = terra::res(r)[1], y_resolution_degrees = terra::res(r)[2],
      n_rows = nrow(r), n_columns = ncol(r),
      terra_version = as.character(utils::packageVersion("terra")),
      geodata_version = as.character(utils::packageVersion("geodata")),
      stringsAsFactors = FALSE
    )
    rasters[[i]] <- r
    # Preserve provenance as each potentially long download completes.
    partial_manifest <- do.call(rbind, metadata[seq_len(i)])
    saveRDS(partial_manifest, manifest_path)
    utils::write.csv(partial_manifest,
                     file.path("outputs", "tables", "worldclim_raster_metadata.csv"),
                     row.names = FALSE, na = "")
  }
  reference <- rasters[[1]]
  stopifnot(all(vapply(rasters, function(r)
    isTRUE(terra::compareGeom(reference, r, lyrs = FALSE, stopOnError = FALSE)),
    logical(1))))
  message("Verified 44 source layers at 30 arc-seconds in EPSG:4326.")
  invisible(list(rasters = rasters, metadata = do.call(rbind, metadata)))
}

if (sys.nframe() == 0L) acquire_worldclim()
