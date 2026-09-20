# =========================================================================
# EDA-03: Temporal and seasonal structure
#
# Purpose:
# Describe when FrogID events were recorded and determine whether the observed
# species composition varies meaningfully through the calendar.
#
# This is descriptive EDA only. No classifier is fitted.
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs:
#   outputs/tables/eda03_month_distribution.csv
#   outputs/tables/eda03_year_distribution.csv
#   outputs/tables/eda03_species_month_distribution.csv
#   outputs/tables/eda03_species_season_summary.csv
#   outputs/tables/eda03_year_class_tvd.csv
#   outputs/tables/eda03_temporal_summary.csv
#   outputs/figures/EDA03/eda03_species_month_heatmap.png
#   outputs/figures/EDA03/eda03_relative_month_profile.png
#   outputs/figures/EDA03/eda03_year_month_overview.png
# =========================================================================

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA03"

if (!file.exists(INPUT)) {
  stop("Missing input: ", INPUT, call. = FALSE)
}

dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

frogs <- as.data.frame(readRDS(INPUT))

frogs$date <- as.Date(frogs$eventDate)
frogs$year <- as.integer(format(frogs$date, "%Y"))
frogs$weekday <- weekdays(frogs$date)

stopifnot(
  nrow(frogs) == 247406L,
  length(unique(frogs$scientificName)) == 18L,
  !any(is.na(frogs$date)),
  all(frogs$month == as.integer(format(frogs$date, "%m"))),
  all(frogs$day_of_year == as.integer(format(frogs$date, "%j")))
)

species_order <- names(
  sort(table(frogs$scientificName), decreasing = TRUE)
)

# -------------------------------------------------------------------------
# 1. Univariate temporal structure
# -------------------------------------------------------------------------

month_counts <- table(factor(frogs$month, levels = 1:12))

month_distribution <- data.frame(
  month = 1:12,
  month_name = month.abb,
  events = as.integer(month_counts),
  share_percent = 100 * as.integer(month_counts) / nrow(frogs)
)

year_counts <- table(frogs$year)

year_distribution <- data.frame(
  year = as.integer(names(year_counts)),
  events = as.integer(year_counts)
)

year_distribution$partial_year <-
  year_distribution$year %in% c(2017L, 2023L)

weekday_counts <- table(
  factor(
    frogs$weekday,
    levels = c(
      "Monday", "Tuesday", "Wednesday", "Thursday",
      "Friday", "Saturday", "Sunday"
    )
  )
)

weekend_share <- 100 * sum(
  frogs$weekday %in% c("Saturday", "Sunday")
) / nrow(frogs)

# -------------------------------------------------------------------------
# 2. Species x month association
# -------------------------------------------------------------------------

species_month <- table(
  factor(frogs$scientificName, levels = species_order),
  factor(frogs$month, levels = 1:12)
)

chi_month <- suppressWarnings(chisq.test(species_month))

cramers_v <- sqrt(
  unname(chi_month$statistic) /
    (sum(species_month) * min(nrow(species_month) - 1,
                              ncol(species_month) - 1))
)

species_month_prop <- prop.table(species_month, margin = 1)

species_month_distribution <- data.frame(
  species = rep(rownames(species_month_prop), each = 12),
  month = rep(1:12, times = nrow(species_month_prop)),
  month_name = rep(month.abb, times = nrow(species_month_prop)),
  within_species_share = as.vector(t(species_month_prop))
)

# -------------------------------------------------------------------------
# 3. Per-species seasonal summaries
# -------------------------------------------------------------------------

months_to_cover <- function(x, threshold = 0.80) {
  ordered <- sort(x, decreasing = TRUE)
  which(cumsum(ordered) >= threshold)[1]
}

# The stored cyclic encodings are year-length aware and provide a convenient
# circular summary without treating January and December as far apart.
season_summary <- do.call(
  rbind,
  lapply(species_order, function(sp) {
    d <- frogs[frogs$scientificName == sp, ]

    mean_sin <- mean(d$day_of_year_sin)
    mean_cos <- mean(d$day_of_year_cos)
    R <- sqrt(mean_sin^2 + mean_cos^2)

    monthly <- species_month_prop[sp, ]

    data.frame(
      species = sp,
      events = nrow(d),
      peak_month = which.max(monthly),
      peak_month_name = month.abb[which.max(monthly)],
      peak_month_share_percent = 100 * max(monthly),
      months_to_cover_80_percent = months_to_cover(monthly),
      circular_concentration_R = R,
      stringsAsFactors = FALSE
    )
  })
)

# -------------------------------------------------------------------------
# 4. Relative-to-overall monthly recording profile
#
# This is NOT a complete correction for observation effort.
# It simply compares each species' monthly recording distribution with the
# aggregate monthly distribution of all selected-species FrogID events.
# -------------------------------------------------------------------------

overall_smoothed <- (as.integer(month_counts) + 0.5) /
  (nrow(frogs) + 0.5 * 12)

relative_month_profile <- matrix(
  NA_real_,
  nrow = nrow(species_month),
  ncol = 12,
  dimnames = dimnames(species_month)
)

for (i in seq_len(nrow(species_month))) {
  species_smoothed <-
    (species_month[i, ] + 0.5) /
    (sum(species_month[i, ]) + 0.5 * 12)

  relative_month_profile[i, ] <-
    log2(species_smoothed / overall_smoothed)
}

# -------------------------------------------------------------------------
# 5. Year-to-year class-composition drift
# -------------------------------------------------------------------------

year_species <- table(
  frogs$year,
  factor(frogs$scientificName, levels = species_order)
)

year_species_prop <- prop.table(year_species, margin = 1)

