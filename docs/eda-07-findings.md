# EDA-07 findings — multi-species recording structure

Work package: EDA-07 (`docs/eda-plan.md`).
Script: `analysis/07_multispecies_eda.R`.
Inputs: `data/processed/frog_multispecies_extension.rds`,
`data/processed/frog_primary_multiclass.rds` (read-only).
Outputs: `outputs/tables/eda07_*.csv` (11), `outputs/figures/EDA07/eda07_*.png` (7).

## Purpose

Establish whether a classifier trained on the 247,406 single-species
recordings can be meaningfully evaluated as a ranked retrieval system on the
multi-species recordings, and define what that evaluation can and cannot
measure.

---

## Headline findings

1. **The multi-species extension is disjoint from the primary cohort.** Its 213,675 events
   share no eventID with the 247,406 primary single-species events.
   This makes it suitable for a future out-of-cohort ranking evaluation,
   provided its different composition is acknowledged.
2. **Only 59.6% of it is strictly evaluable.** 127,322 events have every
   detected species inside the 18-class vocabulary; the other 86,353 contain at
   least one species the model can never predict.
3. **Recall@k has a k-dependent structural ceiling.** Every eligible event holds at
   least two species, so mean Recall@1 cannot exceed **0.438** and Recall@3
   cannot exceed **0.973**, however good the model is.
4. **The strictly evaluable subset differs materially from the excluded partial-overlap events.**
   Its observed locations and environmental summaries are further south, cooler and drier,
   so evaluation on this subset would not have the same covariate distribution as the full multi-species extension.
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

**Selected-species count.** Counting only the 18 target species per event
(same table, `target_species_detected` rows):

| Target species detected | Events | % of extension |
| ---: | ---: | ---: |
| 1 | 40,145 | 18.8 |
| 2 | 113,455 | 53.1 |
| 3 | 42,027 | 19.7 |
| 4 | 14,052 | 6.6 |
| 5+ | 3,996 | 1.9 |

Nearly one event in five contains only one target species, the rest of its
detections being non-vocabulary. Those events are all partial-overlap, so they
have a well-defined target label but are excluded from strict Recall@k.

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

This is an expected consequence of evaluating against a vocabulary restricted
to the 18 selected classes: as the number of detected species in an event increases,
there are more opportunities for at least one detection to fall outside that vocabulary.

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

Future Recall@k results should be interpreted alongside these structural ceilings.
Recall@1 has a maximum attainable mean recall of only 0.438, while the ceilings
for Recall@3 and Recall@5 are 0.973 and 0.999 respectively. This provides a
data-driven reason to prioritise k = 3 and 5 in the later evaluation plan.

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

Hierarchical clustering of the Jaccard co-occurrence matrix shows several clear groups of
species that are frequently detected together. Because this analysis clusters species using
co-occurrence only, it does not by itself establish that the groups are geographic. The pattern
is consistent with spatial structuring, which should be checked directly in EDA-04 using the
geographic data.

**Relevance to EDA-04/09.** The strong block structure provides a data-driven reason to test
whether these co-occurrence groups also have distinct spatial distributions. If EDA-04 confirms
strong geographic separation, that evidence can then be used to justify spatially aware
validation in the later project plan.

---

## 5. Which exact species combinations are common

Table: `eda07_top_combinations.csv` (top 30 exact combinations, listed both
over all detected species and over target species only).

The most common exact combinations across all detected species are:

| Combination | Events | % of extension |
| --- | ---: | ---: |
| *Crinia signifera* + *Limnodynastes peronii* | 10,524 | 4.9 |
| *Crinia signifera* + *Limnodynastes tasmaniensis* | 7,965 | 3.7 |
| *Crinia signifera* + *Litoria ewingii* | 7,642 | 3.6 |
| *Crinia signifera* + *Litoria verreauxii* | 5,288 | 2.5 |
| *Crinia signifera* + *Limnodynastes dumerilii* | 5,109 | 2.4 |

All of the top ten are pairs, and *Crinia signifera*, the most common single
species, is in six of them. Combinations are dominated by two-species
pairings within the same co-occurrence groups (section 4). *Litoria fallax* + *Litoria
peronii* is 9,299 events among target species only but just 4,088 when all
detected species must match, because they are often joined by a non-vocabulary
species.

---

## 6. Per-species representation

Table: `eda07_species_participation.csv`. Figure: `eda07_species_participation.png`.

Within the retained clean primary and multi-species cohorts, most target species
appear in multi-species recordings more often than alone.
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

Species that frequently co-occur with species outside the 18-class vocabulary are
under-represented in the strict evaluation subset. *Litoria moorei* contributes 4,090
multi-species appearances but only 659 evaluable ones. Per-species Recall@k for
low-eligibility species will be estimated from much smaller samples, so it should
be reported with the corresponding eligible sample size and interpreted with greater uncertainty.

