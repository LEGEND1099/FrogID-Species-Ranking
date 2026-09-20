# =========================================================================
# EDA-08: Conservation and geoprivacy
#
# Purpose:
# Quantify what the public FrogID release permits and prevents for confirmed
# EPBC-listed taxa, using only the existing non-sensitive aggregate outputs
# prepared by the certified data pipeline.
#
# Questions:
#   1. How does raw-to-clean retention differ by conservation group?
#   2. Which non-exclusive QC/privacy conditions affect confirmed listed events?
#   3. At what stage does the sequential QC flow remove those events?
#   4. How are confirmed listed recordings distributed across EPBC categories?
#   5. Which target taxa have confirmed or unresolved EPBC matching status?
#
# Inputs:
#   outputs/tables/conservation_species_retention.csv
#   outputs/tables/conservation_category_retention.csv
#   outputs/tables/conservation_group_retention.csv
#   outputs/tables/conservation_qc_exclusion_summary.csv
#
# This script never reads raw point coordinates and never writes event IDs,
# observer IDs or exact locations.
#
# Non-exclusive QC reason counts must not be added together. Sequential counts
# are order-dependent and describe the project's QC order, not a causal reason.
# =========================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

SPECIES_FILE <- "outputs/tables/conservation_species_retention.csv"
CATEGORY_FILE <- "outputs/tables/conservation_category_retention.csv"
GROUP_FILE <- "outputs/tables/conservation_group_retention.csv"
QC_FILE <- "outputs/tables/conservation_qc_exclusion_summary.csv"

TABLE_DIR <- "outputs/tables"
FIG_DIR <- "outputs/figures/EDA08"

input_files <- c(
  SPECIES_FILE,
  CATEGORY_FILE,
  GROUP_FILE,
  QC_FILE
)

missing_files <- input_files[
  !file.exists(input_files)
]

if (length(missing_files)) {
  stop(
    "Missing EDA-08 input(s): ",
    paste(missing_files, collapse = ", "),
    call. = FALSE
  )
}

dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIG_DIR, recursive = TRUE, showWarnings = FALSE)

species <- read.csv(
  SPECIES_FILE,
  stringsAsFactors = FALSE,
  na.strings = c("NA", "")
)

category <- read.csv(
  CATEGORY_FILE,
  stringsAsFactors = FALSE,
  na.strings = c("NA", "")
)

groups <- read.csv(
  GROUP_FILE,
  stringsAsFactors = FALSE,
  na.strings = c("NA", "")
)

qc <- read.csv(
  QC_FILE,
  stringsAsFactors = FALSE,
  na.strings = c("NA", "")
)

# -------------------------------------------------------------------------
# 0. Structural checks
# -------------------------------------------------------------------------

required_species <- c(
  "scientificName",
  "epbc_match_status",
  "epbc_listed",
  "epbc_category",
  "conservation_group",
  "selected_for_model",
  "raw_events",
  "raw_single_species_events",
  "open_location_events",
  "precision_eligible_events",
  "no_generalization_events",
  "clean_events",
  "clean_single_species_events",
  "retention_raw_to_clean_percent"
)

required_category <- c(
  "conservation_group",
  "epbc_category",
  "species_count",
  "raw_events",
  "clean_events",
  "raw_single_species_events",
  "clean_single_species_events",
  "retention_percent",
  "selected_species_count",
  "event_counting"
)

required_group <- c(
  "scope",
  "species_count",
  "raw_events",
  "clean_events",
  "raw_single_species_events",
  "clean_single_species_events",
  "retention_percent",
  "selected_species_count",
  "event_counting"
)

required_qc <- c(
  "scope",
  "count_type",
  "reason",
  "events",
  "denominator_events",
  "percent_events",
  "stage_order",
  "events_remaining",
  "scope_overlap"
)

stopifnot(
  all(required_species %in% names(species)),
  all(required_category %in% names(category)),
  all(required_group %in% names(groups)),
  all(required_qc %in% names(qc)),
  !anyDuplicated(species$scientificName)
)

listed_group_name <- "confirmed_EPBC_listed"
other_group_name <- "not_confirmed_listed_or_unresolved"

all_group <- groups %>%
  filter(scope == "all_events")

listed_group <- groups %>%
  filter(scope == listed_group_name)

other_group <- groups %>%
  filter(scope == other_group_name)

stopifnot(
  nrow(all_group) == 1L,
  nrow(listed_group) == 1L,
  nrow(other_group) == 1L
)

listed_species <- species %>%
  filter(conservation_group == listed_group_name)

