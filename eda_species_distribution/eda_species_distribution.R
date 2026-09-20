# =========================================================================
# EDA: does the prepared FrogID data carry usable information about
#      species (class) identity?
#
# Input : data/processed/frog_primary_multiclass.rds
# Output: eda_species_distribution/figures/*.png  (all figures)
#         console tables (every numeric summary quoted in the findings
#         document is printed here)
#
# Scope of this script, in the order it runs:
#   1. structure and data-quality overview
#   2. univariate analysis  (response, then predictors)
#   3. bivariate analysis   (each predictor vs species; predictor vs predictor)
#   4. multivariate view    (PCA, LDA) and a diagnostic classifier that
#      quantifies how much class information the predictors jointly carry
#
# This script is exploratory only. It does not clean, impute, scale or
# filter the certified dataset, and it does not select a final model.
#
# How to run, from the PROJECT ROOT (not from inside this folder) so that the
# relative paths below resolve:
#     source("eda_species_distribution/eda_species_distribution.R")
# Everything it prints is the source of the numbers quoted in
# EDA_findings_species_distribution.md. Allow roughly 10-20 minutes: the
# seven random forests in section 4 dominate the runtime.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ranger)
})

if (!requireNamespace("MASS", quietly = TRUE)) {
  stop("Package 'MASS' (ships with R) is required for the LDA benchmark.",
       call. = FALSE)
}

# One seed for the whole script: it fixes the 70/30 split, the spatially
# blocked split and every random forest, so a re-run reproduces these numbers.
set.seed(5003)

INPUT   <- "data/processed/frog_primary_multiclass.rds"
OUT_DIR <- "eda_species_distribution"
FIG_DIR <- file.path(OUT_DIR, "figures")

if (!file.exists(INPUT)) {
  stop("Missing input: ", INPUT, call. = FALSE)
}
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

frogs <- readRDS(INPUT)
frogs <- as.data.frame(frogs)
frogs$scientificName <- factor(frogs$scientificName)
frogs$year <- as.integer(format(as.Date(frogs$eventDate), "%Y"))

# coarse 0.5-degree grid cell: used for aggregate maps and for the
# spatially blocked validation split further down
frogs$cell05 <- paste(floor(frogs$decimalLatitude * 2),
                      floor(frogs$decimalLongitude * 2), sep = "_")

# -------------------------------------------------------------------------
# Predictor blocks (the 30 whitelisted predictors, grouped as in the plan)
# -------------------------------------------------------------------------

geo_vars     <- c("decimalLatitude", "decimalLongitude")
season_vars  <- c("month", "day_of_year", "month_sin", "month_cos",
                  "day_of_year_sin", "day_of_year_cos")
clim_vars    <- c(paste0("BIO", 1:19),
                  "climatological_tavg_event_month",
                  "climatological_prec_event_month")
elev_vars    <- "elevation"
env_vars     <- c(clim_vars, elev_vars)
all_vars     <- c(geo_vars, season_vars, clim_vars, elev_vars)

stopifnot(length(all_vars) == 30L, all(all_vars %in% names(frogs)))

# Species are handled in descending frequency order (sp_order) everywhere in
# this script, so every table and figure lists them the same way.
# The genus abbreviations are four letters rather than one because two of the
# 18 species would otherwise both print as "L. peronii" (Limnodynastes
# peronii and Litoria peronii are different animals).
sp_counts  <- sort(table(frogs$scientificName), decreasing = TRUE)
sp_order   <- names(sp_counts)
abbrev     <- c(Crinia = "Cri.", Limnodynastes = "Limn.",
                Litoria = "Lit.", Adelotus = "Ade.")
short_name <- function(x) {
  parts <- strsplit(as.character(x), " ", fixed = TRUE)
  vapply(parts, function(p) {
    g <- if (p[1] %in% names(abbrev)) abbrev[[p[1]]] else paste0(substr(p[1], 1, 1), ".")
    paste(g, p[2])
  }, character(1))
}
sp_label <- short_name(sp_order)

# -------------------------------------------------------------------------
# Plot theme (light surface, one sequential blue hue, diverging blue-red)
# -------------------------------------------------------------------------

# Colours are fixed roles, not per-figure choices, so all 16 figures read the
# same way:
#   S1 blue   - the main series ("the data")
#   S2 orange - the contrast series (reference lines, second split, negatives)
#   S3 green  - a third series, used only where three are genuinely needed
#   seq_blue  - one-hue ramp for magnitude (heatmaps: light = low, dark = high)
#   div_bred  - blue-white-red ramp for quantities with a meaningful zero
# SURF is the panel background; INK/INK2/MUTED/GRID/AXIS are text and chrome.
SURF <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"
MUTED <- "#898781"; GRID <- "#e1e0d9"; AXIS <- "#c3c2b7"
S1 <- "#2a78d6"; S2 <- "#eb6834"; S3 <- "#1baf7a"

seq_blue <- colorRampPalette(c("#fcfcfb", "#cde2fb", "#9ec5f4",
                               "#5598e7", "#2a78d6", "#1c5cab", "#0d366b"))
div_bred <- colorRampPalette(c("#0d366b", "#2a78d6", "#9ec5f4",
                               "#f0efec", "#f0a3a3", "#d03b3b", "#7a1f1f"))

# open_png() / close_png() wrap the PNG device so every figure gets identical
# size, resolution, background and typography. par(adj = 0) is what makes the
# main titles left-aligned; mgp/tcl pull the axis labels and ticks in tight.
open_png <- function(file, width = 9, height = 6) {
  png(file.path(FIG_DIR, file), width = width, height = height,
      units = "in", res = 200, bg = SURF)
  par(family = "sans", col.axis = MUTED, col.lab = INK2, col.main = INK,
      fg = AXIS, bg = SURF, cex.main = 1.05, cex.axis = 0.8, cex.lab = 0.9,
      font.main = 2, adj = 0, mgp = c(2.3, 0.6, 0), tcl = -0.25)
  invisible(NULL)
}
close_png <- function() invisible(dev.off())

