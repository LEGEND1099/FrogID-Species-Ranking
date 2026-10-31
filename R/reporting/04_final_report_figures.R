# STAT5003 A2 - Final report figures (colour edition; print-readable layout)
# Run from the FrogID-A2-Integration repository root:
#   & "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" "R/reporting/04_final_report_figures.R"
# Requires ggplot2 only. Read-only source data; writes four final-report PNGs.
# Inspired by a field-journal palette: lagoon, coral, gold, violet and deep navy.
# Identical cohort, binning, data checks and reported statistical results.

if (!file.exists('renv.lock') || !dir.exists('outputs/tables')) {
  stop('Run this script from the FrogID-A2-Integration project root.', call. = FALSE)
}
if (!requireNamespace('ggplot2', quietly = TRUE)) {
  stop('ggplot2 is unavailable in the active R library. Check renv::status() before installing anything.',
       call. = FALSE)
}
suppressPackageStartupMessages(library(ggplot2))

output_dir <- 'outputs/figures/final_report'
figure_paths <- list(
  clean = file.path(output_dir, 'report_final_cleaning_flow.png'),
  geo = file.path(output_dir, 'report_final_geographic_examples.png'),
  comparison = file.path(output_dir, 'report_final_rf_vs_xgb_rare_species.png'),
  all_species = file.path(output_dir, 'report_final_rf_vs_xgb_all_species.png')
)

read_required <- function(path, columns) {
  if (!file.exists(path)) stop('Missing required file: ', path, call. = FALSE)
  tab <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  missing <- setdiff(columns, names(tab))
  if (length(missing)) stop('Missing columns in ', path, ': ',
                             paste(missing, collapse = ', '), call. = FALSE)
  tab
}
fmt_count <- function(x) format(x, big.mark = ',', scientific = FALSE, trim = TRUE)

# --- Verify original pipeline counts, not manually copied constants ---
qc <- read_required('outputs/tables/qc_filter_flow.csv', c('stage', 'events_remaining'))
missingness <- read_required('outputs/tables/eda06_missingness_summary.csv',
                             c('measure', 'value'))
get_stage <- function(stage) {
  i <- which(qc$stage == stage)
  if (length(i) != 1L) stop('Missing or duplicate QC stage: ', stage)
  as.integer(qc$events_remaining[i])
}
get_measure <- function(measure) {
  i <- which(missingness$measure == measure)
  if (length(i) != 1L) stop('Missing or duplicate diagnostic: ', measure)
  as.integer(as.numeric(missingness$value[i]))
}
original_events <- get_stage('raw_events')
qc_events <- get_stage('no_data_generalization')
single_events <- get_stage('clean_single_species_events')
selected_events <- get_stage('selected_primary_events')
missing_events <- get_measure('environmental_missing_events')
final_events <- selected_events - missing_events
stopifnot(original_events == 542287L, qc_events == 519414L,
          single_events == 291103L, selected_events == 247406L,
          missing_events == 4806L, final_events == 242600L)

# --- Verify exact modelling source, complete cases, selected species ---
cohort_path <- 'data/processed/frog_primary_multiclass.rds'
if (!file.exists(cohort_path)) stop('Missing modelling source: ', cohort_path)
cohort <- as.data.frame(readRDS(cohort_path))
climate_cols <- c(paste0('BIO', 1:19),
                  'climatological_tavg_event_month',
                  'climatological_prec_event_month', 'elevation')
needed <- c('scientificName', 'decimalLatitude', 'decimalLongitude', climate_cols)
if (!all(needed %in% names(cohort))) {
  stop('Primary data missing fields: ', paste(setdiff(needed, names(cohort)), collapse = ', '))
}
stopifnot(nrow(cohort) == selected_events)
complete <- stats::complete.cases(cohort[, climate_cols, drop = FALSE])
stopifnot(sum(complete) == final_events)
cohort <- cohort[complete, c('scientificName', 'decimalLatitude', 'decimalLongitude')]
stopifnot(length(unique(cohort$scientificName)) == 18L,
          !anyNA(cohort), all(is.finite(cohort$decimalLatitude)),
          all(is.finite(cohort$decimalLongitude)))

