# Experiment: class-imbalance correction for elastic-net (not adopted)

## Decision

**Class rebalancing is not used in the primary models.** Correcting for class
imbalance raised Macro-F1 by about 0.075 (22–29%), but it lowered every
ranking metric and overall accuracy. For an 18-species problem whose purpose
is to give an expert a short candidate list, Top-3, Top-5 and MRR matter more
than Macro-F1. The primary elastic-net models therefore stay trained and
evaluated on the natural class distribution, as planned in Stage 1.

This folder keeps the experiment as evidence for that decision.

---

## Why we tested it

The 18-class target is strongly imbalanced (242,600 complete-case events):

| Measure | Value |
| --- | --- |
| Largest class: *Crinia signifera* | 86,099 (35.5%) |
| Smallest class: *Litoria infrafrenata* | 2,096 (0.86%) |
| Largest : smallest | 41.1 : 1 |
| Top 2 species (*C. signifera*, *Limnodynastes peronii*) | 53.4% of events |
| Top 5 species | 71.8% of events |

The primary elastic-net models favour the dominant species: under spatial
validation, five species have recall below 0.10 and Macro-F1 is 0.259–0.266
for M2–M4. The question was whether handling the imbalance would give a
better model overall, not just a better Macro-F1.

---

## Method

### Prior correction

For each recording, the model's predicted probability for each species is
divided by that species' training-set prevalence raised to a power γ, then
the 18 values are rescaled to sum to 1:

> corrected probability of species *c* ∝ predicted probability of *c* / (prevalence of *c*)^γ

- γ = 0: no correction (the primary model).
- γ = 0.5: square-root correction (moderate).
- γ = 1: full correction (equivalent to treating all species as equally
  common in advance).

For multinomial logistic regression, inverse-frequency class weights act
mainly by shifting each species' baseline log-odds by its log prevalence, so
prior correction is a close, much cheaper approximation to class-weighted
training. It is also known as threshold moving.

### Why not resampling

- **Oversampling** is roughly equivalent to class weights for logistic
  regression, but multiplies training size and runtime (the primary run
  already takes over two hours).
- **Undersampling** would discard up to about 97% of *C. signifera* events.
- **SMOTE** would create synthetic recordings with interpolated climate
  values that ignore the strong correlations between BIO variables, at
  locations that were never surveyed.
- The rare classes are not short of data (at least about 1,400 training
  events per fold under random folds and 727 under spatial folds); the issue
  is the decision rule, which prior correction targets directly.

### Part A: exploratory check (fixed γ, no refit)

The saved primary out-of-fold predictions for M2–M4 were corrected with
γ = 0, 0.5 and 1, using development-fold prevalence only, and scored on each
assessment fold.

Because this check scores the assessment folds directly, it was used only to
decide whether the idea was worth testing properly, not to choose γ.

### Part B: nested test (γ tuned on the inner split)

The elastic-net was rerun for M4 with γ ∈ {0, 0.5, 1} added to the tuning
grid alongside `alpha` and `lambda`:

- γ was chosen by Macro-F1 on the inner **tune** rows, using inner **fit**-row
  prevalence;
- the assessment fold was corrected with development-set prevalence and
  scored once;
- test folds never influenced any choice;
- assessment folds keep their natural class distribution.

Command: `Rscript R/modelling/03_elastic_net.R --prior-correction M4`
(55 minutes on 6 workers; no convergence warnings).

---

## Results

### Part A: fixed correction on primary predictions (mean of 3 folds)

