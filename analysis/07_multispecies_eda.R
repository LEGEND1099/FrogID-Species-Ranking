# EDA-07: Multi-species recording structure, co-occurrence and Recall@k design
#
# Purpose:
# Understand whether a classifier trained on single-species recordings can be
# meaningfully evaluated as a ranked retrieval system on the multi-species
# recordings, and quantify what that evaluation can and cannot measure.
#
# Questions addressed (docs/eda-plan.md, EDA-07):
#   - How many species occur per recording?
#   - Which species combinations are common?
#   - Which target classes co-occur most often?
#   - How representative are the Recall@k-eligible events?
#   - How do eligible events differ from partial-overlap events?
#   - Are some target species disproportionately seen in multi-species events?
#
# Inputs are read-only. This script does NOT clean, impute, scale, filter or
# otherwise modify anything under data/processed/.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(ggplot2)
})

set.seed(5003)

# -------------------------------------------------------------------------
# Inputs
# -------------------------------------------------------------------------

paths <- c(
  primary = "data/processed/frog_primary_multiclass.rds",
  multispecies = "data/processed/frog_multispecies_extension.rds"
)

missing_files <- paths[!file.exists(paths)]

if (length(missing_files)) {
  stop(
    "Missing processed EDA input(s): ",
    paste(missing_files, collapse = ", "),
    "\nRun the certified data-preparation pipeline first.",
    call. = FALSE
  )
}

primary <- readRDS(paths["primary"])
multi <- readRDS(paths["multispecies"])

tables_dir <- "outputs/tables"
figures_dir <- "outputs/figures/EDA07"

dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)


# -------------------------------------------------------------------------
# Certified-structure guards
# -------------------------------------------------------------------------

vocabulary <- sort(unique(primary$scientificName))

