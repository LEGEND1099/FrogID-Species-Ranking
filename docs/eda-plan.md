# FrogID exploratory data analysis plan

## Purpose

This document is an execution plan, not a fixed statistical specification.

The objective of EDA is to understand the prepared FrogID analysis data well
enough to make defensible decisions about:

- class imbalance;
- environmental missingness;
- seasonal structure;
- geographic structure;
- predictor redundancy;
- possible geographic memorisation;
- model-validation strategy;
- multi-species evaluation;
- conservation/geoprivacy interpretation.

Findings from earlier EDA work packages may change later analysis choices.
Any change should be documented rather than forcing the original plan to
remain unchanged.

No model should be selected because it performs well on exploratory test data.
EDA should inform preprocessing and validation design; final model comparison
must remain separate.

---

# Shared analysis inputs

Primary labelled dataset:

`data/processed/frog_primary_multiclass.rds`

Primary predictor matrix:

`data/processed/frog_primary_predictors.rds`

Multi-species extension:

`data/processed/frog_multispecies_extension.rds`

Multi-species predictors:

`data/processed/frog_multispecies_predictors.rds`

Species metadata:

`data/processed/species_metadata.rds`

Useful preparation summaries are already available under:

`outputs/tables/`

The preparation pipeline and certified source/data details are documented in:

- `docs/data-pipeline.md`
- `docs/data-summary.md`
- `docs/project-status.md`

---

# EDA operating rules

1. Do not modify the frozen raw source data.
2. Do not publish sensitive event-level locations.
3. Do not treat missing species labels as ecological absences.
4. Do not infer abundance from number of FrogID records.
5. EPBC status must never become a model predictor.
6. Observer identity must never become a model predictor.
7. Do not silently remove rows with environmental NA values.
8. Record every preprocessing decision motivated by EDA.
9. Prefer aggregate or coarse spatial visualisation over exact point maps.
10. Keep exploratory observations distinct from confirmatory/model-evaluation
    claims.

---

# Suggested analysis-file structure

Create EDA scripts incrementally under `analysis/`.

Suggested files:

```text
analysis/
├── 01_data_audit.R
├── 02_class_structure.R
├── 03_temporal_eda.R
├── 04_spatial_eda.R
├── 05_environmental_eda.R
├── 06_missingness_eda.R
├── 07_multispecies_eda.R
├── 08_conservation_privacy_eda.R
├── 09_validation_design.R
└── 10_eda_synthesis.R
```

The exact filenames may change if a different organisation becomes clearer
during analysis.

Figures should go under:

`outputs/figures/`

New aggregate EDA tables should go under:

`outputs/tables/`

Do not overwrite preparation-certification tables with exploratory outputs.

---

# EDA-01 — Analysis data audit

## Goal

Confirm the analysis objects entering EDA and produce a compact analysis-ready
overview.

## Questions

- Are dimensions unchanged from the certified preparation stage?
- Are the 18 target classes unchanged?
- Are predictor names/types exactly as expected?
- Which columns contain missing values?
- Are there obvious impossible numeric values or coding issues?
- Are all predictor-only matrices row-aligned with their labelled datasets?

## Suggested outputs

Tables:

- `eda_dataset_overview.csv`
- `eda_predictor_types.csv`
- `eda_missingness_overview.csv`

Optional figure:

- missingness overview plot

## Dependency

None beyond the certified processed files.

## Decision points

Only investigate discrepancies. Do not redefine the cohort during this step.

---

# EDA-02 — Target/class structure and imbalance

## Goal

Understand the 18-class target distribution before choosing training metrics,
resampling or class-weighting strategies.

## Questions

- How imbalanced is the target?
- How much of the dataset is accounted for by the largest classes?
- Are there extremely small classes relative to the dominant species?
- How do class distributions vary across year, month and broad geography?
- Is imbalance likely to make plain accuracy misleading?

## Core analyses

- event count per species;
- class percentage;
- cumulative class percentage;
- max/min ratio;
- class counts by year;
- class counts by month;
- broad class distribution by state.

## Suggested figures

- ordered class-count bar chart;
- class-share / cumulative-share chart;
- species-by-year heatmap;
- species-by-month heatmap.

## Likely downstream decisions

Potentially motivates:

- Macro-F1 alongside accuracy;
- balanced accuracy or per-class recall as diagnostics;
- class weights;
- stratified folds.

Do not apply balancing automatically. First establish whether it is required.

---

# EDA-03 — Temporal and seasonal structure

## Goal

Characterise recording seasonality and determine whether seasonal predictors
contain meaningful signal.

## Questions

- How strongly seasonal are FrogID recordings overall?
- Does seasonality differ by species?
- Are some species concentrated in narrow calling seasons?
- Has recording volume changed substantially by year?
- Could year or temporal collection effects create distribution shift?

## Core analyses

- recordings per month;
- recordings per year;
- species × month counts;
- species × month proportions;
- day-of-year distributions for major species;
- compare raw/clean/primary temporal distributions where useful.

## Suggested figures