| Set | Scheme | γ | Macro-F1 | Balanced acc. | Accuracy | Top-3 | Top-5 | MRR |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M2 | Random | 0 | 0.321 | 0.318 | 0.525 | 0.857 | 0.961 | 0.703 |
| | | 0.5 | 0.403 | 0.455 | 0.479 | 0.833 | 0.954 | 0.672 |
| | | 1 | 0.350 | 0.517 | 0.315 | 0.755 | 0.906 | 0.558 |
| M2 | Spatial | 0 | 0.261 | 0.273 | 0.496 | 0.831 | 0.947 | 0.680 |
| | | 0.5 | 0.335 | 0.386 | 0.441 | 0.800 | 0.935 | 0.641 |
| | | 1 | 0.292 | 0.448 | 0.268 | 0.714 | 0.886 | 0.522 |
| M3 | Random | 0 | 0.322 | 0.318 | 0.526 | 0.858 | 0.963 | 0.704 |
| | | 0.5 | 0.401 | 0.452 | 0.478 | 0.836 | 0.955 | 0.672 |
| | | 1 | 0.351 | 0.521 | 0.314 | 0.755 | 0.911 | 0.558 |
| M3 | Spatial | 0 | 0.259 | 0.274 | 0.493 | 0.831 | 0.949 | 0.679 |
| | | 0.5 | 0.334 | 0.381 | 0.445 | 0.803 | 0.938 | 0.644 |
| | | 1 | 0.293 | 0.452 | 0.268 | 0.714 | 0.887 | 0.523 |
| M4 | Random | 0 | 0.336 | 0.331 | 0.531 | 0.864 | 0.964 | 0.708 |
| | | 0.5 | 0.411 | 0.470 | 0.480 | 0.840 | 0.957 | 0.675 |
| | | 1 | 0.361 | 0.532 | 0.323 | 0.765 | 0.918 | 0.565 |
| M4 | Spatial | 0 | 0.266 | 0.280 | 0.497 | 0.837 | 0.952 | 0.683 |
| | | 0.5 | 0.341 | 0.392 | 0.446 | 0.812 | 0.941 | 0.647 |
| | | 1 | 0.303 | 0.467 | 0.280 | 0.727 | 0.896 | 0.532 |

- Square-root correction (γ = 0.5) gives the highest Macro-F1 for every set
  and scheme.
- Full correction (γ = 1) recovers the most rare-species events (highest
  balanced accuracy) but predicts rare species so often that accuracy falls
  to 27–32%, Top-5 to about 0.89–0.92 and MRR to about 0.52–0.57.
- The pattern is the same for M2, M3 and M4, so the M3 vs M4 conclusions do
  not depend on it.

### Part B: tuned γ vs primary, M4 (mean of 3 folds)

All six outer folds independently selected **γ = 0.5** on their inner tune
split (`alpha` = 1 in every fold).

| Metric | Random: primary → tuned | Change | Spatial: primary → tuned | Change |
| --- | --- | --- | --- | --- |
| Macro-F1 | 0.336 → 0.411 | +0.075 (+22%) | 0.266 → 0.344 | +0.078 (+29%) |
| Balanced accuracy | 0.331 → 0.470 | +0.139 | 0.280 → 0.397 | +0.117 |
| Accuracy | 0.531 → 0.480 | −0.051 | 0.497 → 0.448 | −0.049 |
| Top-3 | 0.864 → 0.840 | −0.024 | 0.837 → 0.811 | −0.026 |
| Top-5 | 0.964 → 0.957 | −0.007 | 0.952 → 0.940 | −0.012 |
| MRR | 0.708 → 0.675 | −0.033 | 0.683 → 0.647 | −0.035 |

Fold SD of spatial Macro-F1 fell from 0.032 to 0.010. The random-vs-spatial
gap was unchanged (about 0.07 Macro-F1).

### Per-species recall, M4 spatial (pooled over folds)

| Species | Events | Primary | Tuned γ | Change |
| --- | --- | --- | --- | --- |
| *Crinia signifera* | 86,099 | 0.826 | 0.610 | −0.216 |
| *Limnodynastes peronii* | 43,369 | 0.481 | 0.311 | −0.170 |
| *Litoria fallax* | 17,265 | 0.324 | 0.321 | −0.003 |
| *Litoria peronii* | 14,482 | 0.259 | 0.512 | +0.253 |
| *Limnodynastes tasmaniensis* | 12,635 | 0.392 | 0.447 | +0.055 |
| *Litoria caerulea* | 12,090 | 0.413 | 0.327 | −0.086 |
| *Litoria ewingii* | 9,242 | 0.086 | 0.394 | +0.308 |
| *Limnodynastes dumerilii* | 7,671 | 0.141 | 0.443 | +0.302 |
| *Crinia glauerti* | 7,147 | 0.416 | 0.291 | −0.125 |
| *Adelotus brevis* | 5,487 | 0.011 | 0.149 | +0.138 |
| *Litoria pyrina* | 4,502 | 0.127 | 0.273 | +0.146 |
| *Litoria quiritatus* | 4,326 | 0.043 | 0.191 | +0.148 |
| *Litoria gracilenta* | 4,256 | 0.036 | 0.330 | +0.294 |
| *Crinia parinsignifera* | 3,916 | 0.063 | 0.305 | +0.242 |
| *Litoria moorei* | 3,557 | 0.502 | 0.654 | +0.152 |
| *Litoria verreauxii* | 2,324 | 0.002 | 0.127 | +0.125 |
| *Crinia georgiana* | 2,136 | 0.227 | 0.607 | +0.380 |
| *Litoria infrafrenata* | 2,096 | 0.441 | 0.819 | +0.378 |

