# Download the full raw FrogID Dataset 6 CSV.
# Raw source is kept immutable under data/raw/frogid/.

source_url <- "https://d2pifd398unoeq.cloudfront.net/FrogID6_final_dataset.csv"

output_dir <- file.path("data", "raw", "frogid")
output_file <- file.path(output_dir, "FrogID6_final_dataset.csv")
checksum_file <- file.path(output_dir, "FrogID6_final_dataset.md5")

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(output_file)) {

  message("Downloading FrogID Dataset 6...")

  download.file(
    url = source_url,
    destfile = output_file,
    mode = "wb",
    quiet = FALSE
  )

} else {

  message("Raw FrogID file already exists; not downloading again.")

}

size_bytes <- file.info(output_file)$size

if (is.na(size_bytes) || size_bytes <= 0) {
  stop("Downloaded FrogID file is missing or empty.")
}

checksum <- tools::md5sum(output_file)

writeLines(
  paste(names(checksum), checksum),
  checksum_file
)

message("Saved raw FrogID data:")
message(normalizePath(output_file, winslash = "/"))

message(sprintf(
  "File size: %.2f MB",
  size_bytes / 1024^2
))

message("MD5:")
message(unname(checksum))