# EDA-06 findings — environmental missingness

Work package: EDA-06 (`docs/eda-plan.md`).

Script: `analysis/06_environmental_missingness.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

## Question

How is environmental missingness distributed across predictors, species, time
and geography, and would restricting modelling to complete environmental rows
materially alter the primary dataset?

## 1. Environmental missingness is all-or-nothing across the predictor block

Of 247,406 primary events:

- 242,600 (98.06%) contain all 22 environmental predictors;
- 4,806 (1.94%) have missing values.

Every affected event is missing all 22 environmental predictors.

There are no primary events with only a subset of environmental variables
missing.

This indicates a shared extraction/source-cell missingness pattern rather than
independent missingness in individual environmental variables.

## 2. Missingness differs among species but complete-case filtering barely
changes the class distribution

Species-specific missingness ranges from approximately 0.03% to 5.53%.

The highest observed rates are:

- Litoria quiritatus: 5.53%;
- Limnodynastes peronii: 3.71%;
- Litoria gracilenta: 3.12%;
- Litoria infrafrenata: 2.69%.

The species × missingness association has Cramer's V approximately 0.087,
indicating some but limited association.

More importantly for modelling, comparing the complete-case species
distribution with the full primary distribution gives TVD approximately
0.0049.

The largest change in any individual species share is approximately
0.329 percentage points.

Therefore removal of incomplete environmental rows would have only a very
small effect on the overall target-class distribution.

## 3. Temporal distortion from complete-case filtering is very small

Monthly missingness rates range from approximately 1.36% to 2.70%.

Yearly rates range from approximately 1.64% to 2.19%.

The associations are small:

- month × missingness Cramer's V: approximately 0.027;
- year × missingness Cramer's V: approximately 0.014.

Distributional change after complete-case restriction is also very small:

- month distribution TVD: approximately 0.0015;
- year distribution TVD: approximately 0.0008.

Complete-case restriction therefore has negligible effect on the observed
month and year distributions.

## 4. Missingness is geographically concentrated

Environmental missingness is not geographically uniform.

Of 318 occupied 1-degree cells, 78 contain at least one missing environmental
event.

The ten 1-degree cells with the largest missing-event counts contain
approximately 77.2% of all 4,806 missing events.

Among cells containing at least 20 events, the median missingness rate is zero,
while the maximum is approximately 62.2%.

The geographic visualisation is restricted to cells with at least 20 events
so that high percentages based on extremely small denominators do not dominate
the map.

This geographic concentration means the missing rows should not be described
as a simple random sample of the dataset.

## 5. Source-level preparation diagnostics are consistent with raster
boundary/mask effects

The existing WorldClim preparation diagnostics identified environmental
missingness from source raster NA cells rather than isolated missing
predictors.

Almost all missing source cells were adjacent to valid raster cells.

This is consistent with land-mask or raster-boundary behaviour in the
environmental source rather than random corruption of individual variables.

No interpolation was used during preparation, so these source NAs were
preserved rather than silently filled.

## Missing-data decision

For the primary modelling analysis, complete-case environmental modelling is
the most defensible default.

The evidence supporting this choice is:

- only 1.94% of primary events are affected;
- missingness occurs across the entire environmental block, so simple
  variable-specific imputation is not especially natural;
- class composition changes extremely little after complete-case restriction;
- month and year distributions also change negligibly;
- retaining imputed environmental values would require additional assumptions
  about environmental conditions at locations where the source rasters contain
  NA values.

However, complete-case analysis has a geographic limitation: missing events
are spatially concentrated.

The report should therefore disclose that the environmental modelling cohort
has slightly reduced coverage in particular geographic areas rather than
claiming the missingness is random.

## Modelling handoff

The planned modelling stage should:

- use the 242,600 complete environmental rows for models requiring
  environmental predictors;
- apply the same complete-case cohort consistently when comparing environmental
  feature groups;
- document the approximately 1.94% loss of primary events;
- retain the geographic missingness caveat;
- avoid ad-hoc interpolation or global imputation unless later modelling
  provides a specific justification.

Any future imputation method, if introduced, must be fitted using training data
only.

## Report-use recommendation

The row-level missingness-pattern figure directly satisfies the assignment
requirement to visualise missingness.

The geographic missingness map is useful as supporting evidence that
missingness is spatially concentrated.

The species-missingness figure is useful for internal interpretation but can
be omitted from the six-page report if space is limited because the class-
distribution distortion is already quantified numerically.

## Constraints respected

- No missing environmental value was imputed.
- No row was removed by the EDA script.
- No classifier was fitted.
- No exact locations are shown.
- The geographic map uses coarse 1-degree cells with at least 20 observations.
- The complete-case decision was made only after examining species, temporal
  and geographic effects.