Correction moves top-1 predictions away from the two dominant species, which
together make up 53% of events. Their recall falls by 0.17–0.22, which is
why overall accuracy drops by about 5 points. Thirteen of the other sixteen
species gain recall, several by 0.25–0.38. Precision falls for most of the
species that gain recall (for example *L. verreauxii* 0.667 → 0.149), because
the model now predicts them more often and is wrong more often.

---

## Why it was not adopted

1. **Ranking is the primary use case.** With 18 species, the practical output
   is a short candidate list for expert review. Top-3, Top-5 and MRR all fell
   (Top-3 by about 0.025, MRR by about 0.035), and none of them improved in
   any feature set or scheme.
2. **The Macro-F1 gain is a trade, not a better model.** It comes from
   moving top-1 predictions from common to rare species. Total correct
   top-1 predictions fall (accuracy −5 points), and rare-species precision
   drops.
3. **It matches the Stage 1 plan.** The plan specified natural-distribution
   training as primary, with class weighting allowed only as a sensitivity
   analysis. This experiment is that sensitivity analysis.
4. **It would not change the substantive conclusions.** All feature sets
   shift by a similar amount, and the random-vs-spatial gap is unchanged.

If a user's goal were instead to maximise recovery of rare species as the
single top answer (for example, flagging rare species for follow-up),
γ = 0.5 would be the setting to use.

---

## Limitations

- The nested test (Part B) was run for M4 only; M1–M3 have only the
  exploratory Part A results.
- Only the elastic-net was tested. Tree models may respond differently.
- γ was tuned on Macro-F1 only. Tuning on a ranking metric would choose a
  smaller γ (probably 0).
- The γ grid is coarse (0, 0.5, 1).
- Prior correction approximates, but is not identical to, class-weighted
  training.
- Part A scored the assessment folds directly, so it is exploratory; Part B
  is the properly nested result.

---

## Files

| File | Contents |
| --- | --- |
| `prior_correction_analysis.R` | Reproduces Part A and builds the Part B comparison tables |
| `results/posthoc_correction_fold_metrics.csv` | Part A metrics per fold |
| `results/posthoc_correction_summary.csv` | Part A means (table above) |
| `results/tuned_correction_m4_comparison.csv` | Part B overall comparison |
| `results/tuned_correction_m4_species.csv` | Part B per-species recall and precision, both schemes |
| `results/tuned_correction_m4_selected_gamma.csv` | Selected `alpha`, `lambda` and γ per fold |
| `results/prior_correction_analysis.rds` | All analysis tables in one R object |
| `results/model_elastic_net_corrected_*.csv` | Full outputs of the tuned M4 run (fold metrics, per-species metrics, tuning grid, selected settings, feature importance) |
| `results/elastic_net_corrected_results_M4.rds` | Tuned M4 run results object |
| `results/oof_elastic_net_corrected_M4.rds` | Tuned M4 out-of-fold probabilities (event-level, 65 MB) |
| `results/elastic_net_corrected_M4.log` | Console log of the tuned M4 run |

`.rds` and `.log` files are Git-ignored by the repository's global rules, so
only the scripts, README and CSV tables are committed.

## Reproduce

From the repository root, after the primary elastic-net run:

```sh
caffeinate -i env EN_WORKERS=6 Rscript R/modelling/03_elastic_net.R --prior-correction M4
Rscript R/modelling/experiments/class_imbalance/prior_correction_analysis.R
```

The first command writes its outputs directly into `results/`; the second
takes about a minute.