environmental_features <- c(
  paste0("BIO", 1:19),
  "elevation",
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

stopifnot(
  nrow(primary) == 247406L,
  nrow(multi) == 213675L,
  length(vocabulary) == 18L,

  # The extension is a disjoint set of recordings, not duplicated training rows.
  length(intersect(primary$eventID, multi$eventID)) == 0L,

  # Every extension event really is multi-species with at least one target.
  all(multi$n_species >= 2L),
  all(multi$n_selected_species >= 1L),

  # List columns must agree with their cached lengths.
  identical(lengths(multi$species_list), multi$n_species),
  identical(lengths(multi$selected_species_list), multi$n_selected_species),

  # Eligibility is exactly "every detected species is in the 18-class vocabulary".
  identical(
    multi$recall_at_k_eligible,
    multi$n_selected_species == multi$n_species
  ),
  sum(multi$recall_at_k_eligible) == 127322L
)

# selected_species_list must be the vocabulary intersection of species_list.
stopifnot(
  all(unlist(multi$selected_species_list) %in% vocabulary)
)


# -------------------------------------------------------------------------
# Long-form helpers
#
# One row per (event, species). `species_long` keeps every detected species,
# `selected_long` keeps only the 18 target classes.
# -------------------------------------------------------------------------

species_long <- tibble(
  row = rep(seq_len(nrow(multi)), multi$n_species),
  eventID = rep(multi$eventID, multi$n_species),
  species = unlist(multi$species_list, use.names = FALSE),
  n_species = rep(multi$n_species, multi$n_species),
  eligible = rep(multi$recall_at_k_eligible, multi$n_species)
)

selected_long <- tibble(
  row = rep(seq_len(nrow(multi)), multi$n_selected_species),
  eventID = rep(multi$eventID, multi$n_selected_species),
  species = unlist(multi$selected_species_list, use.names = FALSE),
  n_species = rep(multi$n_species, multi$n_selected_species),
  n_selected_species = rep(multi$n_selected_species, multi$n_selected_species),
  eligible = rep(multi$recall_at_k_eligible, multi$n_selected_species)
)

stopifnot(
  nrow(species_long) == sum(multi$n_species),
  nrow(selected_long) == sum(multi$n_selected_species)
)

# Species ordered by primary-cohort frequency; reused for consistent axes.
primary_counts <- primary |>
  count(species = scientificName, name = "primary_events") |>
  arrange(desc(primary_events))

species_by_frequency <- primary_counts$species


# -------------------------------------------------------------------------
# Output 1: species-per-event distribution
#
# Three related counts per event: total detected species, target species, and
# non-vocabulary species (the ones that make an event Recall@k-ineligible).
# -------------------------------------------------------------------------

count_distribution <- function(values, measure) {
  tibble(count = values) |>
    count(count, name = "events") |>
    arrange(count) |>
    mutate(
      measure = measure,
      percent = 100 * events / sum(events),
      cumulative_percent = cumsum(percent)
    ) |>
    relocate(measure)
}

species_per_event <- bind_rows(
  count_distribution(multi$n_species, "species_detected"),
  count_distribution(multi$n_selected_species, "target_species_detected"),
  count_distribution(
    multi$n_species - multi$n_selected_species,
    "non_vocabulary_species_detected"
  )
)


# -------------------------------------------------------------------------
# Output 2: Recall@k eligibility overview
# -------------------------------------------------------------------------

eligibility_by_size <- multi |>
  count(n_species, recall_at_k_eligible, name = "events") |>
  pivot_wider(
    names_from = recall_at_k_eligible,
    values_from = events,
    values_fill = 0L,
    names_prefix = "eligible_"
  ) |>
  rename(eligible = eligible_TRUE, ineligible = eligible_FALSE) |>
  mutate(
    events = eligible + ineligible,
    eligible_percent = 100 * eligible / events
  ) |>
  select(n_species, events, eligible, ineligible, eligible_percent) |>
  arrange(n_species)


# -------------------------------------------------------------------------
# Output 3: Recall@k ceiling
#
# An event with n detected species cannot have all of them recovered by a
# top-k list when k < n, however good the model is. This is the ceiling the
# evaluation must be read against -- it is a property of the data, not of any
# model. Computed over Recall@k-eligible events, where every detected species
# is predictable in principle.
# -------------------------------------------------------------------------

eligible_sizes <- multi$n_species[multi$recall_at_k_eligible]

recall_at_k_ceiling <- tibble(k = 1:10) |>
  rowwise() |>
  mutate(
    eligible_events = length(eligible_sizes),
    events_fully_recoverable = sum(eligible_sizes <= k),
    percent_fully_recoverable = 100 * mean(eligible_sizes <= k),
    max_mean_recall_at_k = mean(pmin(k, eligible_sizes) / eligible_sizes)
  ) |>
  ungroup()


# -------------------------------------------------------------------------
# Output 4: per-target-species participation and eligibility
#
# Answers "are some target species disproportionately observed in
# multi-species events" and "Recall@k eligibility by species".
# -------------------------------------------------------------------------

multi_counts <- selected_long |>
  group_by(species) |>
  summarise(
    multi_events = n(),
    eligible_multi_events = sum(eligible),
    mean_species_per_event = mean(n_species),
    mean_target_partners = mean(n_selected_species - 1),
    .groups = "drop"
  )

species_participation <- primary_counts |>
  left_join(multi_counts, by = "species") |>
  mutate(
    across(
      c(multi_events, eligible_multi_events),
      \(x) coalesce(x, 0L)
    ),
    total_events = primary_events + multi_events,
    multi_share_percent = 100 * multi_events / total_events,
    eligibility_rate_percent = 100 * eligible_multi_events / multi_events,
    # Share of the whole cohort, to show whether ranking evaluation would be
    # dominated by the same species that dominate training.
    primary_share_percent = 100 * primary_events / sum(primary_events),
    multi_appearance_share_percent = 100 * multi_events / sum(multi_events)
  ) |>
  arrange(desc(primary_events))


# -------------------------------------------------------------------------
# Output 5: target-species co-occurrence
#
# Incidence matrix over the 18 target classes, then pairwise co-occurrence
# counts and Jaccard association.
# -------------------------------------------------------------------------

incidence <- matrix(
  0,
  nrow = nrow(multi),
  ncol = length(vocabulary),
  dimnames = list(NULL, vocabulary)
)

incidence[cbind(selected_long$row, match(selected_long$species, vocabulary))] <- 1

stopifnot(identical(as.integer(rowSums(incidence)), multi$n_selected_species))

cooccurrence_counts <- crossprod(incidence)
species_totals <- diag(cooccurrence_counts)

# Jaccard: shared events / events containing either species.
union_counts <- outer(species_totals, species_totals, "+") - cooccurrence_counts
jaccard <- cooccurrence_counts / union_counts
diag(jaccard) <- NA_real_

pair_index <- which(upper.tri(cooccurrence_counts), arr.ind = TRUE)

cooccurrence_pairs <- tibble(
  species_a = vocabulary[pair_index[, "row"]],
  species_b = vocabulary[pair_index[, "col"]],
  cooccurring_events = as.integer(cooccurrence_counts[pair_index]),
  events_with_a = as.integer(species_totals[pair_index[, "row"]]),
  events_with_b = as.integer(species_totals[pair_index[, "col"]]),
  jaccard = jaccard[pair_index]
) |>
  mutate(
    percent_of_a = 100 * cooccurring_events / events_with_a,
    percent_of_b = 100 * cooccurring_events / events_with_b
  ) |>
  arrange(desc(cooccurring_events))


# -------------------------------------------------------------------------
# Output 6: most common species combinations
# -------------------------------------------------------------------------

combination_label <- function(species_lists) {
  vapply(
    species_lists,
    function(x) paste(sort(x), collapse = " + "),
    character(1)
  )
}

top_combinations <- bind_rows(
  tibble(
    combination_type = "all_detected_species",
    combination = combination_label(multi$species_list),
    n_species = multi$n_species,
    eligible = multi$recall_at_k_eligible
  ),
  tibble(
    combination_type = "target_species_only",
    combination = combination_label(multi$selected_species_list),
    n_species = multi$n_selected_species,
    eligible = multi$recall_at_k_eligible
  )
) |>
  group_by(combination_type, combination, n_species) |>
  summarise(events = n(), eligible_events = sum(eligible), .groups = "drop") |>
  group_by(combination_type) |>
  mutate(percent_of_extension = 100 * events / nrow(multi)) |>
  slice_max(events, n = 30, with_ties = FALSE) |>
  arrange(combination_type, desc(events)) |>
  ungroup()


# -------------------------------------------------------------------------
# Output 7: non-vocabulary partner species
#
# These are the species that cause the 86,353 partial-overlap events. They are
# detected in the recording but are outside the 18-class vocabulary, so a
# ranked prediction can never recover them.
# -------------------------------------------------------------------------

nonvocabulary_partners <- species_long |>
  filter(!species %in% vocabulary) |>
  count(species, name = "events") |>
  mutate(
    percent_of_extension = 100 * events / nrow(multi),
    percent_of_ineligible = 100 * events / sum(!multi$recall_at_k_eligible)
  ) |>
  arrange(desc(events))


# -------------------------------------------------------------------------
# Output 8: eligible vs partial-overlap comparison
#
# Establishes whether the 127,322 evaluable events are a representative
# subsample or a biased one. Aggregate summaries only -- no exact locations.
# -------------------------------------------------------------------------

comparison_variables <- c(
  "decimalLatitude",
  "decimalLongitude",
  "day_of_year",
  "elevation",
  "BIO1",
  "BIO12",
  "climatological_tavg_event_month",
  "climatological_prec_event_month"
)

summarise_cohort <- function(data, cohort) {
  data |>
    select(all_of(comparison_variables)) |>
    pivot_longer(everything(), names_to = "variable", values_to = "value") |>
    group_by(variable) |>
    summarise(
      cohort = cohort,
      n = sum(!is.na(value)),
      missing = sum(is.na(value)),
      median = median(value, na.rm = TRUE),
      q25 = quantile(value, 0.25, na.rm = TRUE),
      q75 = quantile(value, 0.75, na.rm = TRUE),
      mean = mean(value, na.rm = TRUE),
      sd = sd(value, na.rm = TRUE),
      .groups = "drop"
    ) |>
    relocate(cohort)
}

eligible_vs_ineligible <- bind_rows(
  summarise_cohort(filter(multi, recall_at_k_eligible), "recall_at_k_eligible"),
  summarise_cohort(filter(multi, !recall_at_k_eligible), "partial_overlap")
) |>
  arrange(variable, cohort)


# -------------------------------------------------------------------------
# Output 9: primary vs multi-species cohort comparison
#
# The extension is only a fair external evaluation set if its seasonal and
# environmental context resembles the training cohort.
# -------------------------------------------------------------------------

cohort_comparison <- bind_rows(
  summarise_cohort(primary, "primary_single_species"),
  summarise_cohort(multi, "multispecies_all"),
  summarise_cohort(filter(multi, recall_at_k_eligible), "multispecies_eligible")
) |>
  arrange(variable, cohort)

monthly_share <- bind_rows(
  tibble(cohort = "primary_single_species", month = primary$month),
  tibble(cohort = "multispecies_all", month = multi$month),
  tibble(
    cohort = "multispecies_eligible",
    month = multi$month[multi$recall_at_k_eligible]
  )
) |>
  count(cohort, month, name = "events") |>
  group_by(cohort) |>
  mutate(percent_of_cohort = 100 * events / sum(events)) |>
  ungroup() |>
  arrange(cohort, month)

cohort_overview <- tibble(
  cohort = c(
    "primary_single_species",
    "multispecies_all",
    "multispecies_eligible",
    "multispecies_partial_overlap"
  ),
  events = c(
    nrow(primary),
    nrow(multi),
    sum(multi$recall_at_k_eligible),
    sum(!multi$recall_at_k_eligible)
  ),
  rows_with_environmental_NA = c(
    sum(!complete.cases(primary[environmental_features])),
    sum(!complete.cases(multi[environmental_features])),
    sum(!complete.cases(multi[multi$recall_at_k_eligible, environmental_features])),
    sum(!complete.cases(multi[!multi$recall_at_k_eligible, environmental_features]))
  ),
  first_event_date = as.Date(c(
    min(primary$eventDate),
    min(multi$eventDate),
    min(multi$eventDate[multi$recall_at_k_eligible]),
    min(multi$eventDate[!multi$recall_at_k_eligible])
  )),
  last_event_date = as.Date(c(
    max(primary$eventDate),
    max(multi$eventDate),
    max(multi$eventDate[multi$recall_at_k_eligible]),
    max(multi$eventDate[!multi$recall_at_k_eligible])
  ))
) |>
  mutate(
    percent_environmental_NA = 100 * rows_with_environmental_NA / events
  )


# -------------------------------------------------------------------------
# Save non-sensitive EDA-07 tables
# -------------------------------------------------------------------------

write_csv(species_per_event, file.path(tables_dir, "eda07_species_per_event.csv"))
write_csv(eligibility_by_size, file.path(tables_dir, "eda07_eligibility_by_event_size.csv"))
write_csv(recall_at_k_ceiling, file.path(tables_dir, "eda07_recall_at_k_ceiling.csv"))
write_csv(species_participation, file.path(tables_dir, "eda07_species_participation.csv"))
write_csv(cooccurrence_pairs, file.path(tables_dir, "eda07_cooccurrence_pairs.csv"))
write_csv(top_combinations, file.path(tables_dir, "eda07_top_combinations.csv"))
write_csv(nonvocabulary_partners, file.path(tables_dir, "eda07_nonvocabulary_partners.csv"))
write_csv(eligible_vs_ineligible, file.path(tables_dir, "eda07_eligible_vs_partial.csv"))
write_csv(cohort_comparison, file.path(tables_dir, "eda07_cohort_comparison.csv"))
write_csv(monthly_share, file.path(tables_dir, "eda07_cohort_monthly_share.csv"))
write_csv(cohort_overview, file.path(tables_dir, "eda07_cohort_overview.csv"))


# -------------------------------------------------------------------------
# Figures
# -------------------------------------------------------------------------

theme_set(
  theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold"),
      plot.subtitle = element_text(colour = "grey30"),
      plot.caption = element_text(colour = "grey40", hjust = 0),
      panel.grid.minor = element_blank(),
      strip.text = element_text(face = "bold")
    )
)