# adds a left-aligned subtitle under a left-aligned main title
subtitle <- function(txt) mtext(txt, side = 3, line = 0.35, adj = 0,
                                cex = 0.78, col = INK2)

# prints a visible separator in the console log, one per analysis section
banner <- function(txt) {
  cat("\n\n", strrep("=", 72), "\n", txt, "\n", strrep("=", 72), "\n", sep = "")
}

# =========================================================================
# 1. STRUCTURE AND DATA QUALITY
# =========================================================================

banner("1. STRUCTURE")

cat("rows:", nrow(frogs), " columns:", ncol(frogs),
    " species:", nlevels(frogs$scientificName),
    " unique events:", length(unique(frogs$eventID)), "\n")
cat("date range:", format(min(as.Date(frogs$eventDate))), "to",
    format(max(as.Date(frogs$eventDate))), "\n")

# environmental missingness is a single all-or-nothing block of rows
env_na_row <- apply(is.na(frogs[, env_vars]), 1, any)
cat("rows with any environmental NA:", sum(env_na_row),
    sprintf(" (%.2f%%)", 100 * mean(env_na_row)), "\n")
cat("missing values per environmental variable (should be constant):\n")
print(colSums(is.na(frogs[, env_vars])))

# does missingness depend on the class? (bias check, not a cleaning step)
na_by_species <- frogs %>%
  mutate(env_na = env_na_row) %>%
  group_by(scientificName) %>%
  summarise(n = n(), n_missing = sum(env_na), pct_missing = 100 * mean(env_na),
            .groups = "drop") %>%
  arrange(desc(n))
print(as.data.frame(na_by_species), digits = 3)
print(chisq.test(table(frogs$scientificName, env_na_row)))

# Complete-case frame used by every analysis that needs environmental values.
# Rows are never dropped from the certified dataset itself.
cc <- frogs[!env_na_row, ]
cat("complete-case rows used for environmental analyses:", nrow(cc), "\n")

# =========================================================================
# 2. UNIVARIATE ANALYSIS
# =========================================================================

banner("2a. UNIVARIATE: the response (species)")

class_tab <- data.frame(
  species = sp_order,
  n       = as.integer(sp_counts),
  prop    = as.numeric(sp_counts) / nrow(frogs)
)
class_tab$cum_prop <- cumsum(class_tab$prop)
print(class_tab, digits = 4, row.names = FALSE)

# Four views of the imbalance. Shannon entropy H is the one reused
# throughout: it is the uncertainty in the label measured in bits, so it is
# the "budget" that predictors can remove (section 3 reports each predictor's
# mutual information as a share of it). 2^H, the effective number of classes,
# is the easier number to quote: it is how many EQUALLY common species would
# carry the same uncertainty as these 18 unequal ones.
p  <- class_tab$prop
H  <- -sum(p * log2(p))
K  <- length(p)
cat(sprintf(
  paste0("\nShannon entropy H = %.4f bits (max log2(18) = %.4f, normalised %.4f)\n",
         "effective number of classes 2^H = %.2f\n",
         "Gini impurity = %.4f | imbalance ratio max/min = %.1f\n",
         "majority class share = %.4f\n"),
  H, log2(K), H / log2(K), 2^H, 1 - sum(p^2), max(p) / min(p), max(p)))

# A model with no predictors can still rank: it returns the species in
# prevalence order for every event. This is the bar every later model must
# clear. With a fixed ranking, mean reciprocal rank reduces to sum(p_i / i)
# over the prevalence-ordered classes.
# reference performance of a model that knows only the class prevalences
cat(sprintf(
  "prevalence-only baseline: Top-1 %.4f | Top-3 %.4f | Top-5 %.4f | MRR %.4f\n",
  p[1], sum(p[1:3]), sum(p[1:5]), sum(p / seq_len(K))))

# ---- Figure 1: class distribution and cumulative share -------------------
open_png("fig01_class_distribution.png", width = 11, height = 5.4)
par(mfrow = c(1, 2), mar = c(4.2, 9.5, 3.2, 1.2))
bp <- barplot(rev(class_tab$n), horiz = TRUE, col = S1, border = NA,
              names.arg = rev(sp_label), las = 1, cex.names = 0.72,
              xlim = c(0, 105000), xaxt = "n",
              main = "Species are severely imbalanced")
subtitle("247,406 single-species events, 18 classes")
axis(1, at = seq(0, 100000, 25000), labels = c("0", "25k", "50k", "75k", "100k"))
text(rev(class_tab$n) + 1500, bp, adj = 0, cex = 0.7, col = INK2,
     labels = sprintf("%s (%.1f%%)", format(rev(class_tab$n), big.mark = ","),
                      100 * rev(class_tab$prop)))
par(mar = c(4.2, 4.5, 3.2, 1.2))
plot(seq_len(K), class_tab$cum_prop, type = "s", col = S1, lwd = 2.4,
     ylim = c(0, 1), xlab = "species ranked by frequency",
     ylab = "cumulative share of events", yaxt = "n",
     main = "Half the data is two species")
subtitle("cumulative share vs a uniform 18-class reference")
axis(2, at = seq(0, 1, 0.25), labels = paste0(seq(0, 100, 25), "%"), las = 1)
lines(seq_len(K), seq_len(K) / K, col = MUTED, lty = 2, lwd = 1.4)
text(12.5, 12.5 / K - 0.06, "uniform classes", col = MUTED, cex = 0.8)
points(c(1, 5), class_tab$cum_prop[c(1, 5)], pch = 19, col = S1)
text(6.6, 0.52, sprintf("top 5 species = %.0f%%", 100 * class_tab$cum_prop[5]),
     col = INK2, cex = 0.8, adj = 0)