unresolved_species <- species %>%
  filter(
    epbc_match_status ==
      "unresolved_listed_subspecies_only"
  )

selected_species <- species %>%
  filter(selected_for_model %in% TRUE)

stopifnot(
  nrow(listed_species) ==
    listed_group$species_count,
  all(
    listed_species$epbc_listed %in% TRUE
  )
)

# -------------------------------------------------------------------------
# 1. Conservation-group retention
# -------------------------------------------------------------------------

group_retention_summary <- groups %>%
  filter(
    scope %in% c(
      listed_group_name,
      other_group_name
    )
  ) %>%
  transmute(
    conservation_group = scope,
    species_count,
    raw_events,
    clean_events,
    raw_single_species_events,
    clean_single_species_events,
    retention_percent,
    selected_species_count
  )

group_retention_summary$group_label <- ifelse(
  group_retention_summary$conservation_group ==
    listed_group_name,
  "Confirmed EPBC-listed",
  "Other / unresolved"
)

# Because the two conservation scopes may both contain the same mixed-taxon
# recording, inclusion-exclusion is used to quantify their event overlap.
listed_other_scope_overlap_events <-
  listed_group$raw_events +
  other_group$raw_events -
  all_group$raw_events

stopifnot(
  listed_other_scope_overlap_events >= 0
)

# -------------------------------------------------------------------------
# 2. Confirmed-listed EPBC category summary
# -------------------------------------------------------------------------

listed_category_summary <- category %>%
  filter(
    conservation_group == listed_group_name
  ) %>%
  arrange(epbc_category)

# In the current prepared data the confirmed-listed taxa occur in exactly the
# Endangered and Vulnerable categories. With two categories, inclusion-
# exclusion gives the exact number of recordings represented in both category
# scopes.
stopifnot(
  nrow(listed_category_summary) == 2L,
  setequal(
    listed_category_summary$epbc_category,
    c("Endangered", "Vulnerable")
  )
)

endangered_vulnerable_overlap_events <-
  sum(listed_category_summary$raw_events) -
  listed_group$raw_events

stopifnot(
  endangered_vulnerable_overlap_events >= 0
)

# -------------------------------------------------------------------------
# 3. Non-exclusive QC/privacy reasons
# -------------------------------------------------------------------------

key_reason_order <- c(
  "uncertainty_over_1000m",
  "obscured_geoprivacy",
  "generalised_location"
)

listed_qc_reasons <- qc %>%
  filter(
    scope == listed_group_name,
    count_type == "non_exclusive",
    reason %in% key_reason_order
  ) %>%
  mutate(
    reason = factor(
      reason,
      levels = key_reason_order
    )
  ) %>%
  arrange(reason)

stopifnot(
  nrow(listed_qc_reasons) == 3L,
  all(
    listed_qc_reasons$denominator_events ==
      listed_group$raw_events
  )
)

listed_qc_reason_summary <- listed_qc_reasons %>%
  transmute(
    reason = as.character(reason),
    events,
    denominator_events,
    percent_events
  )

listed_qc_reason_summary$reason_label <- c(
  "Coordinate uncertainty >1 km",
  "Obscured geoprivacy",
  "Generalised location"
)[
  match(
    listed_qc_reason_summary$reason,
    key_reason_order
  )
]

# If every listed event satisfies each of the three conditions, then every
# listed event necessarily lies in their three-way intersection.
all_listed_fail_each_key_reason <- all(
  listed_qc_reason_summary$events ==
    listed_qc_reason_summary$denominator_events
)

listed_three_way_overlap_events <- if (
  all_listed_fail_each_key_reason
) {
  listed_group$raw_events
} else {
  NA_real_
}

# -------------------------------------------------------------------------
# 4. Sequential QC flow for confirmed-listed events
# -------------------------------------------------------------------------

listed_sequential_flow <- qc %>%
  filter(
    scope == listed_group_name,
    count_type == "sequential"
  ) %>%
  arrange(stage_order) %>%
  transmute(
    stage_order,
    stage = reason,
    events_excluded_at_stage = events,
    denominator_events,
    percent_of_raw_events_excluded_at_stage =
      percent_events,
    events_remaining
  )

stopifnot(
  nrow(listed_sequential_flow) > 0L,
  listed_sequential_flow$events_remaining[
    nrow(listed_sequential_flow)
  ] == listed_group$clean_events
)

# -------------------------------------------------------------------------
# 5. Non-sensitive special-taxon summary
# -------------------------------------------------------------------------