eligibility_levels <- c("Recall@k eligible", "Partial overlap")

eligibility_fill <- c(
  "Recall@k eligible" = "#2A6F97",
  "Partial overlap" = "#C8D6DF"
)

# Factors are given explicit levels throughout: ggplot would otherwise order
# groups alphabetically, which silently reorders legends and facet panels.
label_eligibility <- function(is_eligible) {
  factor(
    if_else(is_eligible, eligibility_levels[1], eligibility_levels[2]),
    levels = eligibility_levels
  )
}

save_figure <- function(plot, file, width, height) {
  ggsave(
    file.path(figures_dir, file),
    plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )
}


## Figure 1 -- species per event, split by eligibility -------------------

fig_species_per_event <- multi |>
  mutate(eligibility = label_eligibility(recall_at_k_eligible)) |>
  count(n_species, eligibility) |>
  ggplot(aes(factor(n_species), n, fill = eligibility)) +
  geom_col(width = 0.75) +
  scale_fill_manual(values = eligibility_fill, name = NULL) +
  scale_y_continuous(labels = scales::comma) +
  labs(
    title = "Species detected per multi-species recording",
    subtitle = paste0(
      format(nrow(multi), big.mark = ","), " recordings; ",
      format(sum(multi$recall_at_k_eligible), big.mark = ","),
      " have every detected species inside the 18-class vocabulary"
    ),
    x = "Species detected in the recording",
    y = "Recordings",
    caption = "Larger recordings are progressively less likely to be fully evaluable."
  ) +
  theme(legend.position = "top")

