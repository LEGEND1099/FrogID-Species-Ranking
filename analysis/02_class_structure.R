# =========================================================================
# EDA-02: Target/class structure and imbalance
#
# Purpose:
# Describe the 18-class response distribution and quantify class imbalance
# before any modelling is performed.
#
# Input:
#   data/processed/frog_primary_multiclass.rds
#
# Outputs:
#   outputs/tables/eda02_class_distribution.csv
#   outputs/tables/eda02_imbalance_summary.csv
#   outputs/figures/EDA02/eda02_class_distribution.png
#
# No model is fitted in this script.
# =========================================================================

INPUT <- "data/processed/frog_primary_multiclass.rds"
TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA02"

if (!file.exists(INPUT)) {
  stop("Missing input: ", INPUT, call. = FALSE)
}

dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

frogs <- readRDS(INPUT)
frogs <- as.data.frame(frogs)

stopifnot(
  nrow(frogs) == 247406L,
  "scientificName" %in% names(frogs),
  length(unique(frogs$scientificName)) == 18L,
  length(unique(frogs$eventID)) == nrow(frogs)
)

# -------------------------------------------------------------------------
# Class distribution
# -------------------------------------------------------------------------

class_counts <- sort(table(frogs$scientificName), decreasing = TRUE)

class_distribution <- data.frame(
  species = names(class_counts),
  events = as.integer(class_counts),
  stringsAsFactors = FALSE
)

class_distribution$share <- class_distribution$events / nrow(frogs)
class_distribution$share_percent <- 100 * class_distribution$share
class_distribution$cumulative_share <- cumsum(class_distribution$share)
class_distribution$cumulative_percent <-
  100 * class_distribution$cumulative_share

# -------------------------------------------------------------------------
# Imbalance summaries
# -------------------------------------------------------------------------

p <- class_distribution$share
K <- length(p)

shannon_entropy <- -sum(p * log2(p))
maximum_entropy <- log2(K)
normalised_entropy <- shannon_entropy / maximum_entropy
effective_classes <- 2^shannon_entropy
gini_impurity <- 1 - sum(p^2)

imbalance_summary <- data.frame(
  measure = c(
    "events",
    "classes",
    "largest_class",
    "largest_class_share_percent",
    "smallest_class",
    "smallest_class_share_percent",
    "largest_to_smallest_ratio",
    "top_3_classes_share_percent",
    "top_5_classes_share_percent",
    "shannon_entropy_bits",
    "maximum_entropy_bits",
    "normalised_entropy",
    "effective_number_of_classes",
    "gini_impurity"
  ),
  value = c(
    as.character(nrow(frogs)),
    as.character(K),
    class_distribution$species[1],
    sprintf("%.4f", class_distribution$share_percent[1]),
    class_distribution$species[K],
    sprintf("%.4f", class_distribution$share_percent[K]),
    sprintf("%.4f",
            class_distribution$events[1] /
              class_distribution$events[K]),
    sprintf("%.4f", 100 * sum(p[1:3])),
    sprintf("%.4f", 100 * sum(p[1:5])),
    sprintf("%.4f", shannon_entropy),
    sprintf("%.4f", maximum_entropy),
    sprintf("%.4f", normalised_entropy),
    sprintf("%.4f", effective_classes),
    sprintf("%.4f", gini_impurity)
  ),
  stringsAsFactors = FALSE
)

write.csv(
  class_distribution,
  file.path(TABLE_DIR, "eda02_class_distribution.csv"),
  row.names = FALSE
)

write.csv(
  imbalance_summary,
  file.path(TABLE_DIR, "eda02_imbalance_summary.csv"),
  row.names = FALSE
)

# -------------------------------------------------------------------------
# Figure: class distribution + cumulative share
# -------------------------------------------------------------------------

png(
  file.path(FIG_DIR, "eda02_class_distribution.png"),
  width = 2200,
  height = 1150,
  res = 180
)

par(mfrow = c(1, 2))

bar_positions <- barplot(
  rev(class_distribution$events),
  names.arg = rev(class_distribution$species),
  horiz = TRUE,
  las = 1,
  cex.names = 0.65,
  border = NA,
  xlab = "Recording events",
  main = "Class distribution"
)

plot(
  seq_len(K),
  class_distribution$cumulative_percent,
  type = "s",
  lwd = 2,
  pch = 19,
  ylim = c(0, 100),
  xlab = "Species ranked by frequency",
  ylab = "Cumulative share of events (%)",
  main = "Cumulative class concentration"
)

abline(h = c(50, 75, 90), lty = 3)

dev.off()

# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-02 CLASS STRUCTURE\n")
cat("============================================================\n")

cat("\nClass distribution:\n")
print(class_distribution, row.names = FALSE, digits = 4)

cat("\nImbalance summary:\n")
print(imbalance_summary, row.names = FALSE)

cat(sprintf(
  paste0(
    "\nLargest class share: %.1f%%\n",
    "Largest/smallest ratio: %.1fx\n",
    "Top 3 classes: %.1f%% of events\n",
    "Top 5 classes: %.1f%% of events\n",
    "Effective number of equally common classes: %.2f of 18\n"
  ),
  class_distribution$share_percent[1],
  class_distribution$events[1] / class_distribution$events[K],
  100 * sum(p[1:3]),
  100 * sum(p[1:5]),
  effective_classes
))

cat("\nEDA-02 COMPLETE\n")
cat("No model was fitted and no data were modified or balanced.\n")