close_png()

banner("2b. UNIVARIATE: the predictors")

# One row per predictor: missing count, centre, spread and quartiles. Compare
# mean with median to spot the skewed ones (BIO13, BIO16, elevation and the
# monthly precipitation variable are all strongly right-skewed), which matters
# for distance- or variance-based methods but not for trees.
uni <- t(sapply(all_vars, function(v) {
  x <- as.numeric(frogs[[v]])
  q <- quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
  c(n_missing = sum(is.na(x)), mean = mean(x, na.rm = TRUE),
    sd = sd(x, na.rm = TRUE), min = min(x, na.rm = TRUE),
    q25 = q[[1]], median = q[[2]], q75 = q[[3]], max = max(x, na.rm = TRUE))
}))
print(round(as.data.frame(uni), 3))

cat("\nevents by month:\n");   print(table(frogs$month))
cat("\nevents by year:\n");    print(table(frogs$year))
cat("\nevents by weekday:\n"); print(table(weekdays(as.Date(frogs$eventDate))))

# ---- Figure 2: sampling context (effort, not ecology) --------------------
open_png("fig02_sampling_context.png", width = 12, height = 3.8)
par(mfrow = c(1, 3), mar = c(4, 4.4, 3.4, 1))
mcount <- table(factor(frogs$month, levels = 1:12))
barplot(mcount, col = S1, border = NA, names.arg = month.abb, las = 1,
        ylab = "events", main = "Effort peaks in November")
subtitle("events by calendar month")
barplot(table(frogs$year), col = S1, border = NA, las = 1, ylab = "events",
        main = "Uneven survey years")
subtitle("events by year (Nov 2017 - Nov 2023)")
hist(frogs$decimalLatitude, breaks = 60, col = S1, border = NA,
     xlab = "latitude (deg)", ylab = "events", las = 1,
     main = "Sampling is south-east heavy")
subtitle("latitude of recording events")
close_png()

# ---- Figure 3: environmental missingness by species ----------------------
open_png("fig03_missingness_by_species.png", width = 7.6, height = 4.8)
par(mar = c(4.2, 9.5, 3.4, 1.2))
mr <- na_by_species$pct_missing[match(sp_order, na_by_species$scientificName)]
barplot(rev(mr), horiz = TRUE, col = S1, border = NA, names.arg = rev(sp_label),
        las = 1, cex.names = 0.72, xlab = "% of events with missing climate values",
        main = "Missingness is species-dependent, not random")
subtitle("coastal-edge species lose the most WorldClim values")
abline(v = 100 * mean(env_na_row), col = S2, lwd = 1.8)
close_png()

# =========================================================================
# 3. BIVARIATE ANALYSIS
# =========================================================================

banner("3a. BIVARIATE: predictor vs species")

# mi_bits(): mutual information I(species ; predictor), in bits.
# The continuous predictor is cut into 10 equal-count (quantile) bins, then
# the standard sum over the contingency table of
#     p(x,y) * log2( p(x,y) / (p(x) p(y)) )
# is evaluated. Read the result as "how many of the H bits of class
# uncertainty this one predictor removes on its own"; 0 means the predictor
# and the species label are independent.
# unique() on the breaks guards against duplicated quantiles in predictors
# with heavy ties (otherwise cut() errors).
mi_bits <- function(x, y, bins = 10) {
  br <- unique(quantile(x, probs = seq(0, 1, length.out = bins + 1), na.rm = TRUE))
  xb <- cut(x, breaks = br, include.lowest = TRUE)
  tb <- table(y, xb)
  pxy <- tb / sum(tb)
  px  <- rowSums(pxy); py <- colSums(pxy)
  ind <- outer(px, py)
  sum(ifelse(pxy > 0, pxy * log2(pxy / ind), 0))
}

Hy_cc <- {
  pc <- as.numeric(table(cc$scientificName)) / nrow(cc); -sum(pc * log2(pc))
}

# For every predictor, three complementary measures of association with
# species:
#   kruskal.test - rank-based test that the 18 species differ on this
#                  predictor. With n = 242,600 the p-value is ~0 for
#                  everything, so it is the EFFECT SIZE, not the p-value,
#                  that carries information here.
#   epsilon2     - the Kruskal-Wallis effect size, (H - k + 1) / (n - k),
#                  read as the share of rank variation explained by species
#   eta2         - the same idea on the raw values, taken from a one-way
#                  ANOVA as between-group SS / total SS
#   MI           - the model-free measure defined above
# The four cyclic encodings are skipped: they are deterministic functions of
# month and day_of_year, so they would only duplicate those two rows.
signal <- do.call(rbind, lapply(setdiff(all_vars, c("month_sin", "month_cos",
                                                    "day_of_year_sin",
                                                    "day_of_year_cos")),
  function(v) {
    x  <- as.numeric(cc[[v]])
    kw <- kruskal.test(x ~ cc$scientificName)
    eps2 <- (unname(kw$statistic) - K + 1) / (nrow(cc) - K)
    fit  <- aov(x ~ cc$scientificName)
    ss   <- summary(fit)[[1]][["Sum Sq"]]
    mi   <- mi_bits(x, cc$scientificName)
    data.frame(predictor = v, kw_H = unname(kw$statistic), p_value = kw$p.value,
               epsilon2 = eps2, eta2 = ss[1] / sum(ss),
               MI_bits = mi, MI_pct_of_Hy = 100 * mi / Hy_cc)
  }))
signal <- signal[order(-signal$MI_bits), ]
cat(sprintf("H(species) on complete cases = %.4f bits\n", Hy_cc))
print(signal, digits = 4, row.names = FALSE)