- monthly recording counts;
- annual recording counts;
- species × month heatmap;
- selected species day-of-year density/ridge plots.

## Important interpretation

The temporal predictors use supplied `eventDate`.

Do not infer local recording hour from `eventTime`; supplied time fields mix
UTC and explicit offsets and `local_hour` was deliberately excluded.

## Possible follow-up

If strong year effects appear, consider whether temporal holdout analysis is
worth adding later as a robustness check.

---

# EDA-04 — Geographic structure

## Goal

Understand how strongly species labels and observation density are structured
by location.

This is central to the question:

> Are models learning environmental/seasonal context, or simply memorising
> Australian geography?

## Questions

- Where is FrogID sampling concentrated?
- How geographically restricted are individual target species?
- How much overlap exists between species?
- Are some classes nearly separable using location alone?
- Are repeated/nearby points likely to make random validation optimistic?

## Core analyses

- event counts by state;
- coarse spatial observation density;
- species geographic ranges/bounding summaries;
- coarse species-density maps;
- geographic overlap among target species;
- repeated-coordinate frequencies;
- optionally nearest-neighbour or spatial-density diagnostics.

## Privacy rule

Do not publish exact sensitive point coordinates.

Use aggregate/coarse representations such as:

- hexagonal bins;
- gridded counts;
- state-level summaries;
- coarse bounding regions.

## Suggested figures

- Australia-wide observation-density hexbin;
- faceted coarse maps for selected target species;
- state × species heatmap;
- distribution of observations per repeated coordinate.

## Likely downstream decision

This work should directly inform the spatial-block validation design.

---

# EDA-05 — Environmental predictors

## Goal

Understand distributions, redundancy and ecological separation in the 22
WorldClim/elevation variables.

## Questions

- Are predictors strongly skewed?
- Are there extreme values?
- Which BIO variables are highly correlated?
- Are some variables effectively redundant?
- Do species occupy noticeably different environmental regions?
- Does environmental structure largely mirror geography?

## Core analyses

- univariate distributions;
- predictor correlation matrix;
- species-level medians/IQRs;
- selected environmental distributions by species;
- PCA of environmental variables;
- optional PCA visualisation by species/geographic region.

## Suggested figures

- correlation heatmap;
- environmental-variable distributions;
- species × selected-variable box/violin plots;
- PCA scatter/density plots.

## Important caution

BIO variables are expected to be highly correlated.

Do not remove variables merely because correlation exists. Use EDA to decide
whether dimensionality reduction, regularisation or selective removal is
needed for particular model families.

Tree models may tolerate redundancy differently from LDA, kNN or multinomial
regression.

---

# EDA-06 — Environmental missingness

## Goal

Decide how to handle the environmental NA rows without silently biasing the
analysis.

Current primary missingness:

4,806 / 247,406 events (approximately 1.94%).

## Questions

- Is missingness concentrated geographically?
- Is it concentrated in particular species?
- Is it concentrated near coastlines/islands/raster boundaries?
- Does removing incomplete rows materially alter class proportions?
- Is simple complete-case analysis defensible?
- Is imputation necessary?

## Core analyses

Compare complete vs incomplete rows by:

- species;
- month/year;
- state;
- broad geography;
- predictor values available outside the missing group where meaningful.

Use existing source-cell diagnostics from preparation.

## Possible decisions

Possible outcomes include:

- complete-case modelling;
- model-specific handling of NA;
- justified imputation.

No approach is predetermined.

Any chosen method must be fitted within training folds later to avoid leakage.

---

# EDA-07 — Multi-species recording structure

## Goal

Understand whether a classifier trained on single-species recordings can be
meaningfully evaluated as a ranked retrieval system on multi-species
recordings.

## Questions

- How many species occur per recording?
- Which species combinations are common?
- Which target classes co-occur most often?
- How representative are the 127,322 fully vocabulary-covered events?
- How do fully eligible events differ from partial-overlap events?
- Are some target species disproportionately observed in multi-species events?

## Core analyses

- species-per-event distribution;
- co-occurrence matrix/network;
- selected-species-count distribution;
- Recall@k eligibility by species;
- primary vs multi-species environmental/seasonal distributions.

## Suggested figures

- species-count histogram;
- species co-occurrence heatmap;
- eligible vs ineligible event comparison;
- primary vs multi-species distributions.

## Modelling consequence

The primary model is trained on single-species events.

Multi-species events are an **external ranking/retrieval-style evaluation
extension**, not contradictory duplicated training labels.

---

# EDA-08 — Conservation and geoprivacy

## Goal

Quantify what the public FrogID release permits and prevents for threatened
species.

## Established preparation result

There are 24 confirmed EPBC-listed FrogID taxa represented across 6,749 raw
recording events.

None survives the project's strict public spatial QC.

## Questions

- How does retention differ between listed and other/unresolved taxa?
- Which QC/privacy reasons explain the loss?
- How much overlap exists between uncertainty, obscuring and generalisation?
- At what stage does sequential QC appear to remove those events?
- How should this constrain claims about conservation applicability?

## Core analyses

