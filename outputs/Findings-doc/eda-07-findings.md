# EDA-07 findings — multi-species recording structure

Work package: EDA-07 (`docs/eda-plan.md`).
Script: `analysis/07_multispecies_eda.R`.
Inputs: `data/processed/frog_multispecies_extension.rds`,
`data/processed/frog_primary_multiclass.rds` (read-only).
Outputs: `outputs/tables/eda07_*.csv` (11), `outputs/figures/eda07_*.png` (6).

## Purpose

Establish whether a classifier trained on the 247,406 single-species
recordings can be meaningfully evaluated as a ranked retrieval system on the
multi-species recordings, and define what that evaluation can and cannot
measure.

---

## Headline findings

1. **The extension is a clean external evaluation set.** Its 213,675 events
   share no `eventID` with the primary cohort, so no recording is both trained
   on and evaluated against.
2. **Only 59.6% of it is strictly evaluable.** 127,322 events have every
   detected species inside the 18-class vocabulary; the other 86,353 contain at
   least one species the model can never predict.
3. **Recall@k has a hard ceiling below 1.** Every eligible event holds at
   least two species, so mean Recall@1 cannot exceed **0.438** and Recall@3
   cannot exceed **0.973**, however good the model is.
4. **The strictly evaluable subset is not a representative subsample.** It is
   systematically cooler, drier and further south than the events it excludes.
   This interacts directly with the project's central geography question.
5. **Eligibility varies enormously by species** — from 95.8% of *Litoria
   ewingii* appearances down to 16.1% for *Litoria moorei*. Per-species Recall@k
   is therefore measured on very unequal samples.

---

## 1. How many species occur per recording

Table: `eda07_species_per_event.csv`. Figure: `eda07_species_per_event.png`.

| Species detected | Events | % of extension |
| ---: | ---: | ---: |
| 2 | 115,818 | 54.2 |
| 3 | 54,482 | 25.5 |
| 4 | 26,211 | 12.3 |
| 5 | 11,158 | 5.2 |
| 6+ | 6,006 | 2.8 |

The distribution is steep: four out of five multi-species recordings contain
two or three species. The maximum is 13.

---

## 2. Recall@k eligibility

Tables: `eda07_eligibility_by_event_size.csv`, `eda07_nonvocabulary_partners.csv`.

An event is `recall_at_k_eligible` when every species detected in it belongs to
the 18-class vocabulary. Eligibility collapses as recordings get richer:

| Species detected | Eligible % |
| ---: | ---: |
| 2 | 75.1 |
| 3 | 52.1 |
| 4 | 35.0 |
| 5 | 20.7 |
| 6 | 10.5 |
| 7 | 4.2 |
| 8 | 0.7 |
| 9+ | 0.0 |

This is a mechanical consequence of the 2,000-event selection threshold, not a
data problem: the more species a recording holds, the more chances it has to
include one of the 124 non-vocabulary species.

**The species responsible.** 142 distinct species appear in the extension, 124
of them outside the vocabulary. A small number drive most exclusions:

| Non-vocabulary species | Events | % of ineligible events |
| --- | ---: | ---: |
| *Litoria tyleri* | 13,787 | 16.0 |
| *Litoria latopalmata* | 10,759 | 12.5 |
| *Uperoleia laevigata* | 8,332 | 9.7 |
| *Uperoleia fusca* | 7,879 | 9.1 |
| *Litoria adelaidensis* | 6,814 | 7.9 |
| *Rhinella marina* | 5,648 | 6.5 |

Most ineligible events are only just ineligible: 60,213 of them — 69.7% of the
partial-overlap group — are excluded by a **single** non-vocabulary species.

---

## 3. The Recall@k ceiling

Table: `eda07_recall_at_k_ceiling.csv`. Figure: `eda07_recall_at_k_ceiling.png`.

A top-k list of k species cannot recover n > k true species. Because every
eligible event contains at least two species, there is a ceiling on mean
Recall@k that belongs to the data, not to any model:

| k | Events fully recoverable | Max attainable mean Recall@k |
| ---: | ---: | ---: |
| 1 | 0.0% | 0.438 |
| 2 | 68.3% | 0.876 |
| 3 | 90.6% | 0.973 |
| 4 | 97.8% | 0.995 |
| 5 | 99.6% | 0.999 |

**This must be reported alongside any Recall@k result.** A model scoring
Recall@1 = 0.40 on this extension is at 91% of the achievable maximum, not
failing. Recall@3 and Recall@5 are the informative operating points; Recall@1
is close to meaningless here and should be reported as Top-1 accuracy against
the primary cohort instead.

---

## 4. Which species co-occur

Table: `eda07_cooccurrence_pairs.csv`. Figure: `eda07_cooccurrence_heatmap.png`.

Strongest associations by Jaccard:

| Pair | Co-occurring events | Jaccard |
| --- | ---: | ---: |
| *Crinia georgiana* + *Crinia glauerti* | 6,118 | 0.484 |
| *Litoria fallax* + *Litoria peronii* | 22,526 | 0.295 |
| *Crinia parinsignifera* + *Limnodynastes tasmaniensis* | 15,019 | 0.250 |
| *Crinia signifera* + *Limnodynastes tasmaniensis* | 26,544 | 0.243 |
| *Litoria caerulea* + *Litoria gracilenta* | 4,674 | 0.206 |

Hierarchical clustering on the co-occurrence matrix separates four groups that
map cleanly onto Australian regions:

- **South-west**: *Crinia glauerti*, *Crinia georgiana*, *Litoria moorei*.
  Near-total isolation from the other 15 species.