# ---- Figure 9: predictor signal ranking ----------------------------------
open_png("fig09_predictor_signal.png", width = 8, height = 6.8)
par(mar = c(4.2, 9, 3.4, 1.2))
s2 <- signal[order(signal$MI_pct_of_Hy), ]
bp <- barplot(s2$MI_pct_of_Hy, horiz = TRUE, col = S1, border = NA,
              names.arg = s2$predictor, las = 1, cex.names = 0.7, xlim = c(0, 31),
              xlab = "mutual information with species, % of H(species)",
              main = "Every predictor carries species information")
subtitle("10-bin quantile discretisation; eps2 = Kruskal-Wallis effect size")
text(s2$MI_pct_of_Hy + 0.3, bp, adj = 0, cex = 0.62, col = MUTED,
     labels = sprintf("%.1f%%  eps2=%.2f", s2$MI_pct_of_Hy, s2$epsilon2))
close_png()

# ---- species x month -----------------------------------------------------
# Cramer's V rescales the chi-squared statistic onto 0-1 so that it does not
# simply grow with sample size the way X2 does; it is the comparable number.
sp_month <- table(frogs$scientificName, frogs$month)
cs <- chisq.test(sp_month)
cramers_v <- sqrt(unname(cs$statistic) /
                    (nrow(frogs) * (min(dim(sp_month)) - 1)))
cat(sprintf("\nspecies x month: X2 = %.0f, df = %d, p = %.3g, Cramer's V = %.4f\n",
            unname(cs$statistic), unname(cs$parameter), cs$p.value, cramers_v))
month_prop <- prop.table(sp_month, 1)[sp_order, ]
print(round(month_prop, 3))

# Calling date is CIRCULAR - 31 December sits next to 1 January - so the
# average date cannot be the mean of the day numbers. Instead each date is
# turned into a unit vector and averaged: the direction of the mean vector is
# the mean date, and its length circ_R measures concentration
# (0 = records spread evenly round the year, 1 = all on the same day).
ang <- 2 * pi * frogs$day_of_year / 366
circ <- frogs %>%
  mutate(s = sin(ang), c = cos(ang)) %>%
  group_by(scientificName) %>%
  summarise(circ_mean_doy = (atan2(mean(s), mean(c)) %% (2 * pi)) * 366 / (2 * pi),
            circ_R = sqrt(mean(s)^2 + mean(c)^2), .groups = "drop")
season_summary <- data.frame(
  species     = sp_order,
  peak_month  = month.abb[apply(month_prop, 1, which.max)],
  peak_share  = apply(month_prop, 1, max),
  months_80pct = apply(month_prop, 1,
                       function(r) sum(cumsum(sort(r, decreasing = TRUE)) < 0.8) + 1)
)
season_summary <- merge(season_summary, circ, by.x = "species",
                        by.y = "scientificName")
season_summary <- season_summary[match(sp_order, season_summary$species), ]
print(season_summary, digits = 3, row.names = FALSE)

# ---- Figure 4: species x month heatmap -----------------------------------
open_png("fig04_species_month_heatmap.png", width = 8.4, height = 5.6)
par(mar = c(3.2, 9.5, 3.6, 4.5))
m <- t(month_prop[rev(sp_order), ])
image(x = 1:12, y = 1:18, z = m, col = seq_blue(64), zlim = c(0, 0.38),
      axes = FALSE, xlab = "", ylab = "",
      main = "Every species has its own calling season")
subtitle("row-normalised: each row sums to 100%")
axis(1, at = 1:12, labels = month.abb, tick = FALSE, cex.axis = 0.8)
axis(2, at = 1:18, labels = rev(sp_label), las = 1, tick = FALSE, cex.axis = 0.72)
close_png()

# ---- Figure 5: seasonal small multiples ----------------------------------
overall_month <- as.numeric(prop.table(mcount))
open_png("fig05_seasonal_small_multiples.png", width = 13, height = 6.2)
par(mfrow = c(3, 6), mar = c(2.4, 2.8, 2.2, 0.8), oma = c(0, 0, 2.4, 0))
for (s in sp_order) {
  v <- as.numeric(month_prop[s, ])
  plot(1:12, v, type = "n", ylim = c(0, 0.40), xaxt = "n", yaxt = "n",
       xlab = "", ylab = "", main = short_name(s), cex.main = 0.85)
  polygon(c(1, 1:12, 12), c(0, overall_month, 0), col = GRID, border = NA)
  lines(1:12, v, col = S1, lwd = 2)
  axis(1, at = c(1, 4, 7, 10), labels = c("J", "A", "J", "O"), tick = FALSE,
       cex.axis = 0.7)
  axis(2, at = c(0, 0.2, 0.4), labels = c("0", "20%", "40%"), las = 1,
       tick = FALSE, cex.axis = 0.7)
  text(12, 0.37, sprintf("n=%s", format(sp_counts[[s]], big.mark = ",")),
       adj = 1, cex = 0.65, col = MUTED)
}
mtext("Seasonal profiles diverge sharply from the overall sampling calendar",
      outer = TRUE, adj = 0, line = 0.6, font = 2, cex = 0.95, col = INK)
close_png()

# ---- geography -----------------------------------------------------------
banner("3b. BIVARIATE: geography and environment vs species")