Use the existing non-sensitive aggregate tables:

- `conservation_species_retention.csv`
- `conservation_category_retention.csv`
- `conservation_group_retention.csv`
- `conservation_qc_exclusion_summary.csv`

## Suggested figures

- raw-to-clean retention by conservation group;
- QC reason counts;
- Endangered vs Vulnerable recording counts;
- species-level retention plot if it can remain non-sensitive.

## Interpretation

Do not claim geoprivacy is an error.

Location suppression is likely deliberate protection of sensitive records.

The analysis should describe the trade-off:

> privacy protection appropriately reduces public spatial precision, but that
> same protection limits the ability to train or evaluate spatial-context
> ranking models for threatened taxa using the public release.

Do not report exact sensitive locations.

---

# EDA-09 — Validation-design diagnostics

## Goal

Use the preceding EDA to choose defensible validation strategies before model
comparison.

## Required comparison

At minimum, later modelling should compare:

### Random/event-level validation

Useful for conventional predictive evaluation, but potentially optimistic
when nearby recordings share strong spatial context.

### Spatially blocked validation

Tests generalisation to geographically separated areas and directly addresses
possible location memorisation.

## Feature-group experiments planned

The intended nested sequence is:

- M0 — species-prevalence baseline
- M1 — season
- M2 — season + climate
- M3 — season + climate + elevation
- M4 — season + climate + elevation + latitude/longitude

The difference between M3 and M4 is particularly important.

If latitude/longitude produces a very large improvement under random
validation but much less under spatial blocking, that is a substantive result
rather than merely a modelling inconvenience.

## Questions EDA should answer

- What block size is defensible?
- Can every important species be represented across folds?
- How many geographic regions/folds are feasible?
- Are some classes so spatially restricted that blocked evaluation becomes
  unstable?
- Should repeated coordinates be kept in the same fold?

The exact implementation should remain open until geographic EDA is complete.

---

# EDA-10 — EDA synthesis and modelling handoff

## Goal

Convert exploratory findings into explicit modelling decisions.

Create a short decision table with fields such as:

| Decision | Evidence | Choice | Alternatives considered |
| --- | --- | --- | --- |
| environmental NA handling | EDA-06 | TBD | complete case / imputation / model-native |
| scaling | EDA-05 | TBD | standardise / none |
| correlated BIO features | EDA-05 | TBD | retain / regularise / reduce |
| class imbalance | EDA-02 | TBD | weights / resampling / metric-only |
| spatial CV | EDA-04/09 | TBD | block size/folds |
| temporal robustness | EDA-03 | TBD | required / optional |
| models to retain | combined EDA | TBD | multinomial/LDA/kNN/RF/etc. |

## Deliverables

- final EDA figures;
- final EDA aggregate tables;
- written EDA findings;
- modelling/preprocessing decisions;
- unresolved questions;
- any justified modifications to the original modelling plan.

This should become the boundary between exploratory work and model comparison.

---

# Parallel-work guide

The following work packages can largely be done independently after EDA-01:

| Work package | Can start after | Main dependency |
| --- | --- | --- |
| EDA-02 class structure | EDA-01 | primary labels |
| EDA-03 temporal | EDA-01 | eventDate |
| EDA-04 geographic | EDA-01 | public clean coordinates |
| EDA-05 environmental | EDA-01 | predictor matrix |
| EDA-06 missingness | EDA-01 | environmental predictors |
| EDA-07 multi-species | EDA-01 | extension dataset |
| EDA-08 conservation/privacy | none | prepared aggregate tables |
| EDA-09 validation design | EDA-02 + EDA-04 | class + spatial findings |
| EDA-10 synthesis | all relevant EDA | combined findings |

This makes it possible for multiple people or agents to work concurrently
without requiring one enormous sequential analysis script.

---

# What is deliberately not fixed yet

EDA should remain open to changing:

- environmental NA handling;
- feature scaling;
- correlated-variable treatment;
- dimensionality reduction;
- class weights/resampling;
- exact spatial-block configuration;
- exact statistical/model families;
- which environmental variables receive detailed interpretation;
- whether temporal holdout analysis is useful;
- whether additional robustness analyses are justified.

The following should **not** change without revisiting the research design:

- presence-only interpretation;
- eventID as the recording unit;
- frozen 18-class objective selection rule;
- EPBC status excluded from predictors;
- privacy/generalisation fields excluded from predictors;
- observer identity excluded from predictors;
- multi-species events not expanded into contradictory training labels;
- sensitive exact locations not published.

---

# Completion criterion

EDA is complete when there is enough evidence to state, explicitly and
reproducibly:

1. how class imbalance will be handled;
2. how environmental missingness will be handled;
3. whether and how predictors will be scaled;
4. how correlated environmental predictors will be treated;
5. how random and spatial validation will be implemented;
6. which feature-group comparisons will be run;
7. which model families are justified;
8. how the multi-species extension will be evaluated;
9. what conservation/geoprivacy claims the public data support;
10. which questions remain outside the scope of the project.

At that point the project moves from EDA into formal model development and
evaluation.