outline <- read_required('R/reporting/assets/australia_outline.csv', c('group', 'long', 'lat'))
equity <- read_required('outputs/tables/report_species_equity_rf_vs_xgb.csv',
                        c('scientificName', 'total_support', 'rare_six',
                          'mean_f1_random_forest', 'mean_f1_xgboost',
                          'mean_recall_random_forest', 'mean_recall_xgboost'))
scorecard <- read_required('outputs/tables/report_species_equity_scorecard.csv',
                           c('model', 'rare_six_mean_f1', 'rare_six_mean_recall'))
rare <- equity[tolower(as.character(equity$rare_six)) == 'true', , drop = FALSE]
rare <- rare[order(rare$total_support), , drop = FALSE]
stopifnot(nrow(equity) == 18L, nrow(rare) == 6L,
          sum(equity$total_support) == final_events)
rf <- scorecard[scorecard$model == 'random_forest', , drop = FALSE]
xgb <- scorecard[scorecard$model == 'xgboost', , drop = FALSE]
stopifnot(nrow(rf) == 1L, nrow(xgb) == 1L)

# --- Colour system: vivid but accessible in print ---
# Blue circles = Random Forest; coral triangles = XGBoost throughout.
# Light gold is a *group marker* for least-recorded species, not performance.
blue   <- '#196DB5' # vivid blue: Random Forest
coral  <- '#E65B48' # warm coral: XGBoost
teal   <- '#078C83' # botanical teal
violet <- '#6B4BA8' # colour scale endpoint
gold   <- '#D79B1C' # high-visibility gold accents
ink    <- '#203145' # navy body text
muted  <- '#516578'
plot_theme <- theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = 'bold', size = 15, colour = ink,
                              margin = margin(b = 5)),
    plot.subtitle = element_text(size = 10, colour = muted,
                                 lineheight = 1.15, margin = margin(b = 11)),
    plot.caption = element_text(size = 8.5, colour = muted,
                                lineheight = 1.28, hjust = 0),
    plot.caption.position = 'plot',
    plot.margin = margin(t = 12, r = 16, b = 16, l = 14),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = '#E9EDF2', linewidth = .32),
    axis.text = element_text(colour = ink),
    axis.title = element_text(colour = ink, face = 'bold'),
    legend.position = 'bottom',
    legend.title = element_text(colour = ink),
    legend.text = element_text(colour = ink),
    strip.text = element_text(face = 'bold', size = 11, colour = ink),
    strip.background = element_rect(fill = '#F2F0FC', colour = '#E1DAF6',
                                    linewidth = .3)
  )

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
save_figure <- function(p, path, width, height) {
  ggplot2::ggsave(path, plot = p, width = width, height = height,
                  units = 'in', dpi = 250, bg = 'white')
  message('Saved: ', path)
}

