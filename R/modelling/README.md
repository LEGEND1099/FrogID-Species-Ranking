# Modelling: M0 baseline and elastic-net (`log-reg` branch)

This branch adds the shared modelling infrastructure and two model families
from the Stage 2 plan:

- **M0**: the species-prevalence baseline (no context);
- **Elastic-net multinomial logistic regression** across feature sets M1–M4
  (the Stage A feature-group progression for the linear model).

The other model families (PCA-LDA, PCA-kNN, random forest, XGBoost) are
handled by other group members. They should reuse the folds and helpers
described below so that every model is evaluated on the same splits with the
same metrics.

All design decisions follow the Stage 1 submission and
`docs/eda-10-modeling-handoff.md` (on `origin/eda`).

---

## What changed on this branch

| File | Purpose |
| --- | --- |
| `R/modelling/modelling_helpers.R` | Shared cohort loader, M0–M4 feature sets, fold utilities, evaluation metrics |
| `R/modelling/01_build_folds.R` | Builds and verifies the fixed outer/inner fold assignment |
| `R/modelling/02_m0_baseline.R` | M0 prevalence baseline |
| `R/modelling/03_elastic_net.R` | Elastic-net multinomial regression for M1–M4 |
| `data/processed/frog_modelling_folds.rds` | Shared fold assignment (event-level, Git-tracked for the team) |
| `outputs/tables/model_*.csv` | Aggregate fold, metric, tuning and diagnostic tables |
| `renv.lock` | Adds `glmnet` 5.1 and its dependencies; nothing removed |

---

## Reproduce

From the repository root:

```sh
Rscript -e "renv::restore(prompt = FALSE)"
Rscript R/modelling/01_build_folds.R     # ~3 s
Rscript R/modelling/02_m0_baseline.R     # ~5 s
caffeinate -i env EN_WORKERS=12 Rscript R/modelling/03_elastic_net.R M1 M2 M3 M4
```

The elastic-net run took **about 2 h 25 min** for all 24 jobs (4 feature sets
× 2 schemes × 3 folds) on 12 workers. M1 alone takes about 5 minutes.

- `01_build_folds.R` only needs re-running if the cohort changes; everyone
  else should use the committed `frog_modelling_folds.rds`.
- `EN_WORKERS` sets the number of parallel workers (default: cores − 2).
- Each job prints a timestamped line when it starts, after each `alpha`, and
  when it finishes.
- Run long jobs from your own terminal, plugged in, with the lid open.
  Jobs started in the background by some tools run at reduced CPU priority
  and can be much slower; `caffeinate -i` stops the Mac idling to sleep.

---

## Shared setup

### Modelling cohort

- 242,600 complete-case events (247,406 primary events minus the 4,806 with
  missing environmental data), 18 species.
- The same rows are used for every model and feature set, so differences in
  performance are not caused by different observations.

### Feature sets

| Set | Predictors |
| --- | --- |
| M0 | none (class prevalence only) |
| M1 | `month_sin`, `month_cos`, `day_of_year_sin`, `day_of_year_cos` |
| M2 | M1 + BIO1–BIO19 + event-month climatological temperature and precipitation |
| M3 | M2 + `elevation` |
| M4 | M3 + `decimalLatitude`, `decimalLongitude` |

Raw `month`, `day_of_year` and year are excluded. EPBC, QC, privacy and
observer fields never enter a predictor matrix.

### Validation folds

Two outer 3-fold schemes, both saved in `frog_modelling_folds.rds`:

- **Random**: class-stratified event-level folds (seed 5003).
- **Spatial**: folds grouped by 0.5° grid cell. Cells are assigned largest
  first to whichever fold keeps each species' share closest to one third.
  No cell is ever split across folds.

Inside each outer development set there is an 80/20 **fit/tune** split for
hyperparameter tuning. It follows the outer scheme: stratified for random,
whole 0.5° cells for spatial (so tuning cannot reward location memorisation).

Verified: all 18 species appear in every outer assessment, development, fit
and tune partition.

| Scheme | Assessment fold sizes | Smallest species count in an assessment fold |
| --- | --- | --- |
| Random | 80,860–80,872 | 698 |
| Spatial | 76,277–87,738 | 316 |

Spatial folds cannot balance geographically concentrated species: 69.5% of
*Crinia glauerti*, 66% of *C. georgiana* and 63% of *Litoria infrafrenata*
fall in a single fold. Per-species results for these are the least stable
under spatial validation.

### Metrics

`evaluate_predictions(prob, truth)` in `modelling_helpers.R` scores any model
from an n × 18 probability matrix (columns named and ordered as
`levels(cohort$scientificName)`). It returns:

- Macro-F1 (primary selection metric), accuracy, balanced accuracy;
- Top-3 and Top-5 accuracy, mean reciprocal rank (MRR), log loss;
- per-species precision, recall and F1.