special_taxa_summary <- species %>%
  filter(
    conservation_group == listed_group_name |
      epbc_match_status ==
        "unresolved_listed_subspecies_only"
  ) %>%
  transmute(
    scientificName,
    epbc_match_status,
    epbc_listed,
    epbc_category,
    selected_for_model,
    raw_events,
    raw_single_species_events,
    open_location_events,
    precision_eligible_events,
    no_generalization_events,
    clean_events,
    clean_single_species_events,
    retention_raw_to_clean_percent
  ) %>%
  arrange(
    desc(epbc_listed %in% TRUE),
    epbc_category,
    scientificName
  )

selected_confirmed_listed_count <- sum(
  selected_species$conservation_group ==
    listed_group_name
)

selected_unresolved_subspecies_count <- sum(
  selected_species$epbc_match_status ==
    "unresolved_listed_subspecies_only"
)

# -------------------------------------------------------------------------
# 6. Compact conservation summary
# -------------------------------------------------------------------------

conservation_summary <- data.frame(
  measure = c(
    "frogid_taxa_in_retention_table",
    "confirmed_epbc_listed_taxa",
    "unresolved_listed_subspecies_only_taxa",
    "selected_target_taxa",
    "selected_confirmed_epbc_listed_taxa",
    "selected_unresolved_listed_subspecies_only_taxa",
    "all_raw_recording_events",
    "all_clean_recording_events",
    "confirmed_listed_raw_recording_events",
    "confirmed_listed_clean_recording_events",
    "confirmed_listed_retention_percent",
    "confirmed_listed_raw_single_species_events",
    "confirmed_listed_clean_single_species_events",
    "other_unresolved_raw_recording_events",
    "other_unresolved_clean_recording_events",
    "other_unresolved_retention_percent",
    "listed_other_scope_overlap_events",
    "endangered_vulnerable_category_overlap_events",
    "listed_events_uncertainty_over_1000m",
    "listed_events_obscured_geoprivacy",
    "listed_events_generalised_location",
    "listed_events_inferred_three_way_overlap"
  ),
  value = c(
    nrow(species),
    nrow(listed_species),
    nrow(unresolved_species),
    nrow(selected_species),
    selected_confirmed_listed_count,
    selected_unresolved_subspecies_count,
    all_group$raw_events,
    all_group$clean_events,
    listed_group$raw_events,
    listed_group$clean_events,
    listed_group$retention_percent,
    listed_group$raw_single_species_events,
    listed_group$clean_single_species_events,
    other_group$raw_events,
    other_group$clean_events,
    other_group$retention_percent,
    listed_other_scope_overlap_events,
    endangered_vulnerable_overlap_events,
    listed_qc_reason_summary$events[
      listed_qc_reason_summary$reason ==
        "uncertainty_over_1000m"
    ],
    listed_qc_reason_summary$events[
      listed_qc_reason_summary$reason ==
        "obscured_geoprivacy"
    ],
    listed_qc_reason_summary$events[
      listed_qc_reason_summary$reason ==
        "generalised_location"
    ],
    listed_three_way_overlap_events
  ),
  stringsAsFactors = FALSE
)

# -------------------------------------------------------------------------
# 7. Figures
# -------------------------------------------------------------------------

# Figure 1: raw-to-clean retention by conservation group.
plot_group_retention <- group_retention_summary

plot_group_retention$group_label <- factor(
  plot_group_retention$group_label,
  levels = c(
    "Confirmed EPBC-listed",
    "Other / unresolved"
  )
)

p_retention <- ggplot(
  plot_group_retention,
  aes(
    x = group_label,
    y = retention_percent
  )
) +
  geom_col(
    width = 0.65
  ) +
  geom_text(
    aes(
      label = sprintf(
        "%.1f%%",
        retention_percent
      )
    ),
    vjust = -0.5,
    size = 4
  ) +
  coord_cartesian(
    ylim = c(0, 105)
  ) +
  labs(
    title = "Raw-to-clean event retention by conservation group",
    subtitle = "Whole-event spatial QC used by the project",
    x = NULL,
    y = "Events retained (%)"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda08_group_retention.png"
  ),
  p_retention,
  width = 8,
  height = 6,
  dpi = 180
)

# Figure 2: non-exclusive listed-event QC/privacy conditions.
plot_qc <- listed_qc_reason_summary

plot_qc$reason_label <- factor(
  plot_qc$reason_label,
  levels = rev(
    c(
      "Coordinate uncertainty >1 km",
      "Obscured geoprivacy",
      "Generalised location"
    )
  )
)