# ============================================================
# Figure 1 - Clean-recording cohort: 5-stage event flow
# ============================================================
stages <- data.frame(
  stage = c('Original recording events', 'Location-quality-control passed',
            'Single-species recordings', 'Selected 18-species cohort',
            'Final complete-case modelling cohort'),
  count = c(original_events, qc_events, single_events,
            selected_events, final_events),
  note = c('974,120 original species-occurrence rows',
           paste0(fmt_count(original_events - qc_events), ' excluded by quality checks'),
           'One identified species per recording',
           '18 species with at least 2,000 clean recordings each',
           paste0(fmt_count(missing_events), ' missing-environment records excluded')),
  y = 5:1, stringsAsFactors = FALSE
)
# Each stage gets a distinct restrained accent; final cohort gets strongest tint.
stages$stage <- factor(stages$stage, levels = stages$stage)
stage_fill <- c(
  'Original recording events' = '#E8F4FB',
  'Location-quality-control passed' = '#E7F6ED',
  'Single-species recordings' = '#F1ECFC',
  'Selected 18-species cohort' = '#FFF1D7',
  'Final complete-case modelling cohort' = '#C9EFE6'
)
stage_stroke <- c(
  'Original recording events' = '#3185C5',
  'Location-quality-control passed' = '#28A17E',
  'Single-species recordings' = '#8063C5',
  'Selected 18-species cohort' = '#8B5D00',
  'Final complete-case modelling cohort' = '#078C83'
)
# Connect each box to the next. These plotting coordinates are intentionally
# fixed positions, independent of the event counts shown in the boxes.
connectors <- data.frame(
  y = c(4.66, 3.66, 2.66, 1.66),
  yend = c(4.34, 3.34, 2.34, 1.34)
)
p_clean <- ggplot() +
  geom_rect(data = stages,
            aes(xmin = 0, xmax = 2.95, ymin = y - .32,
                ymax = y + .32, fill = stage),
            colour = '#CBD6DE', linewidth = .40) +
  # The stage fills and coloured counts provide sufficient differentiation.
  # No hollow accent rectangles: they produced visible white-stripe artefacts.
  geom_segment(data = connectors,
               aes(x = 1.475, xend = 1.475, y = y, yend = yend),
               arrow = grid::arrow(length = grid::unit(.12, 'cm'), type = 'closed'),
               colour = '#788A9A', linewidth = .62) +
  geom_text(data = stages, aes(x = 1.475, y = y + .12, label = stage),
            fontface = 'bold', colour = ink, size = 3.35) +
  geom_text(data = stages, aes(x = 1.475, y = y - .15,
                               label = vapply(count, fmt_count, character(1)),
                               colour = stage),
            fontface = 'bold', size = 4.25, show.legend = FALSE) +
  geom_text(data = stages, aes(x = 3.17, y = y, label = note),
            hjust = 0, size = 3.25, colour = muted) +
  scale_fill_manual(values = stage_fill, guide = 'none') +
  scale_colour_manual(values = stage_stroke, guide = 'none') +
  coord_cartesian(xlim = c(-.10, 7), ylim = c(.56, 5.48), clip = 'off') +
  labs(title = 'From FrogID occurrences to the modelling cohort',
       subtitle = 'Cleaning removes unsuitable events; subsequent selection defines the 18-species task',
       caption = 'Counts verified against saved quality-control and missingness tables.') +
  plot_theme + theme(axis.text = element_blank(), axis.title = element_blank(),
                     panel.grid = element_blank(), panel.grid.major = element_blank(),
                     panel.grid.minor = element_blank(), axis.ticks = element_blank())
save_figure(p_clean, figure_paths$clean, 10.2, 4.9)

# ============================================================
# Figure 2 - 4 illustrative recording footprints (0.5-degree cells)
# Based on COMPLETE-CASE cohort, not an arbitrary first-N-row sample.
# ============================================================
chosen <- c('Crinia signifera', 'Limnodynastes peronii',
            'Litoria ewingii', 'Litoria infrafrenata')
if (!all(chosen %in% cohort$scientificName)) {
  stop('Missing required geographic panel species: ',
       paste(setdiff(chosen, cohort$scientificName), collapse = ', '))
}
geo <- cohort[as.character(cohort$scientificName) %in% chosen, , drop = FALSE]
geo_cells <- data.frame(
  species = as.character(geo$scientificName),
  lon = (floor(geo$decimalLongitude / .5) + .5) * .5,
  lat = (floor(geo$decimalLatitude / .5) + .5) * .5,
  stringsAsFactors = FALSE
)
cell_counts <- stats::aggregate(
  x = list(events = rep.int(1L, nrow(geo_cells))),
  by = geo_cells[c('species', 'lon', 'lat')], FUN = sum
)
cell_counts$species <- factor(cell_counts$species, levels = chosen)
stopifnot(sum(cell_counts$events) == nrow(geo))
p_geo <- ggplot() +
  geom_tile(data = cell_counts, aes(x = lon, y = lat, fill = events),
            width = .5, height = .5) +
  geom_path(data = outline, aes(x = long, y = lat, group = group),
            colour = '#51677B', linewidth = .28) +
  facet_wrap(~species, ncol = 2) +
  coord_quickmap(xlim = c(111, 155), ylim = c(-45, -9), expand = FALSE) +
  scale_fill_gradientn(
    colours = c('#E8F8F0', '#7AD9BE', '#2EB8BB', '#4385CE', '#6A45B8'),
    values = c(0, .24, .48, .73, 1),
    trans = 'log10', breaks = c(1, 10, 100, 1000, 10000),
    labels = fmt_count, name = 'Events per\n0.5-degree cell') +
  labs(title = 'Recording footprints differ across frog species',
       subtitle = 'Four illustrative species; same Australia extent and shared colour scale',
       x = NULL, y = NULL,
       caption = 'Complete-case FrogID recording locations aggregated into 0.5-degree cells; not biological range maps.') +
  plot_theme + theme(panel.grid = element_blank(),
                     axis.text = element_blank(), axis.ticks = element_blank(),
                     strip.text = element_text(face = 'bold.italic', size = 10.5, colour = ink),
                     strip.background = element_rect(fill = '#FFF1D7', colour = '#F2D5A5'),
                     legend.position = 'right')