save_figure(fig_species_per_event, "eda07_species_per_event.png", 8, 5)


## Figure 2 -- target-species co-occurrence heatmap ----------------------

# Order by hierarchical clustering on Jaccard distance so co-occurring
# assemblages sit together rather than being scattered by frequency.
jaccard_complete <- jaccard
diag(jaccard_complete) <- 1
cluster_order <- vocabulary[hclust(as.dist(1 - jaccard_complete), method = "average")$order]

cooccurrence_grid <- cooccurrence_pairs |>
  select(species_a, species_b, jaccard, cooccurring_events) |>
  bind_rows(
    cooccurrence_pairs |>
      select(species_a = species_b, species_b = species_a, jaccard, cooccurring_events)
  ) |>
  mutate(
    species_a = factor(species_a, levels = cluster_order),
    species_b = factor(species_b, levels = cluster_order)
  )

fig_cooccurrence <- ggplot(
  cooccurrence_grid,
  aes(species_a, species_b, fill = jaccard)
) +
  geom_tile(colour = "white", linewidth = 0.4) +
  scale_fill_gradient(
    low = "#F2F6F8",
    high = "#14415C",
    name = "Jaccard",
    labels = scales::number_format(accuracy = 0.01)
  ) +
  coord_fixed() +
  labs(
    title = "Co-occurrence of the 18 target species in multi-species recordings",
    subtitle = "Jaccard association; species ordered by hierarchical clustering on co-occurrence",
    x = NULL,
    y = NULL,
    caption = "Diagonal omitted. High values mark species that are frequently recorded together."
  ) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1, face = "italic"),
    axis.text.y = element_text(face = "italic"),
    panel.grid = element_blank()
  )