---

## 7. Is the evaluable subset representative?

Tables: `eda07_eligible_vs_partial.csv`, `eda07_cohort_comparison.csv`.
Figure: `eda07_eligible_vs_partial.png`.

The two subsets differ materially on several observed covariates.
Medians, eligible vs partial-overlap:

| Variable | Eligible | Partial overlap |
| --- | ---: | ---: |
| Latitude | −34.49 | −30.44 |
| BIO1 annual mean temperature (°C) | 15.36 | 18.30 |
| BIO12 annual precipitation (mm) | 890 | 1,127 |
| Elevation (m) | 107 | 97 |

The eligible subset is roughly four degrees further south in median latitude,
about three degrees cooler in BIO1 and around 240 mm drier in BIO12. These are
substantial descriptive shifts. The mechanism should be investigated in EDA-04/05
rather than assumed from this analysis alone.

**Consequence.** A strict Recall@k evaluation would place substantially more weight on
cooler and more southerly recording contexts than the full multi-species extension.
That scope difference should therefore be reported alongside future Recall@k results.

---

## 8. Primary cohort vs multi-species extension

Tables: `eda07_cohort_monthly_share.csv`, `eda07_cohort_comparison.csv`,
`eda07_cohort_overview.csv`. Figures: `eda07_cohort_monthly_share.png`,
`eda07_cohort_environment.png`.

**Environment.** Medians, primary single-species cohort vs all extension events
vs eligible extension events:

| Variable | Primary | Extension (all) | Extension (eligible) |
| --- | ---: | ---: | ---: |
| Latitude | −33.75 | −33.43 | −34.49 |
| BIO1 annual mean temperature (°C) | 17.13 | 17.13 | 15.36 |
| BIO12 annual precipitation (mm) | 1,002 | 987 | 890 |
| Elevation (m) | 76 | 98 | 107 |

On these selected median summaries, the full extension is relatively similar
to the primary cohort, whereas the eligible subset shows a clearer shift.
These summaries do not establish that the full distributions are identical,
but they show that restricting to Recall@k-eligible events changes the observed
environmental composition more noticeably. Median elevation is also somewhat
higher in the extension.

**Season.** Both cohorts span the same window (2017-11-10 to 2023-11-09) and
are seasonal in the same direction, but the extension is more sharply peaked:
November holds 23.5% of eligible events against 19.2% of primary events, and
the autumn–winter trough is deeper. Multi-species recordings are more concentrated
in spring. This may reflect a combination of frog calling activity and FrogID
recording effort, so these counts should not be interpreted as pure phenology.

Environmental missingness is lower in the eligible extension (0.98%) than in
the primary cohort (1.94%). EDA-06 should determine whether this difference is
explained by geography, raster coverage or species composition rather than
assuming the mechanism here.

---

## Recommendations for the modelling stage

1. **Report the theoretical ceiling alongside future Recall@k results.**
   This is especially important for small k, where the number of species
   detected in each recording constrains the maximum attainable recall.
2. **Use k ∈ {3, 5}** as the primary operating points.
3. **Run both a strict and a restricted evaluation.**
   - *Strict*: the 127,322 eligible events, scoring recall over all detected species.
   - *Restricted*: all 213,675 events, scoring recall only over the target
     species present and ignoring non-vocabulary detections.

   The restricted variant covers the warmer northern events the strict subset
   drops. Comparing the two would show how sensitive future evaluation is
   to the 18-class vocabulary restriction. Neither result alone should be
   interpreted as evidence of national ecological coverage.
4. **Report per-species Recall@k with its eligible sample size** so the
   low-eligibility species are not read as poor model performance.
5. **Keep the multi-species extension out of future model fitting and hyperparameter tuning**
   so it remains a genuinely disjoint evaluation extension.
6. **Do not treat a non-vocabulary detection as a false positive.** The model
   has no vocabulary entry for *Litoria tyleri*; failing to rank it is a
   scope limitation, not an error.

## Open questions

- Should the restricted evaluation weight events by `n_selected_species`, or
  weight every event equally? Equal weighting lets two-species events dominate.
- Is a spatially blocked Recall@k worth running, if EDA-04 confirms that the
  observed co-occurrence structure is strongly geographic? This depends on EDA-09's
  block design.
- Would reporting Recall@k separately per co-occurrence cluster (section 4) be
  more informative than a single national number?

## Constraints respected

- `data/processed/` was read only; nothing was modified, filtered, imputed,
  scaled or balanced.
- No exact recording coordinates are published; all spatial content is
  aggregate summary statistics.
- Multi-species events were not expanded into contradictory training labels.
- No classification model was fitted in EDA-07; all Recall@k quantities reported
  here are structural properties or theoretical ceilings derived from the data.
