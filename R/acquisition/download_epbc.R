# Acquire the latest official DCCEEW/SPRAT threatened-species CSV from CKAN.
# Reuse the frozen local snapshot unless --refresh is explicitly requested.
suppressPackageStartupMessages(library(readr))
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Install jsonlite in the project renv library before acquiring EPBC data.")
}

raw_dir <- file.path("data", "raw", "epbc")
table_dir <- file.path("outputs", "tables")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)
manifest_path <- file.path(raw_dir, "source_manifest.csv")
refresh <- "--refresh" %in% commandArgs(trailingOnly = TRUE)
required_columns <- c(
  "Scientific Name", "Current Scientific Name", "Threatened status", "Class",
  "Listed SPRAT TaxonID", "Current SPRAT TaxonID", "Profile", "Date extracted"
)

read_source <- function(path) {
  source <- read_csv(path, col_types = cols(.default = col_character()),
                     na = c("", "-"), show_col_types = FALSE)
  stopifnot(all(required_columns %in% names(source)), nrow(source) > 0L)
  if (nrow(problems(source))) stop("EPBC CSV has parsing problems.")
  source
}

if (file.exists(manifest_path) && !refresh) {
  manifest <- read_csv(manifest_path, col_types = cols(.default = col_character()))
  stopifnot(nrow(manifest) == 1L)
  source_path <- file.path(raw_dir, manifest$local_filename)
  if (!file.exists(source_path)) stop("Frozen EPBC file is missing; rerun with --refresh.")
  if (unname(tools::md5sum(source_path)) != manifest$md5) {
    stop("Frozen EPBC source checksum changed; investigate before rerunning.")
  }
  source <- read_source(source_path)
  message("Reusing frozen EPBC snapshot: ", manifest$resource_name)
} else {
  dataset_id <- "ae652011-f39e-4c6c-91b8-1dc2d2dfee8f"
  api_url <- paste0("https://data.gov.au/data/api/3/action/package_show?id=", dataset_id)
  metadata_path <- file.path(raw_dir, "ckan_package_metadata.json")
  options(timeout = max(300, getOption("timeout")))
  download.file(api_url, paste0(metadata_path, ".part"), mode = "wb", quiet = TRUE)
  metadata <- jsonlite::fromJSON(paste0(metadata_path, ".part"), simplifyVector = FALSE)
  if (!isTRUE(metadata$success)) stop("Official CKAN API did not report success.")
  package <- metadata$result
  candidates <- Filter(function(resource) {
    toupper(resource$format) == "CSV" &&
      grepl("^Threatened Species State Lists", resource$name)
  }, package$resources)
  if (!length(candidates)) stop("No official threatened-species CSV resource found.")
  timestamps <- vapply(candidates, function(resource) {
    if (is.null(resource$last_modified)) resource$created else resource$last_modified
  }, character(1))
  resource <- candidates[[order(timestamps, decreasing = TRUE)[1]]]
  if (!startsWith(resource$url, "https://data.gov.au/")) {
    stop("The discovered resource moved off data.gov.au; review the source first.")
  }
  filename <- basename(sub("[?].*$", "", resource$url))
  stopifnot(grepl("^[A-Za-z0-9._-]+[.]csv$", filename))
  source_path <- file.path(raw_dir, filename)
  download.file(resource$url, paste0(source_path, ".part"), mode = "wb", quiet = FALSE)
  source <- read_source(paste0(source_path, ".part"))
  dates <- unique(na.omit(source[["Date extracted"]]))
  stopifnot(length(dates) == 1L)
  if (!file.copy(paste0(source_path, ".part"), source_path, overwrite = TRUE)) {
    stop("Could not save validated EPBC source.")
  }
  if (!file.copy(paste0(metadata_path, ".part"), metadata_path, overwrite = TRUE)) {
    stop("Could not save official CKAN metadata.")
  }
  unlink(c(paste0(source_path, ".part"), paste0(metadata_path, ".part")))
  manifest <- data.frame(
    publisher = package$organization$title,
    source = "DCCEEW Species Profile and Threats Database (SPRAT), via data.gov.au",
    dataset_title = package$title,
    dataset_url = paste0("https://data.gov.au/data/dataset/", dataset_id),
    discovery_api_url = api_url,
    dataset_metadata_modified = package$metadata_modified,
    resource_id = resource$id,
    resource_name = resource$name,
    resource_last_modified = resource$last_modified,
    source_url = resource$url,
    source_extracted_date = dates,
    retrieved_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    licence = package$license_title,
    licence_url = package$license_url,
    local_filename = filename,
    md5 = unname(tools::md5sum(source_path)),
    file_bytes = file.info(source_path)$size,
    source_rows = nrow(source),
    amphibian_rows = sum(source$Class == "Amphibia", na.rm = TRUE),
    fields_used = paste(required_columns, collapse = "; ")
  )
  write_csv(manifest, manifest_path)
}
write_csv(manifest, file.path(table_dir, "epbc_acquisition_metadata.csv"))
message("Validated ", nrow(source), " listed taxa; ",
        sum(source$Class == "Amphibia", na.rm = TRUE), " amphibian taxa.")