overall_species_prop <- prop.table(
  table(factor(frogs$scientificName, levels = species_order))
)

year_tvd <- apply(
  year_species_prop,
  1,
  function(x) 0.5 * sum(abs(x - overall_species_prop))
)

year_class_tvd <- data.frame(
  year = as.integer(names(year_tvd)),
  total_variation_distance = as.numeric(year_tvd),
  partial_year = as.integer(names(year_tvd)) %in% c(2017L, 2023L)
)

# -------------------------------------------------------------------------
# 6. Compact summary table
# -------------------------------------------------------------------------

temporal_summary <- data.frame(
  measure = c(
    "first_event_date",
    "last_event_date",
    "calendar_days_spanned",
    "days_with_records",
    "largest_month",
    "largest_month_share_percent",
    "weekend_share_percent",
    "species_month_chisq",
    "species_month_df",
    "species_month_cramers_v"
  ),
  value = c(
    as.character(min(frogs$date)),
    as.character(max(frogs$date)),
    as.character(as.integer(diff(range(frogs$date))) + 1L),
    as.character(length(unique(frogs$date))),
    month.abb[which.max(month_counts)],
    sprintf("%.4f", max(month_distribution$share_percent)),
    sprintf("%.4f", weekend_share),
    sprintf("%.4f", unname(chi_month$statistic)),
    as.character(unname(chi_month$parameter)),
    sprintf("%.4f", cramers_v)
  ),
  stringsAsFactors = FALSE
)

write.csv(
  month_distribution,
  file.path(TABLE_DIR, "eda03_month_distribution.csv"),
  row.names = FALSE
)

write.csv(
  year_distribution,
  file.path(TABLE_DIR, "eda03_year_distribution.csv"),
  row.names = FALSE
)

write.csv(
  species_month_distribution,
  file.path(TABLE_DIR, "eda03_species_month_distribution.csv"),
  row.names = FALSE
)

write.csv(
  season_summary,
  file.path(TABLE_DIR, "eda03_species_season_summary.csv"),
  row.names = FALSE
)

write.csv(
  year_class_tvd,
  file.path(TABLE_DIR, "eda03_year_class_tvd.csv"),
  row.names = FALSE
)

write.csv(
  temporal_summary,
  file.path(TABLE_DIR, "eda03_temporal_summary.csv"),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# Figures
# -------------------------------------------------------------------------

# Figure 1: raw species-by-month distribution.
png(
  file.path(FIG_DIR, "eda03_species_month_heatmap.png"),
  width = 1800,
  height = 1250,
  res = 180
)

par(mar = c(5, 11, 4, 2))

image(
  x = 1:12,
  y = seq_along(species_order),
  z = t(species_month_prop[rev(species_order), ]),
  col = hcl.colors(60, "Blues 3"),
  axes = FALSE,
  xlab = "Calendar month",
  ylab = "",
  main = "Monthly distribution within each species"
)

axis(1, at = 1:12, labels = month.abb)
axis(
  2,
  at = seq_along(species_order),
  labels = rev(species_order),
  las = 1,
  cex.axis = 0.65
)

dev.off()

# Figure 2: relative monthly profile.
png(
  file.path(FIG_DIR, "eda03_relative_month_profile.png"),
  width = 1800,
  height = 1250,
  res = 180
)

par(mar = c(5, 11, 4, 2))

lim <- max(abs(relative_month_profile), finite = TRUE)

image(
  x = 1:12,
  y = seq_along(species_order),
  z = t(relative_month_profile[rev(species_order), ]),
  col = hcl.colors(81, "Blue-Red 3"),
  zlim = c(-lim, lim),
  axes = FALSE,
  xlab = "Calendar month",
  ylab = "",
  main = "Species recording share relative to overall monthly recording pattern"
)

axis(1, at = 1:12, labels = month.abb)
axis(
  2,
  at = seq_along(species_order),
  labels = rev(species_order),
  las = 1,
  cex.axis = 0.65
)

dev.off()

# Figure 3: year-by-month recording pattern.
year_month <- table(
  frogs$year,
  factor(frogs$month, levels = 1:12)
)

year_month_prop <- prop.table(year_month, margin = 1)

png(
  file.path(FIG_DIR, "eda03_year_month_overview.png"),
  width = 1700,
  height = 850,
  res = 180
)

par(mar = c(5, 5, 4, 2))

image(
  x = 1:12,
  y = seq_len(nrow(year_month_prop)),
  z = t(year_month_prop[rev(seq_len(nrow(year_month_prop))), ]),
  col = hcl.colors(60, "Blues 3"),
  axes = FALSE,
  xlab = "Calendar month",
  ylab = "Year",
  main = "Monthly recording distribution within each year"
)

axis(1, at = 1:12, labels = month.abb)
axis(
  2,
  at = seq_len(nrow(year_month_prop)),
  labels = rev(rownames(year_month_prop)),
  las = 1
)

dev.off()

# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-03 TEMPORAL AND SEASONAL STRUCTURE\n")
cat("============================================================\n")

cat("\nMonthly distribution:\n")
print(month_distribution, row.names = FALSE)

cat("\nYear distribution:\n")
print(year_distribution, row.names = FALSE)

cat(sprintf(
  "\nSpecies x month: X-squared = %.1f, df = %d, Cramer's V = %.4f\n",
  unname(chi_month$statistic),
  unname(chi_month$parameter),
  cramers_v
))

cat("\nPer-species seasonal summary:\n")
print(season_summary, row.names = FALSE, digits = 4)

cat("\nYear-to-year class-composition TVD:\n")
print(year_class_tvd, row.names = FALSE, digits = 4)

cat("\nEDA-03 COMPLETE\n")
cat("No classifier was fitted and no certified data were modified.\n")