# =========================================================================
# EDA: does the prepared FrogID data carry usable information about
#      TEMPORAL / SEASONAL structure, and does that structure help
#      distinguish species?
#
# Input : data/processed/frog_primary_multiclass.rds
# Output: eda_temporal_seasonal/figures/*.png  (all figures)
#         console tables (every numeric summary quoted in the findings
#         document is printed here)
#
# Scope, in the order it runs:
#   1. temporal data quality (encodings, coverage, partial years)
#   2. univariate analysis  (month, day-of-year, year, weekday, daily series)
#   3. bivariate analysis   (time vs species, time vs space, time vs climate,
#                            year vs class composition)
#   4. multivariate view    (predictor ladder isolating the marginal value of
#                            temporal information, forward-in-time validation,
#                            and whether the climate block already encodes
#                            the calendar)
#
# Exploratory only: no cleaning, imputation, filtering or model selection.
#
# How to run, from the PROJECT ROOT (not from inside this folder) so that the
# relative paths below resolve:
#     source("eda_temporal_seasonal/eda_temporal_seasonal.R")
# Everything it prints is the source of the numbers quoted in
# EDA_findings_temporal_seasonal.md.
#
# Runtime: section 4 fits eleven random forests on ~170k rows with
# mtry = p, so allow roughly 20-40 minutes depending on the machine.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ranger)
})

# One seed for the whole script: it fixes the 70/30 split and every random
# forest, so a re-run reproduces these numbers.
set.seed(5003)

INPUT   <- "data/processed/frog_primary_multiclass.rds"
OUT_DIR <- "eda_temporal_seasonal"
FIG_DIR <- file.path(OUT_DIR, "figures")