# great-circle distance in kilometres between two lat/long points on a
# spherical earth; used below to measure how far each record sits from its
# own species' centroid
haversine_km <- function(lat1, lon1, lat2, lon2) {
  r <- 6371; d <- pi / 180
  a <- sin((lat2 - lat1) * d / 2)^2 +
    cos(lat1 * d) * cos(lat2 * d) * sin((lon2 - lon1) * d / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}
cent <- frogs %>%
  group_by(scientificName) %>%
  summarise(n = n(), lat_med = median(decimalLatitude),
            lon_med = median(decimalLongitude),
            lat_range = diff(range(decimalLatitude)), .groups = "drop")
idx <- match(frogs$scientificName, cent$scientificName)
frogs$km_to_centroid <- haversine_km(frogs$decimalLatitude, frogs$decimalLongitude,
                                     cent$lat_med[idx], cent$lon_med[idx])
# Three complementary views of how spatially concentrated each species is:
#   median / p90 km to centroid - typical and tail distance from its centre
#   n_cells_0p5deg              - how many 0.5-degree cells it occupies
#   top_cell_share              - share of its records in its busiest cell
# A species with a small median distance and a large top-cell share is
# effectively a single-location species, which is exactly the case where
# coordinates alone can "predict" it.
spatial <- frogs %>%
  group_by(scientificName) %>%
  summarise(median_km_to_centroid = median(km_to_centroid),
            p90_km_to_centroid = quantile(km_to_centroid, 0.9),
            n_cells_0p5deg = n_distinct(cell05),
            top_cell_share = max(table(cell05)) / n(), .groups = "drop")
spatial <- merge(cent, spatial, by = "scientificName")
spatial <- spatial[match(sp_order, spatial$scientificName), ]
print(as.data.frame(spatial), digits = 4, row.names = FALSE)

# ---- Figure 6: geography overview ----------------------------------------
# Maps are drawn from an aggregate 0.5-degree grid, never from raw event
# coordinates: rule 9 of docs/eda-plan.md asks for coarse spatial
# visualisation so that sensitive locations are not published.
grid_counts <- frogs %>%
  mutate(glon = floor(decimalLongitude * 2) / 2,
         glat = floor(decimalLatitude * 2) / 2) %>%
  count(glon, glat)
open_png("fig06_geography_overview.png", width = 12, height = 5.6)
par(mfrow = c(1, 2), mar = c(4.2, 4.4, 3.6, 1.2))
cols <- seq_blue(64)[as.integer(cut(log10(grid_counts$n), 64))]
plot(grid_counts$glon, grid_counts$glat, type = "n", xlim = c(112, 155),
     ylim = c(-45, -8), xlab = "longitude", ylab = "latitude", las = 1,
     main = "Recording effort clusters on the east coast")
subtitle("0.5-degree grid, log record density")
rect(grid_counts$glon, grid_counts$glat, grid_counts$glon + 0.5,
     grid_counts$glat + 0.5, col = cols, border = NA)
plot(grid_counts$glon + 0.25, grid_counts$glat + 0.25, pch = 15, cex = 0.35,
     col = GRID, xlim = c(112, 155), ylim = c(-45, -8), las = 1,
     xlab = "longitude", ylab = "latitude",
     main = "Species occupy distinct geographic centres")
subtitle("median centroid per species, marker area ~ sample size")
points(spatial$lon_med, spatial$lat_med, pch = 19, col = S1,
       cex = sqrt(spatial$n) / 90)
text(spatial$lon_med, spatial$lat_med, labels = short_name(spatial$scientificName),
     pos = 4, cex = 0.6, col = INK2)
close_png()

# ---- Figure 7: per-species geographic small multiples --------------------
open_png("fig07_geographic_small_multiples.png", width = 13, height = 7.6)
par(mfrow = c(3, 6), mar = c(2.2, 2.4, 2.2, 0.8), oma = c(0, 0, 2.4, 0))
for (s in sp_order) {
  d <- frogs[frogs$scientificName == s, ]
  plot(grid_counts$glon + 0.25, grid_counts$glat + 0.25, pch = 15, cex = 0.3,
       col = "#e8e7e1", xlim = c(112, 155), ylim = c(-45, -8), las = 1,
       xlab = "", ylab = "", cex.axis = 0.7,
       main = sprintf("%s (n=%s)", short_name(s),
                      format(nrow(d), big.mark = ",")), cex.main = 0.85)
  gd <- d %>% mutate(glon = floor(decimalLongitude * 2) / 2,
                     glat = floor(decimalLatitude * 2) / 2) %>% count(glon, glat)
  rect(gd$glon, gd$glat, gd$glon + 0.5, gd$glat + 0.5, border = NA,
       col = seq_blue(64)[as.integer(cut(log10(gd$n), 64))])
}
mtext("Geographic ranges barely overlap for several species", outer = TRUE,
      adj = 0, line = 0.6, font = 2, cex = 0.95, col = INK)
close_png()

# ---- environmental envelopes ---------------------------------------------
env_envelope <- cc %>%
  group_by(scientificName) %>%
  summarise(BIO1_mean = mean(BIO1), BIO1_sd = sd(BIO1),
            BIO12_mean = mean(BIO12), BIO12_sd = sd(BIO12),
            BIO15_mean = mean(BIO15), elev_median = median(elevation),
            .groups = "drop")
env_envelope <- env_envelope[match(sp_order, env_envelope$scientificName), ]
print(as.data.frame(env_envelope), digits = 4, row.names = FALSE)

# ---- Figure 8: environmental boxplots ------------------------------------
open_png("fig08_environment_boxplots.png", width = 14, height = 5.8)
par(mfrow = c(1, 4), mar = c(4.2, 8.5, 3.2, 1), oma = c(0, 0, 2.4, 0))
box_panels <- list(c("BIO1", "mean annual temperature (degC)"),
                   c("BIO12", "annual precipitation (mm)"),
                   c("elevation", "elevation (m)"),
                   c("BIO15", "precipitation seasonality (CV)"))
for (bpn in box_panels) {
  v <- bpn[1]
  med <- sort(tapply(cc[[v]], cc$scientificName, median))
  dat <- split(cc[[v]], cc$scientificName)[names(med)]
  boxplot(dat, horizontal = TRUE, outline = FALSE, las = 1, col = S1,
          border = MUTED, medlwd = 1.6, boxwex = 0.66,
          names = short_name(names(med)), cex.axis = 0.7, xlab = bpn[2],
          main = v)
}
mtext("Species occupy separable climate envelopes", outer = TRUE, adj = 0,
      line = 0.6, font = 2, cex = 0.95, col = INK)
close_png()

# ---- predictor redundancy -------------------------------------------------
banner("3c. BIVARIATE: predictor vs predictor")
cmat <- cor(cc[, setdiff(all_vars, c("month_sin", "month_cos",
                                     "day_of_year_sin", "day_of_year_cos"))],
            method = "spearman")
pairs_hi <- which(abs(cmat) > 0.8 & upper.tri(cmat), arr.ind = TRUE)
cat("predictor pairs with |rho| > 0.8:", nrow(pairs_hi), "of",
    sum(upper.tri(cmat)), "\n")
print(data.frame(a = rownames(cmat)[pairs_hi[, 1]],
                 b = colnames(cmat)[pairs_hi[, 2]],
                 rho = round(cmat[pairs_hi], 3)) %>% arrange(desc(abs(rho))),
      row.names = FALSE)

open_png("fig10_predictor_correlation.png", width = 8.6, height = 7.6)
par(mar = c(6.5, 6.5, 3.6, 4.5))
image(1:ncol(cmat), 1:ncol(cmat), t(cmat[rev(seq_len(nrow(cmat))), ]),
      col = div_bred(64), zlim = c(-1, 1), axes = FALSE, xlab = "", ylab = "",
      main = "Climate predictors are heavily redundant")
subtitle("Spearman rho on complete cases")
axis(1, at = seq_len(ncol(cmat)), labels = colnames(cmat), las = 2,
     tick = FALSE, cex.axis = 0.6)
axis(2, at = seq_len(ncol(cmat)), labels = rev(rownames(cmat)), las = 1,
     tick = FALSE, cex.axis = 0.6)
close_png()

# =========================================================================
# 4. MULTIVARIATE STRUCTURE AND DIAGNOSTIC CLASSIFICATION
# =========================================================================

banner("4a. PCA of the environmental block")

# PCA on the 22 environmental predictors. scale. = TRUE is essential here
# because the BIO variables are on wildly different units (degrees C vs mm),
# and without standardising, rainfall would dominate every component purely
# through its larger numbers. The question being asked is how many genuinely
# independent environmental dimensions exist, given the redundancy found in
# section 3c.
pca <- prcomp(cc[, env_vars], center = TRUE, scale. = TRUE)
ev  <- pca$sdev^2 / sum(pca$sdev^2)
print(data.frame(PC = 1:8, prop = round(ev[1:8], 4),
                 cumulative = round(cumsum(ev)[1:8], 4)), row.names = FALSE)
print(round(pca$rotation[, 1:2], 3))

scores <- pca$x[, 1:2]
open_png("fig11_pca_small_multiples.png", width = 13, height = 7.2)
par(mfrow = c(3, 6), mar = c(2.4, 2.6, 2.2, 0.8), oma = c(0, 0, 2.4, 0))
for (s in sp_order) {
  sel <- cc$scientificName == s
  plot(scores[, 1], scores[, 2], pch = 16, cex = 0.15, col = "#e8e7e1",
       xlab = "", ylab = "", las = 1, cex.axis = 0.7,
       main = short_name(s), cex.main = 0.85)
  points(scores[sel, 1], scores[sel, 2], pch = 16, cex = 0.18,
         col = adjustcolor(S1, 0.35))
}
mtext("Species occupy different regions of environmental PC space", outer = TRUE,
      adj = 0, line = 0.6, font = 2, cex = 0.95, col = INK)
close_png()

banner("4b. Diagnostic classifier: how much class information is there?")

# Exploratory only. The purpose is to measure the joint information content
# of each predictor block, not to select or tune a final model.

# metrics(): every number the project reports, computed from a matrix of
# predicted probabilities (one row per test event, one column per species).
#   ord           - each row's species indices, most to least likely
#   rank_of_truth - position of the TRUE species in that ranking (1 = top)
#   top1/3/5      - share of events whose true species is in the top 1/3/5
#   macro_f1      - F1 computed per species then averaged UNWEIGHTED, so each
#                   of the 18 species counts equally however rare it is
#                   (this is why it is so much harsher than accuracy here)
#   mrr           - mean of 1/rank, the standard ranking metric
metrics <- function(prob, truth, classes) {
  ord  <- t(apply(prob, 1, function(r) order(r, decreasing = TRUE)))
  rank_of_truth <- apply(cbind(match(truth, classes), ord), 1,
                         function(z) which.max(z[-1] == z[1]))
  pred <- classes[ord[, 1]]
  tab  <- table(factor(truth, levels = classes), factor(pred, levels = classes))
  rec  <- diag(tab) / pmax(rowSums(tab), 1)
  prec <- diag(tab) / pmax(colSums(tab), 1)
  f1   <- ifelse(rec + prec > 0, 2 * rec * prec / (rec + prec), 0)
  c(top1 = mean(rank_of_truth == 1), top3 = mean(rank_of_truth <= 3),
    top5 = mean(rank_of_truth <= 5), macro_f1 = mean(f1),
    mrr = mean(1 / rank_of_truth))
}

# A plain random 70/30 split. Section 4c repeats the same fits with a
# spatially blocked split, which is the honest test for this dataset.
n_cc  <- nrow(cc)
train <- sample(n_cc, floor(0.7 * n_cc))
test  <- setdiff(seq_len(n_cc), train)

# fit_rf(): one random forest per predictor block.
#   probability = TRUE - return class probabilities, needed for Top-k and MRR
#   min.node.size = 5  - mild regularisation; trees would otherwise be huge
#   num.threads = 0    - use all available cores
#   importance         - impurity (Gini) importance, read in section 4d
#   seed               - reproducible bootstrap samples and split points
# NOTE for anyone reusing this: ranger's default mtry = sqrt(p) means blocks
# with very different numbers of predictors are not strictly comparable. The
# ladder below is nested and increases monotonically, so the default is fine
# here; the temporal EDA script sets mtry = p because there it is not.
fit_rf <- function(vars, tr, te) {
  rf <- ranger(x = cc[tr, vars, drop = FALSE], y = droplevels(cc$scientificName[tr]),
               num.trees = 300, min.node.size = 5, probability = TRUE,
               num.threads = 0, seed = 5003, importance = "impurity")
  pr <- predict(rf, data = cc[te, vars, drop = FALSE])$predictions
  list(model = rf, prob = pr,
       metrics = metrics(pr, as.character(cc$scientificName[te]), colnames(pr)))
}

# The ladder mirrors the model progression in README.md: each rung adds one
# block of context to the rung above, so the DIFFERENCE between consecutive
# rows is the marginal value of that block. G0 is not a rung - it is a
# contrast, showing how far coordinates alone get with no climate or season.
blocks <- list(
  "M1 season"                            = season_vars,
  "M2 season+climate"                    = c(season_vars, clim_vars),
  "M3 season+climate+elevation"          = c(season_vars, clim_vars, elev_vars),
  "M4 season+climate+elevation+lat/long" = c(season_vars, clim_vars, elev_vars, geo_vars),
  "G0 lat/long only"                     = geo_vars
)

# M0: give every test event the same prevalence vector, estimated on the
# TRAINING rows only. This is the "no predictors" reference row of the table.
prior <- as.numeric(table(cc$scientificName[train])) / length(train)
prior_prob <- matrix(prior, nrow = length(test), ncol = K, byrow = TRUE,
                     dimnames = list(NULL, levels(cc$scientificName)))
progression <- rbind(
  data.frame(model = "M0 prevalence prior", n_predictors = 0,
             t(metrics(prior_prob, as.character(cc$scientificName[test]),
                       colnames(prior_prob)))))

fits <- list()
for (nm in names(blocks)) {
  f <- fit_rf(blocks[[nm]], train, test)
  fits[[nm]] <- f
  progression <- rbind(progression,
                       data.frame(model = nm, n_predictors = length(blocks[[nm]]),
                                  t(f$metrics)))
  cat(nm, ":", sprintf("%.4f", f$metrics), "\n")
}
print(progression, digits = 4, row.names = FALSE)

# Linear benchmark on the same 30 predictors. If LDA came close to the random
# forest, the class boundaries would be essentially linear and a simpler,
# more interpretable model would be enough; the size of the gap is the
# evidence that they are not.
# linear benchmark
lda_fit <- MASS::lda(x = cc[train, unlist(blocks[["M4 season+climate+elevation+lat/long"]])],
                     grouping = droplevels(cc$scientificName[train]))
lda_pr <- predict(lda_fit,
                  newdata = cc[test, unlist(blocks[["M4 season+climate+elevation+lat/long"]])])
cat("LDA (linear benchmark):",
    sprintf("%.4f", metrics(lda_pr$posterior, as.character(cc$scientificName[test]),
                            colnames(lda_pr$posterior))), "\n")

# ---- Figure 12: model progression ----------------------------------------
open_png("fig12_model_progression.png", width = 9.5, height = 5.4)
par(mar = c(7.5, 4.4, 3.6, 1.2))
mm <- t(as.matrix(progression[, c("top1", "top3", "top5")]))
bp <- barplot(mm, beside = TRUE, col = c(S1, S2, S3), border = NA, las = 2,
              names.arg = progression$model, cex.names = 0.62, ylim = c(0, 1),
              ylab = "accuracy", main = "Adding context steadily removes class uncertainty")
subtitle("held-out 30% test split; Top-1 / Top-3 / Top-5")
legend("topleft", legend = c("Top-1", "Top-3", "Top-5"), fill = c(S1, S2, S3),
       border = NA, bty = "n", cex = 0.8)
close_png()

# ---- spatially blocked validation ----------------------------------------
banner("4c. Spatially blocked validation (geographic memorisation check)")

# Spatially blocked split: whole 0.5-degree grid cells are assigned to either
# train or test, so the model has to predict in locations it has never seen.
# Cells are shuffled, then taken in that order until they account for ~30% of
# the rows (hence the cumsum). Comparing this with the random split detects
# "geographic memorisation" - a model that has learned which species is
# recorded at each spot rather than what conditions that species likes.
cells <- unique(cc$cell05)
cells <- sample(cells)
cell_n <- table(cc$cell05)[cells]
test_cells <- cells[cumsum(cell_n) <= 0.3 * n_cc]
b_test  <- which(cc$cell05 %in% test_cells)
b_train <- setdiff(seq_len(n_cc), b_test)
cat("blocked split: train", length(b_train), "rows /", length(cells) - length(test_cells),
    "cells; test", length(b_test), "rows /", length(test_cells), "cells\n")

blocked <- do.call(rbind, lapply(c("M2 season+climate",
                                   "M4 season+climate+elevation+lat/long"),
  function(nm) {
    f <- fit_rf(blocks[[nm]], b_train, b_test)
    data.frame(model = nm, split = "spatially blocked", t(f$metrics))
  }))
random <- do.call(rbind, lapply(c("M2 season+climate",
                                  "M4 season+climate+elevation+lat/long"),
  function(nm) data.frame(model = nm, split = "random", t(fits[[nm]]$metrics))))
print(rbind(random, blocked), digits = 4, row.names = FALSE)

open_png("fig13_blocked_vs_random.png", width = 8, height = 5)
par(mar = c(5, 4.4, 3.6, 1.2))
cmp <- rbind(random$top1, blocked$top1)
bp <- barplot(cmp, beside = TRUE, col = c(S1, S2), border = NA, ylim = c(0, 1),
              names.arg = c("season+climate", "full model"), ylab = "Top-1 accuracy",
              main = "Spatial blocking removes part of the apparent skill")
subtitle("random 70/30 split vs held-out 0.5-degree grid cells")
legend("topright", legend = c("random split", "spatially blocked"),
       fill = c(S1, S2), border = NA, bty = "n", cex = 0.85)
close_png()

# ---- per-class behaviour of the full model -------------------------------
banner("4d. Per-class behaviour of the full model")

# Per-class behaviour of the full model: recall (of this species' events, how
# many were ranked first), precision (of the events predicted to be this
# species, how many really were) and Top-3 recall. The two Spearman
# correlations afterwards test the two obvious explanations for why some
# species are recognised better than others - class size and spatial spread.
f4   <- fits[["M4 season+climate+elevation+lat/long"]]
pred <- colnames(f4$prob)[apply(f4$prob, 1, which.max)]
truth <- as.character(cc$scientificName[test])
cm <- table(factor(truth, levels = sp_order), factor(pred, levels = sp_order))
# Top-3 recall per class: how often the true species is in the top 3
top3 <- apply(f4$prob, 1, function(r) colnames(f4$prob)[order(r, decreasing = TRUE)[1:3]])
in_top3 <- vapply(seq_along(truth), function(i) truth[i] %in% top3[, i], logical(1))
per_class <- data.frame(
  species     = sp_order,
  n_test      = as.integer(rowSums(cm)),
  recall      = diag(cm) / pmax(rowSums(cm), 1),
  precision   = diag(cm) / pmax(colSums(cm), 1),
  top3_recall = as.numeric(tapply(in_top3, factor(truth, levels = sp_order), mean)))
print(per_class, digits = 3, row.names = FALSE)
cat("Spearman recall vs log training size:",
    round(cor(per_class$recall, log(as.numeric(sp_counts[sp_order])),
              method = "spearman"), 3), "\n")
cat("Spearman recall vs log spatial dispersion:",
    round(cor(per_class$recall, log(spatial$median_km_to_centroid),
              method = "spearman"), 3), "\n")
# Which species get mistaken for which: the largest off-diagonal entries of
# the row-normalised confusion matrix (the diagonal is zeroed first so that
# only errors are ranked).
cat("\nlargest off-diagonal confusions (row-normalised):\n")
cmn_tab <- prop.table(cm, 1); diag(cmn_tab) <- 0
top_err <- head(sort(as.vector(cmn_tab), decreasing = TRUE), 5)
for (v in top_err) {
  ij <- which(cmn_tab == v, arr.ind = TRUE)[1, ]
  cat(sprintf("  %-28s -> %-28s %.3f\n", sp_order[ij[1]], sp_order[ij[2]], v))
}

open_png("fig14_confusion_matrix.png", width = 8.4, height = 6.4)
par(mar = c(9, 9.5, 3.6, 4.5))
cmn <- prop.table(cm, 1)
image(1:18, 1:18, t(cmn[rev(sp_order), ]), col = seq_blue(64), zlim = c(0, 1),
      axes = FALSE, xlab = "", ylab = "",
      main = "Errors concentrate in co-occurring congeners")
subtitle("row-normalised confusion matrix, full model, held-out test split")
axis(1, at = 1:18, labels = sp_label, las = 2, tick = FALSE, cex.axis = 0.62)
axis(2, at = 1:18, labels = rev(sp_label), las = 1, tick = FALSE, cex.axis = 0.62)
close_png()

open_png("fig15_recall_drivers.png", width = 11.6, height = 5)
par(mfrow = c(1, 2), mar = c(4.4, 4.4, 3.6, 1.2))
plot(as.numeric(sp_counts[sp_order]), per_class$recall, log = "x", pch = 19,
     col = S1, cex = 1.2, ylim = c(0, 1), xlab = "training events (log scale)",
     ylab = "recall", las = 1, main = "Class size does not explain recall")
subtitle("per-species recall of the full model vs class size")
text(as.numeric(sp_counts[sp_order]), per_class$recall, labels = sp_label,
     pos = 3, cex = 0.6, col = INK2)
plot(spatial$median_km_to_centroid, per_class$recall, log = "x", pch = 19,
     col = S1, cex = 1.2, ylim = c(0, 1), las = 1, ylab = "recall",
     xlab = "median distance to species centroid (km, log scale)",
     main = "Spatial compactness helps, but only weakly")
subtitle("spatially isolated species are the best recognised")
text(spatial$median_km_to_centroid, per_class$recall, labels = sp_label,
     pos = 3, cex = 0.6, col = INK2)
close_png()

# Impurity importance is convenient but is biased towards continuous
# predictors with many possible split points, so read it as a rough ordering
# rather than an exact ranking.
imp <- sort(f4$model$variable.importance, decreasing = TRUE)
print(round(head(imp, 15), 1))
open_png("fig16_variable_importance.png", width = 8, height = 5.4)
par(mar = c(4.4, 8.5, 3.6, 1.2))
top <- rev(head(imp, 15))
barplot(top, horiz = TRUE, col = S1, border = NA, las = 1, cex.names = 0.75,
        xlab = "impurity importance",
        main = "Location and temperature dominate, season is complementary")
subtitle("random forest impurity importance, full model, top 15 predictors")
close_png()

banner("DONE")
cat("figures written to", FIG_DIR, "\n")
