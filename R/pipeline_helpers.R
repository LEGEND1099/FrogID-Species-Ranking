# Shared, deterministic data-preparation rules. Run scripts from repository root.
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tibble)
})

raw_frogid_path <- "data/raw/frogid/FrogID6_final_dataset.csv"

read_frogid <- function(path = raw_frogid_path) {
  x <- read_csv(path, col_types = cols(.default = col_character(),
    decimalLatitude = col_double(), decimalLongitude = col_double(),
    coordinateUncertaintyInMeters = col_double()), progress = FALSE)
  stopifnot(nrow(problems(x)) == 0L)
  x
}

valid_coordinates <- function(lat, lon) {
  is.finite(lat) & is.finite(lon) & abs(lat) <= 90 & abs(lon) <= 180
}

valid_uncertainty <- function(x) is.finite(x) & x > 0 & x <= 1000

event_metadata_conflicts <- function(x) {
  fields <- c("decimalLatitude", "decimalLongitude", "eventDate", "eventTime", "recordedBy")
  bind_rows(lapply(fields, function(field) {
    # Missing vs nonmissing also counts as disagreement.
    x |> distinct(eventID, .data[[field]]) |> count(eventID, name = "distinct_values") |>
      filter(distinct_values > 1L) |> mutate(field = field)
  }))
}

select_species <- function(counts) {
  counts <- counts |> arrange(desc(clean_single_species_events), scientificName)
  threshold <- if (sum(counts$clean_single_species_events >= 2000L) < 15L) 1000L else 2000L
  eligible <- which(counts$clean_single_species_events >= threshold)
  # The cap applies after the fallback too; ties use scientific name ascending.
  selected_indices <- head(eligible, 25L)
  counts |> mutate(selected = seq_len(n()) %in% selected_indices, threshold_used = threshold)
}

add_calendar_features <- function(x) {
  x$eventDate <- as.Date(x$eventDate, format = "%Y-%m-%d")
  stopifnot(!anyNA(x$eventDate))
  x$month <- as.integer(format(x$eventDate, "%m"))
  x$day_of_year <- as.integer(format(x$eventDate, "%j"))
  year <- as.integer(format(x$eventDate, "%Y"))
  days_in_year <- ifelse(year %% 4 == 0 & (year %% 100 != 0 | year %% 400 == 0), 366, 365)
  x$month_sin <- sin(2 * pi * (x$month - 1) / 12)
  x$month_cos <- cos(2 * pi * (x$month - 1) / 12)
  x$day_of_year_sin <- sin(2 * pi * (x$day_of_year - 1) / days_in_year)
  x$day_of_year_cos <- cos(2 * pi * (x$day_of_year - 1) / days_in_year)
  x
}

safe_left_join <- function(x, y, by) {
  stopifnot(!anyDuplicated(y[by]))
  out <- left_join(x, y, by = by, relationship = "many-to-one")
  stopifnot(nrow(out) == nrow(x))
  out
}
