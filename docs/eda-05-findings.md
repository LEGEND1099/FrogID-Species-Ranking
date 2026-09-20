# EDA-05 findings — environmental predictors

Work package: EDA-05 (`docs/eda-plan.md`).

Script: `analysis/05_environmental_predictors.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

## Question

How are the 22 environmental predictors distributed, how redundant are they,
how strongly do they differ among species, and how closely is environmental
structure associated with geography?

## 1. Environmental predictors differ substantially in scale and shape

The primary dataset contains 247,406 events. Environmental information is
complete for 242,600 events and missing for 4,806.

The 22 environmental predictors are measured on very different numerical
scales. Predictor standard deviations range from approximately 1.63 to
370.30, a ratio of approximately 227:1.

Several precipitation and elevation-related variables are strongly
right-skewed. Examples include BIO13, BIO16, elevation and climatological
event-month precipitation.

IQR-based flags identify substantial tails for some variables, but these
values are not treated as erroneous observations. The predictors describe
different Australian climatic and elevation regimes, so extreme values may
represent genuine environmental conditions.

### Modelling implication

Scale-sensitive methods such as kNN, PCA and linear/regularised classifiers
will require predictor scaling fitted within each training fold.

The EDA does not justify deleting observations simply because they lie outside
a univariate IQR rule.

## 2. The environmental predictor block contains substantial redundancy

Pairwise Spearman correlation shows strong dependence among several
environmental variables.

- 17 predictor pairs have absolute Spearman correlation at least 0.80.
- 8 pairs have absolute Spearman correlation at least 0.90.
- The strongest pair is BIO13 and BIO16 with rho approximately 0.990.
- Other very strong relationships include BIO1/BIO11, BIO14/BIO17,
  BIO1/BIO10 and BIO2/BIO7.

Correlation therefore cannot be ignored for model families that are sensitive
to multicollinearity or ill-conditioned covariance matrices.

However, correlation alone is not used to remove variables at the EDA stage.
Different planned model families tolerate redundancy differently.

## 3. BIO5, BIO6 and BIO7 have a near-exact linear dependency

A direct numerical diagnostic gives:

`max |BIO7 - (BIO5 - BIO6)| = 1.430511e-06`.

Therefore BIO7 is effectively determined by BIO5 minus BIO6 to the numerical
precision of these raster-derived predictors.

The PCA provides independent confirmation: the final principal component has
effectively zero variance and is dominated by loadings on BIO5, BIO6 and
BIO7.

### Modelling implication

Methods requiring a full-rank or well-conditioned predictor matrix, including
LDA and some regression-style classifiers, should not receive all three
variables unchanged.

The EDA does not yet select which variable should be removed or transformed.
That choice should be model-specific and recorded in the modelling handoff.

## 4. Species occupy different environmental regions

Descriptive between-species variance shares indicate substantial differences
in environmental distributions among the 18 target species.

The largest values are:

| Predictor | Between-species variance share |
| --- | ---: |
| BIO15 | 0.600 |
| BIO18 | 0.547 |
| climatological event-month temperature | 0.544 |
| BIO1 | 0.538 |
| BIO11 | 0.525 |
| BIO10 | 0.498 |

Species-level median/IQR plots show that some species occupy noticeably
different environmental ranges while others overlap considerably.

These results establish association between species identity and environmental
context. They are descriptive and are not classifier-performance estimates.

## 5. Environmental structure is strongly associated with geography

Several environmental predictors show strong Spearman relationships with
coordinates.

Examples include:

- BIO10 versus latitude: rho approximately 0.850;
- BIO1 versus latitude: rho approximately 0.848;
- BIO8 versus latitude: rho approximately 0.824;
- BIO18 versus longitude: rho approximately 0.796.

The strongest absolute environmental-coordinate correlation is approximately
0.850.

Environmental context therefore contains substantial geographic structure.
Environmental effects and explicit coordinate effects should not be treated
as completely independent sources of information.

### Modelling implication

The planned nested comparison remains important:

- M3: season + climate + elevation;
- M4: season + climate + elevation + latitude/longitude.

The effect of adding explicit coordinates should be compared under both
ordinary and spatially grouped validation.

## 6. PCA confirms lower-dimensional environmental structure

PCA was performed after centring and scaling the 22 complete environmental
variables for exploratory purposes.

Variance explained:

- PC1: 45.4%;
- PC2: 21.0%;
- PC1 + PC2: 66.4%;
- first 4 PCs: 84.9%;
- first 6 PCs: 92.5%;
- first 8 PCs: 97.1%.

PC1 is also strongly associated with latitude
(Spearman rho approximately -0.790), while PC3 is associated with longitude
(rho approximately -0.572).

The PCA therefore reinforces both predictor redundancy and the geographic
structure of environmental variation.

PCA is not automatically selected as the modelling representation. It remains
an option for model families that benefit from decorrelated or lower-
dimensional predictors.

## Statistical interpretation

Environmental predictors provide substantial descriptive separation among
species, but the predictor set is highly redundant and strongly tied to
geography.

The evidence supports model-specific preprocessing rather than one universal
transformation for all classifiers.

## Modelling handoff

The later modelling stage should:

- scale predictors within training folds for scale-sensitive models;
- explicitly handle the BIO5/BIO6/BIO7 dependency for full-rank-sensitive
  models;
- consider regularisation, selective variable removal or PCA where appropriate;
- allow tree-based models to retain redundant predictors unless empirical
  comparison indicates otherwise;
- retain the M3 versus M4 feature-group comparison;
- fit every data-dependent preprocessing step using training data only.

## Constraints respected

- No classifier was fitted.
- No predictor was removed.
- PCA was exploratory only.
- IQR flags were not treated as automatic outliers.
- No environmental value was imputed.
- No modelling performance was reported.