Conventions: ties in scores are broken by column order (the same rule as the
top-1 prediction), and a species that is never predicted gets F1 = 0.

---

## M0: prevalence baseline

Each assessment event receives the same ranking: species ordered by their
share of that fold's development data. Assessment-fold prevalence is never
used. M0 always predicts *Crinia signifera*, the most common species.

## Elastic-net multinomial regression

- `glmnet`, `family = "multinomial"`, `type.multinomial = "grouped"` (each
  predictor is kept or dropped for all 18 classes together).
- Predictors standardised inside each fit using only that fit's training rows.
- The correlated BIO block (including BIO5/BIO6/BIO7) is kept and handled by
  the penalty, as planned.
- Natural class distribution; no weighting or resampling.
- Tuning grid: `alpha` ∈ {0, 0.5, 1}; a 30-value `lambda` path
  (`lambda.min.ratio = 1e-4`); solver limit `maxit = 1e6`.
- For each outer fold: fit on the inner fit rows, pick the (`alpha`, `lambda`)
  with the highest Macro-F1 on the tune rows, refit on the full development
  set, then predict the untouched assessment fold once.

### Convergence fix

The first M2–M4 run used `glmnet`'s default `maxit = 1e5`. The solver failed
to converge below `lambda` ≈ 0.01 and silently returned a truncated path
(13–14 of 30 values: *"Convergence for 15th lambda value not reached …
solutions for larger lambdas returned"*). Every job then selected the last
value on that truncated path, so tuning was cut short and the models were
more heavily regularised than intended. For M4 with random folds the refit
also stopped early, which produced an artificial drop in Macro-F1.

How it was diagnosed and fixed:

1. `selected_at_path_end = TRUE` for every M2–M4 job flagged the problem.
2. A 20,000-row subsample reproduced the warning in about 30 seconds.
3. Dropping BIO7 (an exact combination of BIO5 and BIO6) did **not** fix it.
4. Raising `maxit` to 1e6 did: the full path converged, and tune Macro-F1
   rose from about 0.23 at the old stopping point to about 0.31.
5. M1–M4 were rerun with `maxit = 1e6`. All paths now reach 30/30 values and
   every refit reaches its selected `lambda` (`refit_reached_selected`).

Macro-F1 before → after the fix:

| Set | Random | Spatial |
| --- | --- | --- |
| M1 | 0.054 → 0.054 | 0.054 → 0.054 |
| M2 | 0.237 → 0.321 | 0.201 → 0.261 |
| M3 | 0.238 → 0.322 | 0.202 → 0.259 |
| M4 | 0.213 → 0.336 | 0.206 → 0.266 |

The truncated results are archived (Git-ignored) in
`data/interim/modelling/archive_maxit1e5/`.

The reported run logged one warning per job: `glmnet` 5.1's notice that
passing `maxit` directly is deprecated. The script now uses the recommended
`control = list(maxit = ...)`, which gives identical fits (checked on the
20,000-row subsample) without the warning.

Ridge (`alpha = 0`) has a separate, smaller limitation: `glmnet` starts ridge
paths from a much larger `lambda`, so with the same ratio its weakest penalty
is only about 0.03. Ridge was never selected for M2–M4.

### Selected settings

| Set | Random folds | Spatial folds |
| --- | --- | --- |
| M1 | `alpha` 0.5, `lambda` ≈ 0.011 | `alpha` 0.5 / 0 / 0; `lambda` 0.0024–0.084 |
| M2 | `alpha` 1, `lambda` ≈ 3.0e-5 (end of path) | `alpha` 0.5 / 1 / 1; `lambda` 4.2e-5–3.7e-4 |
| M3 | `alpha` 1, `lambda` ≈ 3.0e-5 (end of path) | `alpha` 0.5 / 1 / 0.5; `lambda` 1.2e-4–2.7e-4 |
| M4 | `alpha` 1, `lambda` ≈ 3.0e-5 (end of path) | `alpha` 0.5 / 1 / 0.5; `lambda` 6.2e-5–4.1e-4 |

With random folds, tuning always chose the weakest penalty: with about
130,000 training rows and at most 28 predictors, shrinkage barely helps
prediction near the training data. With spatial folds it usually chose
stronger penalties, so shrinkage helps when predicting in unseen areas.
Nearly all predictors were kept (24–28 non-zero), so the elastic net shrank
coefficients rather than selecting variables.

---

## Results

Mean across the 3 outer folds (random / spatial).

| Set | Macro-F1 | Balanced acc. | Accuracy | Top-3 | Top-5 | MRR |
| --- | --- | --- | --- | --- | --- | --- |
| M0 prevalence | 0.029 / 0.029 | 0.056 / 0.056 | 0.355 / 0.356 | 0.605 / 0.606 | 0.717 / 0.706 | 0.525 / 0.524 |
| M1 season | 0.054 / 0.054 | 0.079 / 0.077 | 0.396 / 0.396 | 0.632 / 0.622 | 0.759 / 0.749 | 0.556 / 0.552 |
| M2 + climate | 0.321 / 0.261 | 0.318 / 0.273 | 0.525 / 0.496 | 0.857 / 0.831 | 0.961 / 0.947 | 0.703 / 0.680 |
| M3 + elevation | 0.322 / 0.259 | 0.318 / 0.274 | 0.526 / 0.493 | 0.858 / 0.831 | 0.963 / 0.949 | 0.704 / 0.679 |
| M4 + lat/lon | 0.336 / 0.266 | 0.331 / 0.280 | 0.531 / 0.497 | 0.864 / 0.837 | 0.964 / 0.952 | 0.708 / 0.683 |

Fold SD of Macro-F1 is 0.003–0.005 under random validation and 0.014–0.032
under spatial validation. Fold-level and per-species values are in
`outputs/tables/`.

### Findings

1. **M0 is a high floor for ranking metrics.** With no context it already
   reaches about 72% Top-5 and 0.52 MRR, because the five most common species
   make up about 72% of events. This is why Macro-F1 is the selection metric.
2. **Season adds a little; climate adds most of the signal.** M1 roughly
   doubles M0's Macro-F1 (0.029 → 0.054) but only ever predicts two species.
   Adding climate raises Macro-F1 about six-fold (0.054 → 0.321).
3. **Elevation adds nothing** beyond climate (M2 0.321 vs M3 0.322),
   consistent with the EDA.
4. **About 20% of performance depends on familiar locations.** Under spatial
   validation, Macro-F1 for M2–M4 falls by about 0.06 (19–21% relative).
   Ranking holds up better: Top-5 0.963 → 0.949 and MRR 0.704 → 0.679 for M3.
   M1, which has no location information, shows no drop.
5. **M3 vs M4: coordinates help only in familiar areas.** Under random
   validation they add +0.014 Macro-F1 (three to four times the fold SD).
   Under spatial validation they add +0.007, well within the fold SD
   (0.025–0.032). This is evidence of geographic memorisation even in a
   linear model, which can only use latitude/longitude as straight-line
   gradients. Larger gaps are expected for tree and kNN models.
6. **Geographically concentrated species lose most under spatial
   validation.** M3 recall, random → spatial:

   | Species | Random | Spatial |
   | --- | --- | --- |
   | *Crinia glauerti* | 0.69 | 0.42 |
   | *Crinia georgiana* | 0.43 | 0.15 |
   | *Litoria infrafrenata* | 0.70 | 0.45 |
   | *Litoria moorei* | 0.62 | 0.50 |
   | *Crinia signifera* (widespread) | 0.85 | 0.83 |

   *L. verreauxii* (about 0), *L. quiritatus*, *A. brevis*, *L. gracilenta*
   and *L. ewingii* stay below 0.1 recall under both schemes: a linear model
   does not separate them from common species with overlapping climates.
7. **Practical value.** Even in unseen areas the true species is in the top 5
   about 95% of the time, against 71% for the prevalence baseline, which
   supports the "screening shortlist for expert review" framing.

For the five-model comparison, M3 under spatial validation (Macro-F1 0.259)
is the linear benchmark for the central M3 vs M4 question.

---

## Outputs

Public aggregate tables (`outputs/tables/`):

- `model_fold_summary.csv`, `model_fold_class_counts.csv`,
  `model_inner_split_summary.csv`: fold construction checks;
- `model_prevalence_fold_metrics.csv`, `model_prevalence_summary.csv`,
  `model_prevalence_class_metrics.csv`: M0;
- `model_elastic_net_fold_metrics.csv`, `model_elastic_net_summary.csv`,
  `model_elastic_net_class_metrics.csv`, `model_elastic_net_tuning.csv`,
  `model_elastic_net_feature_importance.csv`: elastic-net M1–M4;
- `model_elastic_net_selected.csv`: chosen settings per job plus diagnostics
  (`selected_at_path_end`, `refit_reached_selected`, `convergence_warnings`,
  `warning_messages`, `runtime_seconds`).

Event-level out-of-fold predictions are saved under `data/interim/modelling/`
(Git-ignored) and can be regenerated by re-running the scripts.

---

## For other model families

To plug in a new model:

1. `source("R/modelling/modelling_helpers.R")`, then load data with
   `load_modelling_cohort()` and `load_modelling_folds(cohort)`.
2. Select predictors with `feature_sets$M3` (etc.).
3. For each scheme and outer fold, tune only on the `*_inner_<k>` fit/tune
   rows, refit on the development set, and predict the assessment fold once.
4. Score with `evaluate_predictions()` and summarise with
   `summarise_fold_metrics()`.
5. Save predictions with `save_oof_predictions()`.

Lesson from the elastic-net run: check that iterative solvers actually
converge (warnings, path length, whether the selected setting sits at the
edge of the grid) before trusting tuned results.