save_figure(p_geo, figure_paths$geo, 9.5, 6.6)

# ============================================================
# Figure 3 - RF vs XGBoost on 6 least-recorded species
# Display BOTH F1 and recall. Species-level comparisons are post-hoc.
# ============================================================
metric_data <- rbind(
  data.frame(species = rare$scientificName, metric = 'F1',
             rf = rare$mean_f1_random_forest, xgb = rare$mean_f1_xgboost),
  data.frame(species = rare$scientificName, metric = 'Recall',
             rf = rare$mean_recall_random_forest, xgb = rare$mean_recall_xgboost)
)
metric_data$species <- factor(metric_data$species,
                              levels = rev(rare$scientificName))
point_data <- rbind(
  data.frame(species = metric_data$species, metric = metric_data$metric,
             model = 'Random Forest', score = metric_data$rf),
  data.frame(species = metric_data$species, metric = metric_data$metric,
             model = 'XGBoost', score = metric_data$xgb)
)
metric_data$metric <- factor(metric_data$metric, levels = c('F1', 'Recall'))
point_data$metric <- factor(point_data$metric, levels = c('F1', 'Recall'))
subtitle <- sprintf('Six least-recorded species | Mean F1: RF %.3f, XGB %.3f\nMean recall: RF %.3f, XGB %.3f',
                    rf$rare_six_mean_f1, xgb$rare_six_mean_f1,
                    rf$rare_six_mean_recall, xgb$rare_six_mean_recall)
p_equity <- ggplot() +
  geom_segment(data = metric_data,
               aes(x = rf, xend = xgb, y = species, yend = species),
               colour = '#B4C3CD', linewidth = .78) +
  geom_point(data = point_data, aes(x = score, y = species, colour = model, shape = model),
             size = 3.1, stroke = .5) +
  facet_wrap(~metric, ncol = 2) +
  scale_color_manual(values = c('Random Forest' = blue,
                                'XGBoost' = coral), name = NULL) +
  scale_shape_manual(values = c('Random Forest' = 16,
                                'XGBoost' = 17), name = NULL) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, by = .2)) +
  labs(title = 'RF and XGBoost have different species-level strengths',
       subtitle = subtitle,
       x = 'Species-level assessment score (higher is better)', y = NULL,
       caption = 'Six lowest-frequency species in the 242,600-event cohort.\nPost-hoc descriptive comparison, not a separate validation set.') +
  plot_theme + theme(panel.grid.major.y = element_blank(),
                     axis.text.y = element_text(face = 'italic', size = 9.4))
save_figure(p_equity, figure_paths$comparison, 11, 5.0)

# ============================================================
# Figure 4 - RF versus XGBoost F1 for ALL 18 species
# Show full species context, ordered by observed support.
# Highlight the six least-recorded classes. No model is re-fitted.
# Source: frozen M4 spatial species-level results.
# ============================================================
all_species <- equity[order(equity$total_support, equity$scientificName), , drop = FALSE]
stopifnot(nrow(all_species) == 18L,
          !anyDuplicated(all_species$scientificName),
          identical(sort(as.character(all_species$scientificName)),
                    sort(unique(as.character(cohort$scientificName)))),
          all(is.finite(all_species$mean_f1_random_forest)),
          all(is.finite(all_species$mean_f1_xgboost)),
          all(all_species$mean_f1_random_forest >= 0 &
              all_species$mean_f1_random_forest <= 1),
          all(all_species$mean_f1_xgboost >= 0 &
              all_species$mean_f1_xgboost <= 1))