save_figure(fig_cooccurrence, "eda07_cooccurrence_heatmap.png", 9.5, 8.5)


## Figure 3 -- participation and eligibility by target species -----------

participation_measures <- c(
  "Share of appearances in multi-species recordings",
  "Recall@k-eligible share of those appearances"
)

participation_long <- species_participation |>
  select(
    species,
    !!participation_measures[1] := multi_share_percent,
    !!participation_measures[2] := eligibility_rate_percent
  ) |>
  pivot_longer(-species, names_to = "measure", values_to = "percent") |>
  mutate(
    species = factor(species, levels = rev(species_by_frequency)),
    # Explicit levels: facets would otherwise be ordered alphabetically, which
    # silently swaps the two panels relative to the caption.
    measure = factor(measure, levels = participation_measures)
  )

fig_participation <- ggplot(participation_long, aes(percent, species)) +
  geom_col(fill = "#2A6F97", width = 0.7) +
  facet_wrap(~measure) +
  scale_x_continuous(limits = c(0, 100), expand = expansion(mult = c(0, 0.05))) +
  labs(
    title = "How each target species is represented in the evaluation extension",
    subtitle = "Species ordered by training-cohort frequency (most frequent at top)",
    x = "Percent",
    y = NULL,
    caption = paste(
      "Left: of all events containing the species, the percent that are multi-species.",
      "Right: of its multi-species events, the percent that are Recall@k eligible."
    )
  ) +
  theme(axis.text.y = element_text(face = "italic"))