- **Northern/tropical**: *Litoria caerulea*, *Litoria gracilenta*,
  *Litoria pyrina*, *Litoria infrafrenata*.
- **Eastern coastal**: *Litoria fallax*, *Litoria peronii*,
  *Limnodynastes peronii*, *Adelotus brevis*.
- **South-eastern temperate**: *Crinia signifera*,
  *Limnodynastes tasmaniensis*, *Crinia parinsignifera*,
  *Limnodynastes dumerilii*, *Litoria ewingii*, *Litoria verreauxii*.

**Relevance to EDA-04/09.** Co-occurrence structure here is essentially
geographic structure. The block-diagonal pattern is independent corroboration
that the 18 classes are strongly spatially separated, which is exactly the
condition under which random validation flatters a model with latitude and
longitude in it. This supports treating the M3 vs M4 comparison under spatial
blocking as the decisive test.

---

## 5. Per-species representation

Table: `eda07_species_participation.csv`. Figure: `eda07_species_participation.png`.

Most target species appear in multi-species recordings more often than alone.
*Litoria verreauxii* (90.2%) and *Crinia parinsignifera* (87.9%) are recorded
in company nine times out of ten; only *Litoria infrafrenata* (40.2%) and
*Litoria quiritatus* (47.6%) are predominantly solitary.

Eligibility rates differ far more than participation rates:

| Highest eligibility | % | Lowest eligibility | % |
| --- | ---: | --- | ---: |
| *Litoria ewingii* | 95.8 | *Litoria moorei* | 16.1 |
| *Limnodynastes dumerilii* | 90.6 | *Litoria pyrina* | 28.3 |
| *Crinia signifera* | 81.0 | *Litoria caerulea* | 34.0 |
| *Litoria verreauxii* | 80.1 | *Litoria infrafrenata* | 38.7 |

A species living alongside many unselected species is under-represented in the
strict evaluation even when it is common. *Litoria moorei* contributes 4,090
multi-species appearances but only 659 evaluable ones. Per-species Recall@k for
the bottom group will be noisy and is not comparable with the top group.

---

## 6. Is the evaluable subset representative?

Tables: `eda07_eligible_vs_partial.csv`, `eda07_cohort_comparison.csv`.
Figure: `eda07_eligible_vs_partial.png`.

No. Medians, eligible vs partial-overlap:

| Variable | Eligible | Partial overlap |
| --- | ---: | ---: |
| Latitude | −34.49 | −30.44 |
| BIO1 annual mean temperature (°C) | 15.36 | 18.30 |
| BIO12 annual precipitation (mm) | 890 | 1,127 |
| Elevation (m) | 107 | 97 |

The eligible subset sits roughly four degrees further south, three degrees
cooler and 240 mm drier. This follows from the species-selection rule: the
2,000-event threshold favoured widespread temperate species, so recordings in
warmer, wetter northern assemblages are much more likely to contain an
unselected species.

**Consequence.** Strict Recall@k measures ranking quality in temperate
southern Australia, not nationally. Because the project's central question is
whether models generalise geographically, silently evaluating only on eligible
events would bias that answer in the direction the project is trying to test.

---

## 7. Training cohort vs extension

Table: `eda07_cohort_monthly_share.csv`. Figure: `eda07_cohort_monthly_share.png`.

Both cohorts span the same window (2017-11-10 to 2023-11-09) and are seasonal
in the same direction, but the extension is more sharply peaked: November holds
23.6% of eligible events against 19.2% of primary events, and the autumn–winter
trough is deeper. Multi-species recordings concentrate in peak spring chorus
conditions, when more species are calling at once.

Environmental missingness is *lower* in the extension (0.98% of eligible events)
than in the primary cohort (1.94%), consistent with EDA-06's expectation that
missingness sits at raster edges and coastal cells.

---

## Recommendations for the modelling stage

1. **Report the ceiling with every Recall@k number.** Either report raw
   Recall@k beside the attainable maximum, or report the normalised ratio
   (achieved ÷ ceiling). Do not present Recall@1 on this extension as a headline.
2. **Use k ∈ {3, 5}** as the primary operating points.
3. **Run both a strict and a restricted evaluation.**
   - *Strict*: the 127,322 eligible events, scoring recall over all detected species.
   - *Restricted*: all 213,675 events, scoring recall only over the target
     species present and ignoring non-vocabulary detections.

   The restricted variant covers the warmer northern events the strict subset
   drops. Agreement between the two supports a national claim; divergence is
   itself a reportable finding about where the vocabulary is thin.
4. **Report per-species Recall@k with its eligible sample size** so the
   low-eligibility species are not read as poor model performance.
5. **Keep the extension out of training entirely**, including any
   hyperparameter tuning, so it stays a genuine external evaluation.
6. **Do not treat a non-vocabulary detection as a false positive.** The model
   has no vocabulary entry for *Litoria tyleri*; failing to rank it is a
   scope limitation, not an error.

## Open questions

- Should the restricted evaluation weight events by `n_selected_species`, or
  weight every event equally? Equal weighting lets two-species events dominate.
- Is a spatially blocked Recall@k worth running, given that co-occurrence
  structure is largely geographic? This depends on EDA-09's block design.
- Would reporting Recall@k separately per co-occurrence cluster (section 4) be
  more informative than a single national number?

## Constraints respected

- `data/processed/` was read only; nothing was modified, filtered, imputed,
  scaled or balanced.
- No exact recording coordinates are published; all spatial content is
  aggregate summary statistics.
- Multi-species events were not expanded into contradictory training labels.