# This is the same definition of 'rare six' as the saved class-audit table.
rare_flag <- tolower(as.character(all_species$rare_six)) == 'true'
stopifnot(!anyNA(rare_flag), sum(rare_flag) == 6L,
          all(rare_flag[seq_len(6L)]),
          !any(rare_flag[7:18]),
          setequal(all_species$scientificName[rare_flag], rare$scientificName))

# Positive y-values locate least-recorded species at the top of the chart.
all_species$y <- rev(seq_len(nrow(all_species)))
all_species$label <- paste0(
  ifelse(rare_flag, '* ', ''), all_species$scientificName,
  '  (n=', vapply(all_species$total_support, fmt_count, character(1)), ')'
)

f1_points <- rbind(
  data.frame(y = all_species$y, model = 'Random Forest',
             F1 = all_species$mean_f1_random_forest),
  data.frame(y = all_species$y, model = 'XGBoost',
             F1 = all_species$mean_f1_xgboost)
)
f1_points$model <- factor(f1_points$model,
                          levels = c('Random Forest', 'XGBoost'))

xgb_wins <- sum(all_species$mean_f1_xgboost > all_species$mean_f1_random_forest)
rf_wins <- sum(all_species$mean_f1_random_forest > all_species$mean_f1_xgboost)
stopifnot(xgb_wins == 12L, rf_wins == 6L, xgb_wins + rf_wins == 18L)

all_species_caption <- paste0(
  '* Gold bands = six least-recorded species; all scores use the same spatial folds.\n',
  'XGBoost higher F1 in ', xgb_wins, '/18 species. Post-hoc comparison, not a new test set.'
)

p_all_species <- ggplot() +
  # Subtle horizontal bands mark the six species with the smallest support.
  geom_rect(
    data = all_species[rare_flag, , drop = FALSE],
    aes(xmin = -Inf, xmax = Inf, ymin = y - .48, ymax = y + .48),
    inherit.aes = FALSE, fill = '#FFF1D7', colour = NA
  ) +
  geom_segment(
    data = all_species,
    aes(x = mean_f1_random_forest, xend = mean_f1_xgboost,
        y = y, yend = y),
    colour = '#B4C3CD', linewidth = .82
  ) +
  geom_point(data = f1_points,
             aes(x = F1, y = y, colour = model, shape = model),
             size = 2.55, stroke = .55) +
  scale_colour_manual(values = c('Random Forest' = blue,
                                 'XGBoost' = coral), name = NULL) +
  scale_shape_manual(values = c('Random Forest' = 16,
                                'XGBoost' = 17), name = NULL) +
  scale_y_continuous(
    breaks = seq_len(18L),
    labels = all_species$label[order(all_species$y)],
    limits = c(.48, 18.55), expand = c(0, 0)
  ) +
  scale_x_continuous(breaks = seq(0, .8, by = .1),
                     labels = function(x) sprintf('%.1f', x)) +
  coord_cartesian(xlim = c(0, .82), clip = 'off') +
  labs(title = 'Species-level F1 reveals a model-selection trade-off',
       subtitle = 'All 18 species, ordered by number of recordings (fewest at top)',
        x = 'Mean spatial F1 across three outer folds\n(higher is better)',
       y = NULL, caption = all_species_caption) +
  plot_theme +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(),
        plot.title.position = 'plot',
        axis.text.y = element_text(face = 'italic', size = 10.5,
                                   margin = margin(r = 7)),
        axis.text.x = element_text(size = 10),
        axis.title.x = element_text(size = 10.5, margin = margin(t = 7)),
        legend.position = 'bottom',
        legend.text = element_text(size = 10.5),
        plot.caption = element_text(size = 9.5, hjust = 0))

# Export at the intended A4 print width so label sizes survive HTML printing.
# Keep all 18 scientific names, support counts, both models and rare-six bands.
save_figure(p_all_species, figure_paths$all_species, 7.4, 7.0)

cat('\nFINAL REPORT FIGURES PASSED: created 4 graphics without changing model results.\n')
for (f in unlist(figure_paths)) cat('  ', f, '\n', sep = '')