if (!file.exists(INPUT)) stop("Missing input: ", INPUT, call. = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

# Derived columns added here, not in the certified data. The dataset ships
# with `month` and `day_of_year` but no calendar date object, so `date` is
# rebuilt from eventDate and `year` / `weekday` are taken from it; weekday is
# an ordered factor so it prints Monday-first rather than alphabetically.
frogs <- as.data.frame(readRDS(INPUT))
frogs$scientificName <- factor(frogs$scientificName)
frogs$date    <- as.Date(frogs$eventDate)
frogs$year    <- as.integer(format(frogs$date, "%Y"))
frogs$weekday <- factor(weekdays(frogs$date),
                        levels = c("Monday", "Tuesday", "Wednesday", "Thursday",
                                   "Friday", "Saturday", "Sunday"))
# 0.5-degree grid cell id (floor(x*2) buckets degrees into halves): used as
# the spatial "footprint" of a species when comparing seasonal against
# spatial overlap in section 3c.
frogs$cell05  <- paste(floor(frogs$decimalLatitude * 2),
                       floor(frogs$decimalLongitude * 2), sep = "_")
# Four latitude bands, cut at roughly Tas/Vic, southern NSW, northern NSW and
# Queensland-and-north. They are deliberately coarse: the point is to ask
# whether the seasonal SHAPE differs by region, not to model latitude.
frogs$latband <- cut(frogs$decimalLatitude,
                     breaks = c(-45, -37, -33, -28, -8),
                     labels = c("<-37 (Tas/Vic)", "-37..-33 (SE NSW)",
                                "-33..-28 (N NSW)", ">-28 (QLD/N)"))

# -------------------------------------------------------------------------
# Predictor blocks
# -------------------------------------------------------------------------

geo_vars  <- c("decimalLatitude", "decimalLongitude")
cal_vars  <- c("month", "day_of_year", "month_sin", "month_cos",
               "day_of_year_sin", "day_of_year_cos")
# The split between bio_vars and evc_vars is the single most important design
# decision in this script. Both are "climate", but BIO1-BIO19 are ANNUAL
# normals - one fixed value per location, identical in January and July - so
# they carry no calendar information. The two event-month variables are the
# normals FOR THE MONTH THE RECORDING WAS MADE, so they move with the
# calendar and are effectively temporal predictors. Section 4d demonstrates
# this; keeping them in a supposedly "season-free" model would invalidate the
# whole comparison.
bio_vars  <- paste0("BIO", 1:19)          # annual normals: no calendar content
elev_vars <- "elevation"
evc_vars  <- c("climatological_tavg_event_month",   # normals FOR THE EVENT MONTH:
               "climatological_prec_event_month")   # these DO carry calendar content
all_vars  <- c(geo_vars, cal_vars, bio_vars, elev_vars, evc_vars)

stopifnot(length(all_vars) == 30L, all(all_vars %in% names(frogs)))

# Species are handled in descending frequency order everywhere, so tables and
# figures always line up. Genus abbreviations are four letters rather than
# one because Limnodynastes peronii and Litoria peronii would otherwise both
# print as "L. peronii".
sp_counts <- sort(table(frogs$scientificName), decreasing = TRUE)
sp_order  <- names(sp_counts)
abbrev    <- c(Crinia = "Cri.", Limnodynastes = "Limn.",
               Litoria = "Lit.", Adelotus = "Ade.")
short_name <- function(x) {
  vapply(strsplit(as.character(x), " ", fixed = TRUE), function(p) {
    g <- if (p[1] %in% names(abbrev)) abbrev[[p[1]]] else paste0(substr(p[1], 1, 1), ".")
    paste(g, p[2])
  }, character(1))
}
sp_label <- short_name(sp_order)
MON <- month.abb

# -------------------------------------------------------------------------
# Plot theme
# -------------------------------------------------------------------------

# Colours are fixed roles, not per-figure choices, and match the
# species-distribution script so the two sets of figures read the same way:
#   S1 blue   - the main series ("the data")
#   S2 orange - the contrast series (reference lines, second split, negatives)
#   S3 green  - a third series, only where three are genuinely needed
#   BAND_COLS - ordered south-to-north scale for the four latitude bands
#   seq_blue  - one-hue ramp for magnitude (heatmaps: light = low, dark = high)
#   div_bred  - blue-white-red ramp for quantities with a meaningful zero,
#               used for the log-ratio heatmap where zero means "as expected"
SURF <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"
MUTED <- "#898781"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"
S1 <- "#2a78d6"; S2 <- "#eb6834"; S3 <- "#1baf7a"
BAND_COLS <- c("#0d366b", "#2a78d6", "#86b6ef", "#eb6834")

seq_blue <- colorRampPalette(c("#fcfcfb", "#cde2fb", "#9ec5f4",
                               "#5598e7", "#2a78d6", "#1c5cab", "#0d366b"))
div_bred <- colorRampPalette(c("#0d366b", "#2a78d6", "#9ec5f4",
                               "#f0efec", "#f0a3a3", "#d03b3b", "#7a1f1f"))

# open_png() / close_png() wrap the PNG device so every figure gets identical
# size, resolution, background and typography. par(adj = 0) is what makes the
# main titles left-aligned. banner() just prints a console separator.
open_png <- function(file, width = 9, height = 6) {
  png(file.path(FIG_DIR, file), width = width, height = height,
      units = "in", res = 200, bg = SURF)
  par(family = "sans", col.axis = MUTED, col.lab = INK2, col.main = INK,
      fg = AXIS, bg = SURF, cex.main = 1.05, cex.axis = 0.8, cex.lab = 0.9,
      font.main = 2, adj = 0, mgp = c(2.3, 0.6, 0), tcl = -0.25)
  invisible(NULL)
}
close_png <- function() invisible(dev.off())
subtitle  <- function(txt) mtext(txt, side = 3, line = 0.35, adj = 0,
                                 cex = 0.78, col = INK2)
banner    <- function(txt) cat("\n\n", strrep("=", 72), "\n", txt, "\n",
                               strrep("=", 72), "\n", sep = "")

# Entropy helpers, used throughout section 3 to answer "how much does
# knowing X tell us about the species?".
#   H_bits(p)             - Shannon entropy of a probability vector, in bits.
#                           H(species) = 3.21 here, i.e. the total label
#                           uncertainty that predictors can remove.
#   cond_entropy(group,y) - H(y | group): the entropy of y within each level
#                           of group, averaged with weights equal to each
#                           level's share of the data.
# The difference H(y) - H(y | group) is the mutual information: the bits of
# class uncertainty that knowing `group` removes.
H_bits <- function(p) { p <- p[p > 0]; -sum(p * log2(p)) }
cond_entropy <- function(group, y) {
  tb <- table(group, y)
  w  <- rowSums(tb) / sum(tb)
  sum(w * apply(tb, 1, function(r) H_bits(r / sum(r))))
}

# =========================================================================
# 1. TEMPORAL DATA QUALITY
# =========================================================================

banner("1. TEMPORAL DATA QUALITY")

# Three checks before trusting any temporal analysis: how long the window is,
# whether there are gaps in it (days spanned vs days with records), and
# whether the supplied `month` / `day_of_year` columns actually agree with
# eventDate. Any disagreement here would invalidate everything downstream.
cat("rows:", nrow(frogs), " date range:", format(min(frogs$date)), "to",
    format(max(frogs$date)), "\n")
cat("calendar days spanned:", as.integer(diff(range(frogs$date))) + 1L,
    " days with at least one record:", length(unique(frogs$date)), "\n")
cat("missing dates:", sum(is.na(frogs$date)),
    " | month disagreements:", sum(frogs$month != as.integer(format(frogs$date, "%m"))),
    " | day_of_year disagreements:",
    sum(frogs$day_of_year != as.integer(format(frogs$date, "%j"))), "\n")

# Reverse-engineer and verify the cyclic encodings, so later work knows
# exactly what month_sin / day_of_year_sin mean. This matters because the
# data-preparation step produced them and nothing downstream documents the
# exact formula: getting the phase or the period wrong would silently break
# any attempt to recreate or extend these features.
cat("\nmax |month_sin - sin(2*pi*(month-1)/12)| =",
    max(abs(frogs$month_sin - sin(2 * pi * (frogs$month - 1) / 12))), "\n")
year_len <- ifelse((frogs$year %% 4 == 0 & frogs$year %% 100 != 0) |
                     frogs$year %% 400 == 0, 366, 365)
cat("max |day_of_year_sin - sin(2*pi*(doy-1)/year_length)| =",
    max(abs(frogs$day_of_year_sin -
              sin(2 * pi * (frogs$day_of_year - 1) / year_len))), "\n")
cat("=> the calendar encodings are exact and year-length aware.\n")

cat("\nrecords in the two partial years:\n")
print(table(frogs$year[frogs$year %in% c(2017, 2023)]))
cat("2017 starts", format(min(frogs$date)), "and 2023 ends", format(max(frogs$date)),
    "- both are partial and must not be read as full survey years.\n")

# =========================================================================
# 2. UNIVARIATE ANALYSIS OF TIME
# =========================================================================

banner("2a. UNIVARIATE: calendar month")

month_n <- table(factor(frogs$month, levels = 1:12))
month_p <- month_n / nrow(frogs)
print(data.frame(month = MON, n = as.integer(month_n),
                 pct = round(100 * as.numeric(month_p), 2)), row.names = FALSE)

# Uniformity test for the monthly counts. The expected proportions are month
# LENGTHS, not 1/12, so that February is not flagged simply for being short
# (28.25 averages over the leap year in the window).
days_in_month <- c(31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
expected <- nrow(frogs) * days_in_month / sum(days_in_month)
print(chisq.test(as.integer(month_n), p = days_in_month / sum(days_in_month)))
cat("November share:", round(100 * month_p[[11]], 2), "% vs",
    round(100 * expected[11] / nrow(frogs), 2), "% expected\n")

banner("2b. UNIVARIATE: circular summaries of day-of-year")

# circ_stats(): summary statistics for a circular variable. Dates wrap
# around - 31 December sits next to 1 January - so the average date cannot be
# the mean of the day numbers (that would place the mean of 1 Jan and 31 Dec
# in July). Each date is turned into a unit vector instead and averaged:
#   R        - length of the mean vector, the concentration measure:
#              0 = spread evenly round the year, 1 = all on the same day
#   mean_doy - direction of the mean vector, converted back to a day number
#   circ_sd  - circular standard deviation, sqrt(-2 log R)
#   rayleigh_z - test statistic for uniformity, n * R^2. At this sample size
#              it always rejects, so report R, not the test.
circ_stats <- function(doy, period = 366) {
  a <- 2 * pi * doy / period
  C <- mean(cos(a)); S <- mean(sin(a))
  R <- sqrt(C^2 + S^2)
  mu <- (atan2(S, C) %% (2 * pi)) * period / (2 * pi)
  c(n = length(doy), R = R, mean_doy = mu,
    circ_sd = sqrt(-2 * log(R)), rayleigh_z = length(doy) * R^2)
}
overall_circ <- circ_stats(frogs$day_of_year)
print(round(overall_circ, 4))
cat("circular mean date:",
    format(as.Date("2021-01-01") + overall_circ[["mean_doy"]] - 1, "%d %b"), "\n")
cat("Rayleigh z is enormous at this n, so uniformity is rejected trivially;\n",
    "the mean resultant length R is the informative quantity.\n")

banner("2c. UNIVARIATE: year, weekday and the daily series")

print(table(frogs$year))
wd <- table(frogs$weekday)
print(data.frame(day = names(wd), n = as.integer(wd),
                 pct = round(100 * as.numeric(wd) / nrow(frogs), 2)), row.names = FALSE)
cat("weekend share:", round(mean(frogs$weekday %in% c("Saturday", "Sunday")), 4),
    "vs 0.2857 expected\n")

# Daily counts. table() returns a named vector whose names are the dates as
# text, so it is converted to a data frame and the dates are parsed back into
# Date objects before sorting - otherwise they would sort alphabetically.
# Only days with at least one record appear, which is fine here because the
# check above confirmed every day in the window has records.
daily <- as.data.frame(table(frogs$date), stringsAsFactors = FALSE)
names(daily) <- c("date", "n"); daily$date <- as.Date(daily$date)
daily <- daily[order(daily$date), ]
cat("median records/day:", median(daily$n), " max:", max(daily$n), "\n")
cat("top 8 recording days:\n")
print(head(daily[order(-daily$n), ], 8), row.names = FALSE)
# How concentrated is the effort in time? If the busiest 1% of days carried
# 1% of the records, recording would be spread evenly; the actual figure is
# several times that, which is the campaign effect in one number.
top1pct <- head(sort(daily$n, decreasing = TRUE), ceiling(0.01 * nrow(daily)))
cat("share of all records falling on the busiest 1% of days:",
    round(sum(top1pct) / nrow(frogs), 4), "\n")
# Autocorrelation of the daily counts: high values at short lags mean busy
# days cluster together (campaigns and weekends), which is worth knowing
# before treating daily counts as independent observations of anything.
cat("autocorrelation of daily counts, lags 1-14:\n")
print(round(acf(daily$n, lag.max = 14, plot = FALSE)$acf[-1], 3))

# November campaign effect, year by year. Comparing November with the mean of
# its two neighbours separates a genuine annual step from a gradual spring
# ramp-up: if it were just seasonal warming, the ratio would sit near 1.
nov_step <- frogs %>%
  filter(month %in% c(10, 11, 12)) %>%
  count(year, month) %>%
  pivot_wider(names_from = month, values_from = n, values_fill = 0) %>%
  rename(oct = `10`, nov = `11`, dec = `12`) %>%
  mutate(nov_vs_neighbours = nov / ((oct + dec) / 2))
print(as.data.frame(nov_step), digits = 3, row.names = FALSE)

# ---- Figure 1: univariate temporal panels -------------------------------
open_png("fig01_temporal_univariate.png", width = 12, height = 7)
par(mfrow = c(2, 2), mar = c(4, 4.6, 3.6, 1.2))
barplot(as.integer(month_n), names.arg = MON, col = S1, border = NA, las = 1,
        ylab = "events", main = "Recording effort is strongly seasonal")
subtitle("events per calendar month vs a uniform-effort reference")
lines(seq(0.7, by = 1.2, length.out = 12), expected, type = "s", col = S2, lwd = 1.8)
doy_n <- as.integer(table(factor(frogs$day_of_year, levels = 1:366)))
plot(1:366, doy_n, type = "h", col = "#cde2fb", las = 1, xaxt = "n",
     xlab = "", ylab = "events", main = "The spike is a few days wide, not a month")
subtitle("events per day-of-year (all years pooled), 7-day mean overlaid")
smooth7 <- stats::filter(doy_n, rep(1 / 7, 7), sides = 2)
lines(1:366, smooth7, col = S1, lwd = 1.8)
axis(1, at = cumsum(days_in_month) - days_in_month / 2, labels = MON, tick = FALSE,
     cex.axis = 0.75)
yr <- table(frogs$year)
bp <- barplot(as.integer(yr), names.arg = names(yr), col = S1, border = NA, las = 1,
              ylim = c(0, max(yr) * 1.15), ylab = "events",
              main = "Survey volume grew 15x then plateaued")
subtitle("events per year (2017 and 2023 are partial)")
text(bp, as.integer(yr), labels = format(as.integer(yr), big.mark = ","), pos = 3,
     cex = 0.7, col = INK2)
barplot(as.integer(wd), names.arg = substr(names(wd), 1, 3), border = NA, las = 1,
        col = c(rep(S1, 5), S2, S2), ylab = "events",
        main = "Weekends are over-represented")
subtitle("Sat/Sun carry more records than an equal-days split implies")
abline(h = nrow(frogs) / 7, col = MUTED, lty = 2, lwd = 1.4)
close_png()

# ---- Figure 2: daily time series ----------------------------------------
open_png("fig02_daily_timeseries.png", width = 12, height = 4.4)
par(mar = c(4, 4.6, 3.6, 1.2))
plot(daily$date, daily$n, type = "h", col = "#e1ecfb", las = 1, xlab = "",
     ylab = "events per day",
     main = "Effort arrives in campaign pulses on a rising baseline")
subtitle("daily counts (shaded) with a 7-day rolling mean; November peaks marked")
lines(daily$date, stats::filter(daily$n, rep(1 / 7, 7), sides = 2), col = S1, lwd = 1.4)
peaks <- daily %>% mutate(y = as.integer(format(date, "%Y"))) %>%
  group_by(y) %>% slice_max(n, n = 1) %>% ungroup()
points(peaks$date, peaks$n, pch = 19, col = S2, cex = 0.9)
close_png()

# ---- Figure 3: circular views -------------------------------------------
# a polar rose of effort, and a clock of per-species mean calling date.
# Base R has no polar plot, so polar_axes() draws one by hand: concentric
# rings at R = 0.25/0.5/0.75/1, a spoke and label per month placed at the
# middle of that month's arc, and everything plotted as
# (x, y) = (r*sin(angle), r*cos(angle)) so that angle 0 points north (Jan)
# and the year runs clockwise.
polar_axes <- function() {
  plot.new(); plot.window(c(-1.25, 1.25), c(-1.25, 1.25), asp = 1)
  for (r in c(0.25, 0.5, 0.75, 1)) {
    a <- seq(0, 2 * pi, length.out = 200)
    lines(r * sin(a), r * cos(a), col = GRID)
  }
  mid <- (cumsum(days_in_month) - days_in_month / 2) / 366
  for (k in 1:12) {
    a <- 2 * pi * mid[k]
    lines(c(0, 1.02 * sin(a)), c(0, 1.02 * cos(a)), col = GRID)
    text(1.14 * sin(a), 1.14 * cos(a), MON[k], cex = 0.72, col = MUTED)
  }
}
sp_season <- frogs %>%
  group_by(scientificName) %>%
  summarise(n = n(), R = circ_stats(day_of_year)[["R"]],
            mean_doy = circ_stats(day_of_year)[["mean_doy"]], .groups = "drop")
sp_season <- sp_season[match(sp_order, sp_season$scientificName), ]

open_png("fig03_circular_seasonality.png", width = 11, height = 5.6)
par(mfrow = c(1, 2), mar = c(2, 2, 3.6, 2))
polar_axes()
title(main = "Effort concentrates in spring", col.main = INK)
subtitle(sprintf("mean vector R = %.3f, mean date %s (orange arrow)",
                 overall_circ[["R"]],
                 format(as.Date("2021-01-01") + overall_circ[["mean_doy"]] - 1, "%d %b")))
rad <- doy_n / max(doy_n)
for (k in 1:366) {
  a <- 2 * pi * (k - 1) / 366
  lines(c(0, rad[k] * sin(a)), c(0, rad[k] * cos(a)), col = S1, lwd = 1.1)
}
amu <- 2 * pi * overall_circ[["mean_doy"]] / 366
arrows(0, 0, overall_circ[["R"]] * 2.4 * sin(amu), overall_circ[["R"]] * 2.4 * cos(amu),
       col = S2, lwd = 2.4, length = 0.12)
polar_axes()
title(main = "Species split into winter and summer callers", col.main = INK)
subtitle("angle = circular mean calling date, radius = concentration R")
a <- 2 * pi * (sp_season$mean_doy - 1) / 366
points(sp_season$R * sin(a), sp_season$R * cos(a), pch = 19, col = S1,
       cex = sqrt(sp_season$n) / 90)
text(sp_season$R * sin(a), sp_season$R * cos(a), labels = short_name(sp_season$scientificName),
     pos = 4, cex = 0.55, col = INK2)
close_png()

# ---- Figure 4: year x month heatmap -------------------------------------
# Row-normalised so each year is compared on shape, not on volume: the point
# is that the November peak recurs every year, not that later years are
# bigger.
#
# NOTE on the image() calls in this script (there are four of them): base R's
# image() expects z[x, y] with y increasing upwards, which is the transpose
# of how a table reads on screen and upside down. The recurring idiom
#     image(1:ncol, 1:nrow, t(mat[rev(rownames), ]))
# transposes the matrix and reverses the row order so the heatmap comes out
# oriented exactly like the printed table - first row at the top.
ym <- table(frogs$year, frogs$month)
ymp <- prop.table(ym, 1)
open_png("fig04_year_month_heatmap.png", width = 8.6, height = 4.4)
par(mar = c(3.2, 4.6, 3.6, 4.5))
image(1:12, 1:nrow(ymp), t(ymp[rev(seq_len(nrow(ymp))), ]), col = seq_blue(64),
      zlim = c(0, 0.30), axes = FALSE, xlab = "", ylab = "",
      main = "The November campaign repeats every year")
subtitle("row-normalised; 2017 and 2023 are partial years")
axis(1, at = 1:12, labels = MON, tick = FALSE, cex.axis = 0.8)
axis(2, at = 1:nrow(ymp), labels = rev(rownames(ymp)), las = 1, tick = FALSE,
     cex.axis = 0.8)
close_png()

# =========================================================================
# 3. BIVARIATE ANALYSIS
# =========================================================================

banner("3a. BIVARIATE: does the date shift the species prior?")

# The 18 x 12 contingency table of species against month underpins most of
# section 3. Cramer's V rescales the chi-squared statistic onto 0-1 so that
# it does not simply grow with sample size the way X2 does; with n = 247,406
# the test itself is a formality, so V is the number to read.
sp_month <- table(frogs$scientificName, frogs$month)
cs <- chisq.test(sp_month)
cramers_v <- sqrt(unname(cs$statistic) / (nrow(frogs) * (min(dim(sp_month)) - 1)))
cat(sprintf("species x month: X2 = %.0f, df = %d, Cramer's V = %.4f\n",
            unname(cs$statistic), unname(cs$parameter), cramers_v))

# How many bits does each temporal variable tell us about the species?
# Hy is the total label uncertainty (3.21 bits); for each candidate variable
# the loop prints H(species | variable) and the mutual information
# Hy - H(species | variable), i.e. the uncertainty that variable removes.
# This puts month, year and weekday on one comparable scale, and includes
# the latitude band as a spatial reference point.
pri <- as.numeric(sp_counts) / nrow(frogs)
Hy  <- H_bits(pri)
for (v in c("month", "year", "weekday", "latband")) {
  Hc <- cond_entropy(frogs[[v]], frogs$scientificName)
  cat(sprintf("H(species | %-8s) = %.4f  =>  MI = %.4f bits (%.1f%% of H = %.4f)\n",
              v, Hc, Hy - Hc, 100 * (Hy - Hc) / Hy, Hy))
}
# The decisive comparison in this script. Conditioning on month AND latitude
# band jointly (interaction() builds the 12 x 4 combined grouping; drop =
# TRUE discards empty combinations) is compared with conditioning on the band
# alone. The difference Hc_l - Hc_ml is what the month still adds AFTER
# location is known. If season were merely a proxy for geography, that
# difference would collapse towards zero; it does not, which is the evidence
# that temporal and spatial information are complementary rather than
# redundant.
Hc_ml <- cond_entropy(interaction(frogs$month, frogs$latband, drop = TRUE),
                      frogs$scientificName)
Hc_l  <- cond_entropy(frogs$latband, frogs$scientificName)
cat(sprintf("H(species | month x latband) = %.4f => MI = %.4f bits (%.1f%%)\n",
            Hc_ml, Hy - Hc_ml, 100 * (Hy - Hc_ml) / Hy))
cat(sprintf("month still adds %.4f bits once the latitude band is known\n",
            Hc_l - Hc_ml))

# What does knowing the month do to a prevalence-only ranker? Instead of one
# global prevalence ordering, use the ordering observed WITHIN each month and
# average the resulting accuracy over months, weighted by how many records
# each month holds (w). The gap between the two lines is the practical value
# of the calendar, expressed in the same units as the models in section 4.
month_prop_sp <- prop.table(sp_month, 2)          # composition within each month
w <- as.numeric(table(frogs$month)) / nrow(frogs)
topk <- function(p, k) sum(sort(p, decreasing = TRUE)[1:k])
cat(sprintf("\nglobal prior      : Top-1 %.4f  Top-3 %.4f  Top-5 %.4f\n",
            max(pri), topk(pri, 3), topk(pri, 5)))
cat(sprintf("month-conditional : Top-1 %.4f  Top-3 %.4f  Top-5 %.4f\n",
            sum(w * apply(month_prop_sp, 2, max)),
            sum(w * apply(month_prop_sp, 2, topk, 3)),
            sum(w * apply(month_prop_sp, 2, topk, 5))))
cat("\nmost likely species in each month:\n")
print(data.frame(month = MON, n = as.integer(table(frogs$month)),
                 top_species = rownames(month_prop_sp)[apply(month_prop_sp, 2, which.max)],
                 share = round(apply(month_prop_sp, 2, max), 3)), row.names = FALSE)

banner("3b. BIVARIATE: per-species seasonality, raw and effort-adjusted")

month_prop <- prop.table(sp_month, 1)[sp_order, ]   # each species' own calendar
effort <- as.numeric(table(frogs$month)) / nrow(frogs)
# Per-species seasonality. tvd_effort is the total variation distance between
# a species' own monthly distribution and the overall effort calendar:
# 0 means the species is recorded exactly when people happen to be recording
# (so it carries no seasonal signal of its own), and larger values mean its
# calendar is genuinely different from the crowd's.
season_tab <- data.frame(
  species     = sp_order,
  n           = as.integer(sp_counts),
  peak_month  = MON[apply(month_prop, 1, which.max)],
  peak_share  = apply(month_prop, 1, max),
  months_80   = apply(month_prop, 1, function(r) sum(cumsum(sort(r, TRUE)) < 0.8) + 1),
  circ_R      = sp_season$R,
  mean_date   = format(as.Date("2021-01-01") + sp_season$mean_doy - 1, "%d %b"),
  tvd_effort  = apply(month_prop, 1, function(r) sum(abs(r - effort)) / 2))
print(season_tab, digits = 3, row.names = FALSE)

# Effort-adjusted seasonality. The raw monthly shares above are dominated by
# WHEN PEOPLE RECORD, so dividing each species' monthly share by the overall
# monthly effort share removes the sampling calendar and leaves the biology.
# On the log2 scale used here, 0 means "recorded exactly as often as the
# effort implies", +1 means twice as often, -1 half as often.
# Add-half smoothing ((n + 0.5) / (total + 6)) keeps months with zero records
# finite instead of producing -Inf.
sel_ratio <- log2(sweep((sp_month[sp_order, ] + 0.5) / (as.integer(sp_counts) + 6),
                        2, effort, "/"))
cat("\nlog2(species share / effort share):\n")
print(round(sel_ratio, 2))

# ---- Figure 5/6: raw vs effort-adjusted seasonal heatmaps ----------------
open_png("fig05_species_month_raw.png", width = 8.2, height = 5.4)
par(mar = c(3.2, 9.5, 3.6, 4.5))
image(1:12, 1:18, t(month_prop[rev(sp_order), ]), col = seq_blue(64), zlim = c(0, 0.38),
      axes = FALSE, xlab = "", ylab = "",
      main = "Raw seasonal profiles: everything peaks in November")
subtitle("row-normalised; each row sums to 100%")
axis(1, at = 1:12, labels = MON, tick = FALSE, cex.axis = 0.8)
axis(2, at = 1:18, labels = rev(sp_label), las = 1, tick = FALSE, cex.axis = 0.72)
close_png()

open_png("fig06_selection_ratio.png", width = 8.2, height = 5.4)
par(mar = c(3.2, 9.5, 3.6, 4.5))
image(1:12, 1:18, t(sel_ratio[rev(sp_order), ]), col = div_bred(64), zlim = c(-4, 4),
      axes = FALSE, xlab = "", ylab = "",
      main = "Once effort is divided out, real phenology appears")
subtitle("red = more records than the season's effort implies, blue = fewer")
axis(1, at = 1:12, labels = MON, tick = FALSE, cex.axis = 0.8)
axis(2, at = 1:18, labels = rev(sp_label), las = 1, tick = FALSE, cex.axis = 0.72)
close_png()

# ---- Figure 7: seasonal small multiples ---------------------------------
open_png("fig07_seasonal_small_multiples.png", width = 13, height = 6.2)
par(mfrow = c(3, 6), mar = c(2.4, 2.8, 2.2, 0.8), oma = c(0, 0, 2.4, 0))
for (s in sp_order) {
  plot(1:12, month_prop[s, ], type = "n", ylim = c(0, 0.40), xaxt = "n", yaxt = "n",
       xlab = "", ylab = "", main = short_name(s), cex.main = 0.85)
  polygon(c(1, 1:12, 12), c(0, effort, 0), col = GRID, border = NA)
  lines(1:12, month_prop[s, ], col = S1, lwd = 2)
  axis(1, at = c(1, 4, 7, 10), labels = c("J", "A", "J", "O"), tick = FALSE, cex.axis = 0.7)
  axis(2, at = c(0, 0.2, 0.4), labels = c("0", "20%", "40%"), las = 1, tick = FALSE,
       cex.axis = 0.7)
  text(12, 0.37, sprintf("R=%.2f", season_tab$circ_R[season_tab$species == s]),
       adj = 1, cex = 0.65, col = MUTED)
}
mtext("Two seasonal guilds: spring/summer breeders and winter callers", outer = TRUE,
      adj = 0, line = 0.6, font = 2, cex = 0.95, col = INK)
close_png()

banner("3c. BIVARIATE: season vs space, and season vs climate")

# Does the seasonal SHAPE change with latitude, or only its height? Each row
# is normalised to sum to 1, so the four bands are compared on profile rather
# than on how many records each contributes. The circular summary underneath
# gives the same comparison as a single mean date and concentration per band.
lat_month <- prop.table(table(frogs$latband, frogs$month), 1)
print(round(100 * lat_month, 1))
cat("\ncircular summary by latitude band:\n")
for (b in levels(frogs$latband)) {
  cst <- circ_stats(frogs$day_of_year[frogs$latband == b])
  cat(sprintf("  %-20s n=%6d  R=%.3f  mean date %s\n", b, cst[["n"]], cst[["R"]],
              format(as.Date("2021-01-01") + cst[["mean_doy"]] - 1, "%d %b")))
}

# Circular-linear correlation: the appropriate correlation between a circular
# variable (day-of-year) and a linear one, built from the correlations of x
# with sin and cos of the angle. It runs 0 to 1 with no sign, because a
# circular variable has no consistent direction to be positive about. A high
# value means the predictor effectively tracks the calendar - which is
# exactly what we expect to find for the event-month climate variables.
circ_lin <- function(x, doy) {
  a <- 2 * pi * doy / 366
  rxc <- cor(x, cos(a)); rxs <- cor(x, sin(a)); rcs <- cor(cos(a), sin(a))
  sqrt((rxc^2 + rxs^2 - 2 * rxc * rxs * rcs) / (1 - rcs^2))
}
# Complete-case frame: the ~2% of rows with missing WorldClim values are set
# aside HERE ONLY, so that every model in section 4 is fitted on exactly the
# same rows and the ladder comparisons are like-for-like. The certified
# dataset itself is never modified, and the temporal summaries above all use
# the full 247,406 rows.
cc <- frogs[stats::complete.cases(frogs[, all_vars]), ]
cc$month_f <- factor(cc$month)   # target for the month-recoverability probe
cat("complete cases used for the model probes:", nrow(cc), "of", nrow(frogs), "\n")
cat("\ncircular-linear correlation with day_of_year:\n")
for (v in c("decimalLatitude", "BIO1", "climatological_tavg_event_month",
            "climatological_prec_event_month", "elevation")) {
  cat(sprintf("  %-34s r_cl = %.4f\n", v, circ_lin(cc[[v]], cc$day_of_year)))
}
cat("\nmean event-month climate by month:\n")
print(round(aggregate(cbind(climatological_tavg_event_month,
                            climatological_prec_event_month) ~ month,
                      data = frogs, FUN = mean), 1), row.names = FALSE)

# The central question of this script: does season separate species that
# geography cannot? Two similarity measures per species pair, both on 0-1:
#   seasonal overlap - sum of the month-by-month minima of the two monthly
#                      distributions (1 = identical calendars, 0 = disjoint)
#   spatial overlap  - cosine similarity of their 0.5-degree cell profiles
#                      (1 = recorded in exactly the same places in the same
#                      proportions, 0 = no shared cells)
# Pairs in the bottom-right - high spatial, low seasonal overlap - are the
# ones where temporal predictors earn their place.
overlap <- function(p, q) sum(pmin(p, q))
cell_tab <- table(frogs$scientificName, frogs$cell05)[sp_order, ]
cell_norm <- cell_tab / sqrt(rowSums(cell_tab^2))
spatial_cos <- cell_norm %*% t(cell_norm)
pairs <- expand.grid(i = seq_len(18), j = seq_len(18)) %>% filter(i < j) %>%
  mutate(a = sp_order[i], b = sp_order[j],
         spatial_cosine = spatial_cos[cbind(i, j)],
         seasonal_overlap = mapply(function(x, y) overlap(month_prop[x, ], month_prop[y, ]),
                                   a, b))
cat("\nseasonal overlap across all 153 pairs: median", round(median(pairs$seasonal_overlap), 3),
    " min", round(min(pairs$seasonal_overlap), 3), "\n")
co <- pairs %>% filter(spatial_cosine > 0.3)
cat(nrow(co), "pairs share substantial range (cosine > 0.3); the least seasonally\n",
    "overlapping of them are the pairs season can separate but geography cannot:\n")
print(co %>% arrange(seasonal_overlap) %>%
        transmute(pair = paste(short_name(a), "/", short_name(b)),
                  spatial_cosine = round(spatial_cosine, 3),
                  seasonal_overlap = round(seasonal_overlap, 3)) %>% head(8),
      row.names = FALSE)
print(cor.test(pairs$spatial_cosine, pairs$seasonal_overlap, method = "spearman"))

# ---- Figure 8: latitude bands and the climate-calendar link -------------
open_png("fig08_latband_and_climate.png", width = 11.6, height = 4.8)
par(mfrow = c(1, 2), mar = c(4.2, 4.6, 3.6, 1.2))
plot(1:12, 100 * lat_month[1, ], type = "n", ylim = c(0, 25), xaxt = "n", las = 1,
     xlab = "", ylab = "% of that band's records",
     main = "Seasonal shape depends on latitude")
subtitle("monthly distribution of records within each latitude band")
for (k in seq_len(nrow(lat_month)))
  lines(1:12, 100 * lat_month[k, ], col = BAND_COLS[k], lwd = 2.2)
axis(1, at = 1:12, labels = MON, tick = FALSE, cex.axis = 0.75)
legend("topleft", legend = rownames(lat_month), col = BAND_COLS, lwd = 2.2,
       bty = "n", cex = 0.72)
mc <- aggregate(climatological_tavg_event_month ~ month, data = frogs, FUN = mean)
plot(mc$month, mc$climatological_tavg_event_month, type = "b", pch = 19, col = S1,
     lwd = 2.2, xaxt = "n", las = 1, xlab = "",
     ylab = "mean event-month temperature (degC)",
     main = "'Climate' predictors already encode the calendar")
subtitle("climatological_tavg_event_month by calendar month")
axis(1, at = 1:12, labels = MON, tick = FALSE, cex.axis = 0.75)
close_png()

# ---- Figure 9: seasonal vs spatial overlap ------------------------------
open_png("fig09_season_vs_space_overlap.png", width = 8.4, height = 5.6)
par(mar = c(4.4, 4.6, 3.6, 1.2))
plot(pairs$spatial_cosine, pairs$seasonal_overlap, pch = 21, bg = GRID, col = MUTED,
     cex = 0.9, ylim = c(0, 1), las = 1,
     xlab = "spatial overlap (cosine similarity of 0.5-degree cell profiles)",
     ylab = "seasonal overlap (sum of monthly minima)",
     main = "Where geography cannot separate a pair, season often can")
subtitle("all 153 species pairs; blue = pairs sharing substantial range")
points(co$spatial_cosine, co$seasonal_overlap, pch = 19, col = S1, cex = 1.1)
abline(h = median(pairs$seasonal_overlap), col = MUTED, lty = 2)
lab <- co[order(co$seasonal_overlap), ][1:4, ]
text(lab$spatial_cosine, lab$seasonal_overlap,
     paste(short_name(lab$a), "/", short_name(lab$b)), pos = 4, cex = 0.6, col = INK2)
close_png()

banner("3d. BIVARIATE: is the class mix stable over time?")

# Is the label distribution stationary? For each year, the total variation
# distance between that year's species composition and the overall prior:
# 0 means the year looks exactly like the pooled data, and 0.5 would mean
# half the probability mass sits on different species. This decides whether
# a model trained on early years can be expected to transfer to later ones
# (tested directly in section 4c).
year_comp <- prop.table(table(frogs$year, frogs$scientificName), 1)[, sp_order]
print(round(100 * year_comp, 1))
tvd_year <- apply(year_comp, 1, function(r) sum(abs(r - pri)) / 2)
cat("\ntotal variation distance of each year's composition from the overall prior:\n")
print(round(tvd_year, 3))
full_years <- year_comp[rownames(year_comp) %in% as.character(2018:2022), ]
cat("\nlargest swing in share across the full years 2018-2022 (percentage points):\n")
print(round(100 * sort(apply(full_years, 2, function(c) max(c) - min(c)),
                       decreasing = TRUE)[1:6], 1))

# ---- Figure 10: composition drift ---------------------------------------
open_png("fig10_year_composition_drift.png", width = 11.6, height = 4.4)
par(mfrow = c(1, 2), mar = c(4.2, 4.8, 3.6, 1.2))
bp <- barplot(tvd_year, col = ifelse(names(tvd_year) == "2017", S2, S1), border = NA,
              las = 1, ylim = c(0, 0.42), ylab = "TVD from overall prior",
              main = "The class mix is not stationary")
subtitle("2017 covers only Nov-Dec of the first season")
text(bp, tvd_year, labels = sprintf("%.2f", tvd_year), pos = 3, cex = 0.7, col = INK2)
plot(as.integer(rownames(year_comp)), 100 * year_comp[, sp_order[1]], type = "n",
     ylim = c(0, 45), las = 1, xlab = "", ylab = "% of that year's records",
     main = "The majority class keeps growing")
subtitle("share of the three most common species by year")
for (k in 1:3)
  lines(as.integer(rownames(year_comp)), 100 * year_comp[, sp_order[k]],
        col = BAND_COLS[k], lwd = 2.2, type = "b", pch = 19, cex = 0.7)
legend("topright", legend = sp_label[1:3], col = BAND_COLS[1:3], lwd = 2.2, bty = "n",
       cex = 0.75)
close_png()

# =========================================================================
# 4. HOW MUCH DOES TEMPORAL INFORMATION ACTUALLY ADD?
# =========================================================================

banner("4a. Predictor ladder isolating the temporal contribution")

# Diagnostic probe only. mtry is set to the full number of predictors in
# every model so that blocks of different size are compared fairly: with
# the default mtry = sqrt(p), an 8-predictor model can score BELOW a
# 2-predictor model simply because the informative variables are offered
# to each split less often.
# metrics(): every number this project reports, computed from a matrix of
# predicted probabilities (one row per test event, one column per species).
#   ord           - each row's species indices, most to least likely
#   rank_of_truth - position of the TRUE species in that ranking (1 = top)
#   top1/3/5      - share of events whose true species is in the top 1/3/5
#   macro_f1      - F1 per species, averaged UNWEIGHTED, so each of the 18
#                   counts equally however rare it is
#   mrr           - mean of 1/rank, the standard ranking metric
metrics <- function(prob, truth, classes) {
  ord <- t(apply(prob, 1, function(r) order(r, decreasing = TRUE)))
  rank_of_truth <- apply(cbind(match(truth, classes), ord), 1,
                         function(z) which.max(z[-1] == z[1]))
  pred <- classes[ord[, 1]]
  tab  <- table(factor(truth, levels = classes), factor(pred, levels = classes))
  rec  <- diag(tab) / pmax(rowSums(tab), 1)
  prec <- diag(tab) / pmax(colSums(tab), 1)
  f1   <- ifelse(rec + prec > 0, 2 * rec * prec / (rec + prec), 0)
  c(top1 = mean(rank_of_truth == 1), top3 = mean(rank_of_truth <= 3),
    top5 = mean(rank_of_truth <= 5), macro_f1 = mean(f1), mrr = mean(1 / rank_of_truth))
}

# A plain random 70/30 split, used for the whole ladder. Section 4c refits
# the two key models on a forward-in-time split instead, which is the harder
# and more realistic test for this dataset.
n_cc  <- nrow(cc)
train <- sample(n_cc, floor(0.7 * n_cc))
test  <- setdiff(seq_len(n_cc), train)

# fit_rf(): one random forest per predictor block.
#   vars               - the predictor block to fit on
#   tr / te            - row indices of the training and test rows, so the
#                        same function serves the random split, the
#                        forward-in-time split and the month probe
#   target             - the response column; defaults to the species label
#                        but is switched to month_f in section 4d
#   mtry = length(vars)- EVERY predictor is considered at every split (see
#                        the note above); this is the fairness fix, and it is
#                        also why the script is slow
#   probability = TRUE - return class probabilities, needed for Top-k and MRR
#   min.node.size = 5  - mild regularisation; trees would otherwise be huge
#   num.threads = 0    - use all available cores
#   importance         - impurity (Gini) importance, read at the end of 4d;
#                        it is biased towards continuous predictors with many
#                        split points, so treat it as a rough ordering
fit_rf <- function(vars, tr, te, target = "scientificName", ntree = 150) {
  rf <- ranger(x = cc[tr, vars, drop = FALSE], y = droplevels(cc[[target]][tr]),
               num.trees = ntree, min.node.size = 5, mtry = length(vars),
               probability = TRUE, num.threads = 0, seed = 5003,
               importance = "impurity")
  pr <- predict(rf, data = cc[te, vars, drop = FALSE])$predictions
  list(model = rf, prob = pr)
}

# The ladder is designed so that each DIFFERENCE isolates one question:
#   S1 -> S2  what does the calendar add to location alone?
#   C1 -> C2  what do the event-month climate variables add? (they are
#             temporal information in disguise - see section 4d)
#   C2 -> C3  what is left for the explicit calendar variables to add?
#   C1 -> C3  all temporal information together
# C1 is the only genuinely season-free model in the set, which is why it is
# the baseline for every "value of time" statement in the findings document.
ladder <- list(
  "T1 calendar only"                         = cal_vars,
  "S1 location only"                         = geo_vars,
  "S2 location + calendar"                   = c(geo_vars, cal_vars),
  "C1 location + static climate + elevation" = c(geo_vars, bio_vars, elev_vars),
  "C2 C1 + event-month climatology"          = c(geo_vars, bio_vars, elev_vars, evc_vars),
  "C3 C2 + calendar (full model)"            = all_vars)

# M0: give every test event the same prevalence vector, estimated on the
# TRAINING rows only. This is the "no predictors" reference row of the table.
classes <- levels(cc$scientificName)
prior_train <- as.numeric(table(cc$scientificName[train])) / length(train)
prior_prob <- matrix(prior_train, nrow = length(test), ncol = length(classes),
                     byrow = TRUE, dimnames = list(NULL, classes))
progression <- data.frame(model = "M0 prevalence prior", k = 0,
                          t(metrics(prior_prob, as.character(cc$scientificName[test]),
                                    classes)))
fits <- list()
for (nm in names(ladder)) {
  f <- fit_rf(ladder[[nm]], train, test)
  fits[[nm]] <- f
  m <- metrics(f$prob, as.character(cc$scientificName[test]), colnames(f$prob))
  progression <- rbind(progression, data.frame(model = nm, k = length(ladder[[nm]]), t(m)))
  cat(nm, ":", sprintf("%.4f", m), "\n")
}
print(progression, digits = 4, row.names = FALSE)
cat(sprintf("\nmarginal value of event-month climatology (C1 -> C2): %+.4f Top-1\n",
            progression$top1[progression$model == "C2 C1 + event-month climatology"] -
              progression$top1[progression$model == "C1 location + static climate + elevation"]))
cat(sprintf("marginal value of the explicit calendar (C2 -> C3):    %+.4f Top-1\n",
            progression$top1[progression$model == "C3 C2 + calendar (full model)"] -
              progression$top1[progression$model == "C2 C1 + event-month climatology"]))
cat(sprintf("all temporal information together  (C1 -> C3):         %+.4f Top-1\n",
            progression$top1[progression$model == "C3 C2 + calendar (full model)"] -
              progression$top1[progression$model == "C1 location + static climate + elevation"]))

open_png("fig11_model_ladder.png", width = 10, height = 5.4)
par(mar = c(8.5, 4.6, 3.6, 1.2))
mm <- t(as.matrix(progression[, c("top1", "top3")]))
bp <- barplot(mm, beside = TRUE, col = c(S1, S2), border = NA, las = 2,
              names.arg = progression$model, cex.names = 0.6, ylim = c(0, 1.05),
              ylab = "accuracy on held-out 30%",
              main = "Temporal information adds real but modest ranking skill")
subtitle("mtry fixed to all predictors so blocks of different size compare fairly")
legend("topleft", legend = c("Top-1", "Top-3"), fill = c(S1, S2), border = NA,
       bty = "n", cex = 0.8)
close_png()

banner("4b. Which species benefit from temporal information?")

# Recall per species under two models, so the difference shows WHICH species
# temporal information actually helps. The average gain across all 18 hides
# this completely: a few species gain heavily, a few lose slightly.
per_class_recall <- function(f) {
  pred <- colnames(f$prob)[apply(f$prob, 1, which.max)]
  truth <- as.character(cc$scientificName[test])
  tab <- table(factor(truth, levels = sp_order), factor(pred, levels = sp_order))
  diag(tab) / pmax(rowSums(tab), 1)
}
gain <- data.frame(
  species = sp_order,
  n = as.integer(sp_counts),
  recall_no_time = per_class_recall(fits[["C1 location + static climate + elevation"]]),
  recall_full    = per_class_recall(fits[["C3 C2 + calendar (full model)"]]))
gain$gain <- gain$recall_full - gain$recall_no_time
print(gain[order(-gain$gain), ], digits = 3, row.names = FALSE)

open_png("fig13_perclass_gain.png", width = 8.6, height = 5.4)
par(mar = c(4.4, 9.5, 3.6, 1.2))
g <- gain[order(gain$gain), ]
barplot(100 * g$gain, horiz = TRUE, col = ifelse(g$gain > 0, S1, S2), border = NA,
        names.arg = short_name(g$species), las = 1, cex.names = 0.72,
        xlab = "change in recall (percentage points)",
        main = "Seasonal information rescues the species geography confuses")
subtitle("per-species recall, full model minus the no-temporal-information model")
abline(v = 0, col = AXIS)
close_png()

banner("4c. Does the model survive being asked to predict a later period?")

# Forward-in-time validation: train on the earlier years and predict the
# later ones, which is what a deployed model would actually face. Comparing
# it with the random split shows how much of the random-split score depends
# on the test rows coming from the same period - and therefore the same
# survey campaigns and the same class mix - as the training rows.
tr_time <- which(cc$year <= 2021); te_time <- which(cc$year >= 2022)
cat("forward-in-time split: train", length(tr_time), "rows (2017-2021), test",
    length(te_time), "rows (2022-2023)\n")
transfer <- do.call(rbind, lapply(
  c("C1 location + static climate + elevation", "C3 C2 + calendar (full model)"),
  function(nm) {
    f <- fit_rf(ladder[[nm]], tr_time, te_time)
    rbind(data.frame(model = nm, split = "forward in time",
                     t(metrics(f$prob, as.character(cc$scientificName[te_time]),
                               colnames(f$prob)))),
          data.frame(model = nm, split = "random 70/30",
                     t(metrics(fits[[nm]]$prob, as.character(cc$scientificName[test]),
                               colnames(fits[[nm]]$prob)))))
  }))
prior_t <- as.numeric(table(cc$scientificName[tr_time])) / length(tr_time)
transfer <- rbind(transfer,
  data.frame(model = "M0 prevalence prior", split = "forward in time",
             t(metrics(matrix(prior_t, nrow = length(te_time), ncol = length(classes),
                              byrow = TRUE, dimnames = list(NULL, classes)),
                       as.character(cc$scientificName[te_time]), classes))))
print(transfer, digits = 4, row.names = FALSE)

open_png("fig12_forward_in_time.png", width = 8.6, height = 5)
par(mar = c(4.6, 4.6, 3.6, 1.2))
tt <- transfer[transfer$model != "M0 prevalence prior", ]
cmp <- matrix(tt$top1, nrow = 2,
              dimnames = list(c("forward in time", "random 70/30"),
                              c("no temporal info", "full model")))
bp <- barplot(cmp, beside = TRUE, col = c(S2, S1), border = NA, ylim = c(0, 1),
              ylab = "Top-1 accuracy",
              main = "Predicting a later period is harder than a random split")
subtitle("train 2017-2021, test 2022-2023")
legend("topright", legend = rownames(cmp), fill = c(S2, S1), border = NA, bty = "n",
       cex = 0.85)
close_png()

banner("4d. Does the climate block already encode the calendar?")

# Can the month be reconstructed from predictors that contain no date at all?
# If yes, those predictors ARE temporal predictors, whatever they are called.
# The two feature sets differ only by the two event-month climate variables,
# so the jump between them measures exactly how much calendar information
# those two columns leak. mean_circular_error is measured on the month circle
# (December and January are one month apart, not eleven).
month_probe <- do.call(rbind, lapply(
  list("static climate + location" = c(geo_vars, bio_vars, elev_vars),
       "+ event-month climatology" = c(geo_vars, bio_vars, elev_vars, evc_vars)),
  function(vars) {
    f <- fit_rf(vars, train, test, target = "month_f", ntree = 100)
    pred <- as.integer(colnames(f$prob)[apply(f$prob, 1, which.max)])
    truth <- as.integer(as.character(cc$month_f[test]))
    d <- pmin(abs(pred - truth), 12 - abs(pred - truth))
    data.frame(accuracy = mean(pred == truth), within_1_month = mean(d <= 1),
               mean_circular_error = mean(d))
  }))
print(month_probe, digits = 4)

# The same point in linear-model form: how well can each event-month climate
# variable be rebuilt from (a) the month alone, (b) the location and the
# static annual climate, (c) both? An R-squared close to 1 for (c) means the
# variable is very nearly a deterministic function of "where" and "when", and
# therefore carries little independent information of its own.
for (tgt in evc_vars) {
  r2 <- function(form) summary(lm(form, data = cc))$r.squared
  cat(sprintf("%s: R2 month-only %.4f | location + static climate %.4f | both %.4f\n",
              tgt,
              r2(as.formula(paste(tgt, "~ factor(month)"))),
              r2(as.formula(paste(tgt, "~", paste(c(geo_vars, bio_vars, elev_vars),
                                                  collapse = " + ")))),
              r2(as.formula(paste(tgt, "~ factor(month) +",
                                  paste(c(geo_vars, bio_vars, elev_vars),
                                        collapse = " + "))))))
}

open_png("fig14_month_recoverability.png", width = 8.2, height = 5)
par(mar = c(4.6, 4.6, 3.6, 1.2))
mp <- rbind(month_probe$accuracy, month_probe$within_1_month)
bp <- barplot(mp, beside = TRUE, col = c(S1, S2), border = NA, ylim = c(0, 1),
              names.arg = rownames(month_probe), cex.names = 0.8,
              ylab = "share of test events",
              main = "The event-month climatology gives the calendar away")
subtitle("recovering the calendar month from predictors with no explicit date")
legend("topleft", legend = c("exact month", "within one month"), fill = c(S1, S2),
       border = NA, bty = "n", cex = 0.85)
abline(h = 1 / 12, col = MUTED, lty = 2)
close_png()

# Where do the temporal predictors sit in the full model's importance
# ranking? The interesting comparison is within the calendar block itself:
# the day-of-year encodings against the coarser month encodings, which are
# a 12-level rounding of the same information.
imp <- sort(fits[["C3 C2 + calendar (full model)"]]$model$variable.importance,
            decreasing = TRUE)
cat("\nfull-model impurity importance (top 15):\n"); print(round(head(imp, 15), 1))
cat("ranks of the temporal predictors:\n")
print(match(c(cal_vars, evc_vars), names(imp)))

open_png("fig15_variable_importance.png", width = 8.4, height = 5.6)
par(mar = c(4.4, 9.5, 3.6, 1.2))
top <- rev(head(imp, 15))
is_time <- names(top) %in% c(cal_vars, evc_vars)
barplot(top, horiz = TRUE, col = ifelse(is_time, S2, S1), border = NA, las = 1,
        cex.names = 0.75, xlab = "impurity importance",
        main = "Temporal terms sit high in the full model")
subtitle("orange = calendar or event-month climatology, blue = location or static climate")
close_png()

banner("DONE")
cat("figures written to", FIG_DIR, "\n")