save_figure(fig_participation, "eda07_species_participation.png", 10, 6)


## Figure 4 -- Recall@k ceiling ------------------------------------------

fig_ceiling <- recall_at_k_ceiling |>
  filter(k <= 8) |>
  ggplot(aes(k, max_mean_recall_at_k)) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "grey60") +
  geom_line(colour = "#2A6F97", linewidth = 0.9) +
  geom_point(colour = "#2A6F97", size = 2.4) +
  geom_text(
    aes(label = scales::number(max_mean_recall_at_k, accuracy = 0.001)),
    vjust = -1.1,
    size = 3,
    colour = "grey25"
  ) +
  scale_x_continuous(breaks = 1:8) +
  scale_y_continuous(limits = c(0.4, 1.06), labels = scales::number_format(accuracy = 0.1)) +
  labs(
    title = "Best achievable mean Recall@k on the eligible extension",
    subtitle = "Upper bound imposed by recordings containing more species than k",
    x = "k",
    y = "Maximum attainable mean Recall@k",
    caption = paste(
      "A perfect model cannot exceed this line. Recall@1 is capped near 0.44 because",
      "\nevery eligible recording contains at least two species."
    )
  )

save_figure(fig_ceiling, "eda07_recall_at_k_ceiling.png", 7.5, 5)


## Figure 5 -- eligible vs partial-overlap context -----------------------

comparison_labels <- c(
  decimalLatitude = "Latitude (degrees)",
  elevation = "Elevation (m)",
  BIO1 = "BIO1 annual mean temperature (C)",
  BIO12 = "BIO12 annual precipitation (mm)"
)

eligibility_context <- multi |>
  mutate(eligibility = label_eligibility(recall_at_k_eligible)) |>
  select(eligibility, all_of(names(comparison_labels))) |>
  pivot_longer(-eligibility, names_to = "variable", values_to = "value") |>
  filter(!is.na(value)) |>
  mutate(
    variable = factor(
      comparison_labels[variable],
      levels = unname(comparison_labels)
    )
  )

fig_eligibility_context <- ggplot(
  eligibility_context,
  # Reversed so the eligible group reads at the top of each panel.
  aes(value, factor(eligibility, levels = rev(eligibility_levels)), fill = eligibility)
) +
  geom_boxplot(outlier.alpha = 0.05, outlier.size = 0.4, width = 0.55) +
  facet_wrap(~variable, scales = "free_x") +
  scale_fill_manual(values = eligibility_fill, guide = "none") +
  labs(
    title = "Are the evaluable recordings a representative subsample?",
    subtitle = "Recall@k-eligible vs partial-overlap recordings in the extension",
    x = NULL,
    y = NULL,
    caption = "Aggregate distributions only; no exact recording locations are shown."
  )

save_figure(fig_eligibility_context, "eda07_eligible_vs_partial.png", 9, 5.5)


## Figure 6 -- training cohort vs evaluation extension -------------------

cohort_labels <- c(
  primary_single_species = "Primary (single-species, training)",
  multispecies_all = "Multi-species extension (all)",
  multispecies_eligible = "Multi-species extension (Recall@k eligible)"
)

