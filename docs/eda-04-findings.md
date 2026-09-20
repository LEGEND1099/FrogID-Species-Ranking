# EDA-04 findings — geographic structure

Work package: EDA-04 (`docs/eda-plan.md`).

Script: `analysis/04_geographic_structure.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

Outputs:
- `outputs/tables/eda04_geographic_summary.csv`
- `outputs/tables/eda04_cell_structure_summary.csv`
- `outputs/tables/eda04_species_geographic_summary.csv`
- `outputs/tables/eda04_pairwise_cell_overlap.csv`
- `outputs/figures/EDA04/eda04_sampling_density_05deg.png`
- `outputs/figures/EDA04/eda04_species_coarse_footprints.png`
- `outputs/figures/EDA04/eda04_species_cell_overlap.png`

## Question

How geographically concentrated are the selected FrogID recordings, how much
spatial repetition exists, and how strongly is geographic location associated
with the species composition of the primary multiclass cohort?

## 1. Spatial sampling is highly uneven

The primary cohort contains 247,406 events at 188,063 distinct exact coordinate
pairs.

Of all events, **74,659 (30.18%)** occur at coordinate pairs that appear more
than once. A single exact coordinate appears in as many as **927 events**.

Aggregation to coarse spatial cells also shows strong geographic concentration.

| Cell size | Occupied cells | Top 10 cells' share of events |
| ---: | ---: | ---: |
| 0.25° | 1,872 | 25.60% |
| 0.5° | 762 | 40.11% |
| 1° | 318 | 52.58% |
| 2° | 132 | 74.88% |

The 0.5-degree recording-density map confirms that observations are concentrated
in particular parts of Australia rather than distributed uniformly across the
study region.

These are patterns of **FrogID recording activity**, not estimates of frog
abundance or population density.

## 2. Species composition varies across geographic cells

Overall species entropy is 3.214 bits.

After conditioning descriptively on coarse spatial cell identity, remaining
species entropy is:

| Cell size | Conditional entropy | Cell-species mutual information | Fraction of overall species entropy |
| ---: | ---: | ---: | ---: |
| 0.25° | 1.821 | 1.394 | 0.434 |
| 0.5° | 1.926 | 1.289 | 0.401 |
| 1° | 2.018 | 1.196 | 0.372 |
| 2° | 2.121 | 1.093 | 0.340 |

Thus, coarse location is substantially associated with which species is
recorded. The association persists across several grid resolutions.

These information quantities are descriptive association measures. They should
not be interpreted as the percentage of species identity causally explained by
geography or as predictive model performance.

Most observations are not in cells containing only one species. Although
approximately 29–34% of occupied cells contain only one selected species, such
cells account for only about 1–1.6% of all events.

Within cells, however, species composition is uneven: the dominant species
accounts for approximately 45–51% of observations when aggregated across the
different grid resolutions.

## 3. Geographic concentration differs strongly among species

The 18 species have very different observed geographic footprints.

At 0.5-degree resolution, examples of strong concentration include:

- *Crinia glauerti*: top 5 cells contain **89.8%** of its events
- *Litoria moorei*: **88.5%**
- *Crinia georgiana*: **85.2%**
- *Litoria infrafrenata*: **89.1%**

Other species are distributed across substantially larger numbers of cells.
For example, *Limnodynastes tasmaniensis* occurs across 433 occupied 0.5-degree
cells, while *Crinia signifera* occurs across 336.

The coarse species-footprint figure therefore shows that geographic
concentration is heterogeneous across classes rather than being a uniform
property of the dataset.

These footprints describe where FrogID observations occur in the public
dataset and should not be interpreted as complete biological range maps.

## 4. Geographic overlap varies greatly among species pairs

Across the 153 possible species pairs, overlap of occupied cells is generally
limited but highly variable.

At 1-degree resolution:

- median Jaccard overlap = **0.114**
- mean Jaccard overlap = **0.163**
- 56 of 153 pairs have **zero** occupied-cell overlap
- maximum Jaccard overlap = **0.875**

The highest-overlap pair is *Crinia glauerti* and *Crinia georgiana*, which
share 14 occupied 1-degree cells and have a Jaccard overlap of 0.875.

Other species pairs occupy largely or completely different coarse geographic
regions.

Therefore, geography does not separate every species equally. Some species have
strongly overlapping observed footprints, whereas others have little or no
coarse-cell overlap.

## Statistical interpretation

EDA-04 establishes three relevant characteristics of the primary cohort:

1. observations are spatially concentrated and exact locations are frequently
   repeated;
2. species composition is associated with coarse geographic location;
3. geographic overlap and concentration differ substantially among species.

Together, these findings show that observations cannot automatically be treated
as spatially interchangeable when designing later evaluation.

They do **not** establish that geographic coordinates should be included or
excluded as predictors, and they do not establish the appropriate spatial
validation method or block size.

## Implications for EDA-09 and project planning

EDA-09 should explicitly investigate whether the observed spatial structure
creates dependence that matters for the eventual validation design.

In particular, EDA-09 should examine:

- how recordings are distributed among candidate spatial blocks;
- whether each candidate blocking scheme preserves usable representation of the
  18 classes;
- how much spatial overlap would remain between development and assessment
  partitions under different designs;
- whether repeated/co-located recordings could place very similar observations
  on opposite sides of an ordinary random split.

The appropriate validation strategy and spatial scale should be selected only
after those diagnostics are examined.

Likewise, whether latitude and longitude should be used as modelling predictors
remains an open modelling-design question. EDA-04 demonstrates that they contain
substantial species-related spatial information, but it does not determine
whether using that information is desirable for the intended application.

## Report-use recommendation

The most informative EDA-04 figure for the six-page report is likely the
**species geographic-footprint figure** or the **pairwise overlap heatmap**,
because either directly connects geography with the multiclass outcome.

The overall sampling-density map is useful if the report needs to emphasise
sampling concentration, but the numerical concentration statistics may be
sufficient if figure space is limited.

## Constraints respected

- No classifier was fitted.
- No model performance was calculated.
- No validation strategy or spatial block size was selected.
- Latitude/longitude were not accepted or rejected as future predictors.
- Exact coordinate pairs were used only internally and were not written to
  aggregate outputs.
- The processed dataset was read only.