p_qc <- ggplot(
  plot_qc,
  aes(
    x = percent_events,
    y = reason_label
  )
) +
  geom_col(
    width = 0.65
  ) +
  geom_text(
    aes(
      label = sprintf(
        "%.1f%%",
        percent_events
      )
    ),
    hjust = -0.15,
    size = 4
  ) +
  coord_cartesian(
    xlim = c(0, 105)
  ) +
  labs(
    title = "QC and privacy conditions among confirmed listed events",
    subtitle = "Non-exclusive reasons; the same recording may satisfy multiple conditions",
    x = "Confirmed listed events affected (%)",
    y = NULL
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda08_listed_qc_reasons.png"
  ),
  p_qc,
  width = 9,
  height = 5.5,
  dpi = 180
)

# Figure 3: distinct raw event unions within EPBC categories.
plot_category <- listed_category_summary

plot_category$epbc_category <- factor(
  plot_category$epbc_category,
  levels = c(
    "Endangered",
    "Vulnerable"
  )
)

p_category <- ggplot(
  plot_category,
  aes(
    x = epbc_category,
    y = raw_events
  )
) +
  geom_col(
    width = 0.65
  ) +
  geom_text(
    aes(
      label = paste0(
        format(
          raw_events,
          big.mark = ","
        ),
        "\n(",
        species_count,
        " taxa)"
      )
    ),
    vjust = -0.35,
    size = 3.7
  ) +
  scale_y_continuous(
    expand = expansion(
      mult = c(0, 0.12)
    )
  ) +
  labs(
    title = "Raw FrogID recordings containing confirmed EPBC-listed taxa",
    subtitle = "Distinct event unions within category; categories may overlap",
    x = "EPBC category",
    y = "Raw recording events"
  ) +
  theme_minimal()

ggsave(
  file.path(
    FIG_DIR,
    "eda08_listed_category_events.png"
  ),
  p_category,
  width = 8,
  height = 6,
  dpi = 180
)

# -------------------------------------------------------------------------
# 8. Write non-sensitive aggregate outputs
# -------------------------------------------------------------------------

outputs <- list(
  eda08_conservation_summary =
    conservation_summary,
  eda08_group_retention_summary =
    group_retention_summary,
  eda08_listed_category_summary =
    listed_category_summary,
  eda08_listed_qc_reason_summary =
    listed_qc_reason_summary,
  eda08_listed_sequential_qc_flow =
    listed_sequential_flow,
  eda08_special_taxa_summary =
    special_taxa_summary
)

sensitive_columns <- c(
  "eventID",
  "occurrenceID",
  "recordedBy",
  "decimalLatitude",
  "decimalLongitude"
)

for (name in names(outputs)) {

  stopifnot(
    !any(
      sensitive_columns %in%
        names(outputs[[name]])
    )
  )

  write.csv(
    outputs[[name]],
    file.path(
      TABLE_DIR,
      paste0(name, ".csv")
    ),
    row.names = FALSE,
    na = "NA"
  )
}

# -------------------------------------------------------------------------
# 9. Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-08 CONSERVATION AND GEOPRIVACY\n")
cat("============================================================\n")

cat("\nCompact conservation summary:\n")
print(
  conservation_summary,
  row.names = FALSE,
  digits = 6
)

cat("\nConservation-group retention:\n")
print(
  group_retention_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nConfirmed listed EPBC categories:\n")
print(
  listed_category_summary[
    ,
    c(
      "epbc_category",
      "species_count",
      "raw_events",
      "clean_events",
      "raw_single_species_events",
      "clean_single_species_events",
      "retention_percent"
    )
  ],
  row.names = FALSE,
  digits = 5
)

cat("\nConfirmed listed non-exclusive QC/privacy reasons:\n")
print(
  listed_qc_reason_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nConfirmed listed sequential QC flow:\n")
print(
  listed_sequential_flow,
  row.names = FALSE,
  digits = 5
)

cat("\nConfirmed listed and unresolved-subspecific taxa:\n")
print(
  special_taxa_summary,
  row.names = FALSE,
  digits = 5
)

cat("\nImportant counting notes:\n")
cat(
  "- Conservation scopes can overlap when one recording contains taxa from multiple groups.\n"
)
cat(
  "- EPBC category event counts are distinct within category and can overlap across categories.\n"
)
cat(
  "- Non-exclusive QC reason counts overlap and must not be added.\n"
)
cat(
  "- Sequential QC exclusions depend on stage order; a zero at a later stage can mean no events remained to test there.\n"
)

cat("\nEDA-08 COMPLETE\n")
cat(
  paste0(
    "No exact locations were read or written. No classifier was fitted, ",
    "and geoprivacy was treated as a protection mechanism rather than a data error.\n"
  )
)
