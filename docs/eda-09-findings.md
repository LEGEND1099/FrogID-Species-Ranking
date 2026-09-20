# EDA-09 findings — validation-design diagnostics

Work package: EDA-09 (`docs/eda-plan.md`).

Script: `analysis/09_validation_design.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

Outputs:
- `outputs/tables/eda09_random_fold_spatial_sharing.csv`
- `outputs/tables/eda09_species_block_support.csv`
- `outputs/tables/eda09_block_scale_summary.csv`
- `outputs/tables/eda09_composition_distance_summary.csv`
- `outputs/tables/eda09_validation_summary.csv`
- `outputs/figures/EDA09/eda09_block_support.png`
- `outputs/figures/EDA09/eda09_composition_distance.png`

## Question

Given the spatial concentration identified in EDA-04, would ordinary
row-wise validation substantially share geographic context between folds, and
what spatial grouping scale retains enough support across the 18 target
species?

## 1. Ordinary row-wise folds would frequently split repeated locations

The primary cohort contains 188,063 exact coordinate groups, including 15,316
coordinates associated with more than one event.

Under independent row-wise assignment to folds, the probability that a
repeated coordinate group spans multiple folds is high.

| Folds | Repeated coordinate groups expected to span folds | Events at repeated coordinates expected to belong to spanning groups |
| ---: | ---: | ---: |
| 3 | 79.9% | 91.2% |
| 5 | 88.6% | 95.1% |
| 10 | 94.5% | 97.7% |

These are analytical expectations under uniform independent fold assignment,
not results from a fitted model or an observed cross-validation split.

At coarser geographic scales, essentially all observations belong to spatial
cells that would be expected to span multiple ordinary row-wise folds. This
means ordinary row-wise validation would generally permit training and
assessment observations from the same coarse geographic neighbourhood.

This does not make random validation invalid. It means that random validation
addresses prediction for observations drawn from spatial contexts already
represented in development data.

## 2. Species composition changes with geographic separation

Using all 289,941 pairs of occupied 0.5-degree cells, species-composition
difference was measured using total-variation distance (TVD).

TVD ranges from 0 for identical species-composition distributions to 1 for
completely non-overlapping distributions.

| Distance between cell centres | Median composition TVD |
| --- | ---: |
| <50 km | 0.274 |
| 50–100 km | 0.347 |
| 100–250 km | 0.500 |
| 250–500 km | 0.692 |
| 500–1000 km | 0.800 |
| 1000–2000 km | 0.973 |
| 2000+ km | 1.000 |

The Spearman correlation between inter-cell distance and composition TVD is
**0.642**.

The percentage of cell pairs sharing the same dominant species also declines
from 62.2% below 50 km to 33.5% at 250–500 km.

The first several hundred kilometres are the most relevant part of this
analysis for validation design: they show progressively weaker similarity in
species composition with spatial separation.

The 1000–2000 km and 2000+ km categories primarily demonstrate broad
continental-scale turnover and are not used to select a spatial block size.

These patterns are descriptive associations in FrogID recording composition
and should not be interpreted as causal ecological distance effects.

## 3. Candidate spatial block sizes involve a support/separation trade-off

All four candidate spatial resolutions retain multiple nominal occupied blocks
for every species, but the observations are unevenly distributed among those
blocks.

The effective number of blocks accounts for this unequal concentration.

| Block size | Occupied blocks | Minimum species effective blocks | Median species effective blocks |
| ---: | ---: | ---: | ---: |
| 0.25° | 1,872 | 4.85 | 58.87 |
| 0.5° | 762 | 3.90 | 27.34 |
| 1° | 318 | 2.55 | 13.89 |
| 2° | 132 | 2.08 | 6.44 |

At 0.25°, one species has fewer than five effective blocks, while all species
have at least three.

At 0.5°, three species have fewer than five effective blocks, but all remain
above three effective blocks.

At 1°, one species falls below three effective blocks and four fall below
five.

At 2°, three species fall below three effective blocks, eight below five and
12 below ten.

Larger blocks therefore provide stronger geographic grouping but increasingly
reduce independent geographic support for spatially concentrated species.

## Statistical interpretation

EDA-04 showed that recording locations are geographically concentrated and
that species composition is associated with location.

EDA-09 adds two pieces of evidence:

1. ordinary row-wise folds would frequently place observations sharing exact
   or coarse geographic context in different folds; and
2. species composition becomes progressively less similar as geographic
   separation increases.

Therefore, random event-level validation and spatially grouped validation test
different generalisation conditions.

Random validation remains useful as a conventional reference for prediction in
spatial contexts similar to those represented during development.

A spatially grouped assessment is additionally required if the project wants
to evaluate transfer to geographically separated observations.

## Validation plan supported by the diagnostics

Among the tested resolutions, **0.5-degree cells provide the most defensible
current compromise** between spatial grouping and class support.

The planned modelling stage should therefore compare:

- ordinary event-level validation as a conventional reference; and
- **3-fold validation grouped by 0.5-degree spatial cells**.

When the actual spatial folds are constructed, each fold must be checked to
ensure that all target classes have usable development and assessment
representation. The present effective-block diagnostics establish feasibility
but do not guarantee that every arbitrary fold allocation will be balanced.

A 1-degree grouped analysis may be used as a sensitivity analysis if class
support remains adequate after fold construction.

The diagnostics do not support selecting 2-degree cells as the primary design
because several geographically concentrated species have very low effective
block support at that resolution.

## Coordinate predictors

EDA-09 does not determine whether latitude and longitude should be included as
predictors.

The later modelling comparison should retain the planned M3 versus M4
contrast:

- M3: season + climate + elevation
- M4: season + climate + elevation + latitude/longitude

This allows the contribution of explicit coordinates to be examined under
both conventional and spatially grouped validation rather than assuming in
advance that coordinates should either be retained or removed.

## Report-use recommendation

For the six-page report, the effective-block support figure is the most
directly useful validation-design visual.

The distance-versus-composition figure can also support the rationale for
spatial evaluation, but interpretation should focus on the shorter-distance
pattern rather than the continental-scale 1000+ km bins.

The detailed random-fold sharing probabilities can be reported compactly in
text rather than requiring an additional figure.

## Constraints respected

- No classifier was fitted.
- No predictive performance was calculated.
- No coordinates were accepted or rejected as predictors.
- Exact coordinates and spatial-cell identifiers were not written to outputs.
- Validation decisions were made only after examining EDA-04 and EDA-09
  diagnostics.
- The processed dataset was read only.