fig_monthly <- monthly_share |>
  mutate(
    cohort = factor(cohort_labels[cohort], levels = unname(cohort_labels))
  ) |>
  ggplot(aes(month, percent_of_cohort, colour = cohort, group = cohort)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.8) +
  scale_x_continuous(breaks = 1:12, labels = month.abb) +
  scale_colour_manual(
    values = setNames(
      c("#B5651D", "#7FA8C0", "#14415C"),
      unname(cohort_labels)
    ),
    name = NULL
  ) +
  guides(colour = guide_legend(nrow = 2)) +
  labs(
    title = "Seasonal profile of the training cohort and the evaluation extension",
    subtitle = "Percent of each cohort's recordings falling in each calendar month",
    x = NULL,
    y = "Percent of cohort",
    caption = paste(
      "The extension is more sharply peaked in spring and thinner through autumn",
      "and winter than the\ntraining cohort, so its seasonal composition is related",
      "but not identical."
    )
  ) +
  theme(legend.position = "top")

save_figure(fig_monthly, "eda07_cohort_monthly_share.png", 8.5, 5)


## Figure 7 -- training cohort vs evaluation extension, environment -------

cohort_environment <- bind_rows(
  primary |>
    mutate(cohort = "primary_single_species"),
  multi |>
    mutate(cohort = "multispecies_all"),
  multi |>
    filter(recall_at_k_eligible) |>
    mutate(cohort = "multispecies_eligible")
) |>
  select(cohort, all_of(names(comparison_labels))) |>
  pivot_longer(-cohort, names_to = "variable", values_to = "value") |>
  filter(!is.na(value)) |>
  mutate(
    cohort = factor(cohort_labels[cohort], levels = rev(unname(cohort_labels))),
    variable = factor(
      comparison_labels[variable],
      levels = unname(comparison_labels)
    )
  )

fig_cohort_environment <- ggplot(
  cohort_environment,
  aes(value, cohort, fill = cohort)
) +
  geom_boxplot(outlier.alpha = 0.05, outlier.size = 0.4, width = 0.55) +
  facet_wrap(~variable, scales = "free_x") +
  scale_fill_manual(
    values = setNames(
      c("#B5651D", "#7FA8C0", "#14415C"),
      unname(cohort_labels)
    ),
    guide = "none"
  ) +
  labs(
    title = "Environmental context of the training cohort and the extension",
    subtitle = "Primary single-species events vs all and Recall@k-eligible multi-species events",
    x = NULL,
    y = NULL,
    caption = "Aggregate distributions only; no exact recording locations are shown."
  )

save_figure(fig_cohort_environment, "eda07_cohort_environment.png", 10, 6)


# -------------------------------------------------------------------------
# Console handoff
# -------------------------------------------------------------------------

cat("\n============================================================\n")
cat("EDA-07 MULTI-SPECIES STRUCTURE\n")
cat("============================================================\n\n")

cat("Cohort overview:\n")
print(cohort_overview, width = Inf)

cat("\nSpecies detected per recording:\n")
print(
  species_per_event |> filter(measure == "species_detected"),
  n = Inf, width = Inf
)

cat("\nRecall@k ceiling on the eligible extension:\n")
print(recall_at_k_ceiling |> filter(k <= 6), width = Inf)

cat("\nTop 10 target-species pairs by co-occurrence:\n")
print(
  cooccurrence_pairs |>
    select(species_a, species_b, cooccurring_events, jaccard) |>
    slice_head(n = 10),
  width = Inf
)

cat("\nTop 10 non-vocabulary partner species:\n")
print(nonvocabulary_partners |> slice_head(n = 10), width = Inf)

cat("\nSpecies most and least represented in multi-species recordings:\n")
print(
  species_participation |>
    select(
      species, primary_events, multi_events,
      multi_share_percent, eligibility_rate_percent
    ) |>
    arrange(desc(multi_share_percent)),
  n = Inf, width = Inf
)

cat("\nEDA-07 COMPLETE\n")
cat("11 tables written to outputs/tables/ (eda07_*.csv)\n")
cat("7 figures written to outputs/figures/EDA07/ (eda07_*.png)\n")
cat("No data were modified, filtered, imputed, scaled or balanced.\n")
