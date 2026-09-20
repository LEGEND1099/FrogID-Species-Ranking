# EDA-10 — EDA synthesis and modelling handoff

## Purpose

EDA-10 closes the exploratory phase and converts EDA-02 through EDA-09B into
an explicit modelling specification.

No new exploratory analysis is introduced here. The purpose is to preserve the
data-driven chain:

**data -> EDA evidence -> modelling decision -> later evaluation**

The primary modelling question remains:

> Given the environmental, seasonal and geographic context of a FrogID
> recording, how effectively can a multiclass classifier distinguish among the
> 18 selected Australian frog species, and how do public geoprivacy protections
> constrain extension of that framework to threatened species?

The central methodological question is:

> Are models learning transferable environmental/seasonal context, or mainly
> exploiting geographic structure already represented in the training data?

---

## 1. Evidence synthesis

The EDA provides the following combined picture.

- **Target imbalance is substantial.** The 18-class primary cohort contains
  247,406 events. The largest class accounts for 35.38% of events, the top
  five account for 71.78%, and the largest-to-smallest class ratio is about
  40.6:1. Overall accuracy alone is therefore insufficient.
- **Season matters.** Species composition varies by month, with a
  species-by-month Cramer's V of about 0.197. Cyclic seasonal encoding is
  justified, while year should remain a robustness variable rather than a
  predictor.
- **Geography is strongly structured.** About 30.18% of primary events occur
  at repeated exact coordinates, recording effort is geographically
  concentrated, and species composition varies strongly across coarse cells.
- **Environment matters but is spatially structured.** Environmental
  predictors differ among species, but several are strongly correlated with
  latitude/longitude. Seventeen environmental pairs have |Spearman rho| >=
  0.80 and eight have |rho| >= 0.90.
- **BIO5/BIO6/BIO7 contain a near-exact dependency.**
  `BIO7 ~= BIO5 - BIO6` with maximum observed discrepancy about
  `1.43e-06`.
- **Environmental missingness is small but spatially concentrated.** 4,806 of
  247,406 events (1.94%) have all 22 environmental predictors missing.
  Complete-case restriction barely changes class or temporal composition, but
  the missing rows are geographically concentrated.
- **Multi-species recordings provide a disjoint ranking extension.** The
  extension has 213,675 events; 127,322 are strictly evaluable because all
  detected species are inside the 18-class vocabulary. Recall@3 and Recall@5
  have theoretical ceilings of approximately 0.973 and 0.999 respectively in
  the strict subset.
- **Public conservation applicability is constrained by geoprivacy.** The
  public FrogID release contains 6,749 raw recording events involving 24
  confirmed EPBC-listed taxa, but none survives the project's strict public
  spatial QC. This is an applicability limitation, not model failure.
- **Random and spatial validation answer different questions.** EDA-09
  supports 0.5-degree grouped, 3-fold validation as the primary spatial
  compromise, alongside ordinary event-level validation.
- **EDA-09B connects the story.** Multi-species co-occurrence is extremely
  strongly aligned with geographic footprint overlap (Spearman rho about
  0.95), while environment retains a smaller association with species
  composition after geography is controlled descriptively. In stable cells,
  geography-composition rho is about 0.719, environment-composition rho about
  0.503, and their descriptive partial correlations are about 0.611 and 0.173
  respectively.

The resulting modelling plan must therefore distinguish **predictive signal
available in familiar geographic contexts** from **signal that transfers when
geographic sharing is restricted**.

---

## 2. Final modelling cohorts

### 2.1 Primary single-species cohort

The primary modelling unit remains one FrogID recording event.

The target is `scientificName` with the frozen 18-class vocabulary.

For all feature-group and model comparisons involving environmental
predictors, use the common complete-case cohort:

- full primary events: 247,406;
- complete environmental events: 242,600;
- excluded environmental-missing events: 4,806 (1.94%).

Using one common 242,600-event cohort prevents apparent feature improvements
from being confounded with a change in the observations being evaluated.

The 4,806 excluded events should remain documented as a geographically
non-random loss of coverage.

### 2.2 Multi-species extension

The multi-species extension remains completely outside model fitting,
hyperparameter tuning and model selection.

It is used only after a final model specification has been chosen from the
primary single-species analysis.

---

## 3. Final feature-group progression

Use the following predeclared feature groups.

### M0 — prevalence baseline

No contextual predictors.

Within each development fold, rank species using training-fold class
prevalence only. Assessment-fold prevalence must never be used.

### M1 — seasonal context

Use the cyclic seasonal representation:

- `month_sin`
- `month_cos`
- `doy_sin`
- `doy_cos`

Raw `month` and `day_of_year` are not used in the primary model matrix. This
keeps the calendar circular and avoids simultaneously feeding both a linear
calendar code and its cyclic representation.

`year` remains excluded as a primary predictor.

### M2 — season + climate

M1 plus:

- BIO1-BIO19;
- `climatological_tavg_event_month`;
- `climatological_prec_event_month`.

The two event-month climate variables are climatological normals, not
event-day weather.

### M3 — season + climate + elevation

M2 plus:

- `elevation`.

### M4 — season + climate + elevation + coordinates

M3 plus:

- `decimalLatitude`;
- `decimalLongitude`.

The M3-versus-M4 contrast is the central feature experiment because it tests
whether explicit coordinates add value beyond environmental context.

---

## 4. Modelling experiment structure

To keep the experiment computationally realistic while retaining the
scientific comparisons, use two stages.

### Stage A — feature-group progression

Run **elastic-net multinomial regression** and **XGBoost** across M1-M4 under
both validation regimes.

These two models provide complementary views:

- elastic-net multinomial regression: regularised linear decision structure;
- XGBoost: nonlinear interactions and threshold effects.

M0 is included as the fold-specific prevalence baseline.

This stage answers whether adding climate, elevation and explicit coordinates
changes performance under conventional versus spatially grouped validation.

### Stage B — five-model benchmark

Compare the following five classifier families on **M3 and M4** under both
validation regimes:

1. elastic-net multinomial logistic regression;
2. PCA-LDA;
3. PCA-kNN;
4. random forest;
5. XGBoost gradient-boosted trees.

M3 and M4 are retained for the full five-model benchmark because EDA-05 and
EDA-09B show that environmental context contains species-related structure,
while EDA-04/09/09B show that explicit geography is the key methodological
contrast.

This design avoids the much larger and less informative Cartesian product of
five model families x four feature groups x two validation regimes while still
testing the complete M1-M4 progression using both a linear and nonlinear
reference model.

---

## 5. Model-specific preprocessing

All data-dependent preprocessing must be estimated using development/training
data only and then applied unchanged to the corresponding assessment data.

### 5.1 Elastic-net multinomial logistic regression

- standardise numeric predictors inside the training fold;
- retain the environmental variables, including the correlated BIO block;
- use elastic-net regularisation to control coefficient instability;
- tune regularisation strength and mixing parameter using training data only.

The BIO5/BIO6/BIO7 dependency is handled by regularisation rather than global
pre-removal.

### 5.2 PCA-LDA

LDA is sensitive to singular and highly correlated predictor matrices.

Therefore:

- standardise the environmental block inside the training fold;
- fit PCA to the environmental block using training data only;
- retain the minimum number of PCs explaining at least 95% of training-fold
  environmental variance;
- append non-environmental predictors for that feature group after appropriate
  scaling;
- fit LDA on the resulting full-rank representation.

This explicitly resolves the BIO5/BIO6/BIO7 dependency and broader BIO
correlation.

### 5.3 PCA-kNN

kNN is scale- and distance-sensitive.

Therefore:

- standardise predictors using training-fold parameters only;
- fit PCA to the environmental block using training data only;
- retain enough PCs for at least 95% of training-fold environmental variance;
- append scaled seasonal, elevation and coordinate predictors as applicable;
- tune `k` using development data only.

PCA is used here to prevent multiple highly correlated BIO variables from
dominating Euclidean distance.

### 5.4 Random forest

- no standardisation;
- retain the original environmental variables;
- retain correlated BIO predictors, including BIO5/BIO6/BIO7;
- tune a small predeclared set of tree-complexity parameters using development
  data only.

Tree importance must not be interpreted as a causal measure because correlated
predictors can share or redistribute importance.

### 5.5 XGBoost

- no standardisation is required for tree splitting;
- retain the original environmental variables;
- retain the correlated BIO block;
- tune a bounded predeclared hyperparameter grid using development data only;
- use early stopping or equivalent training controls only within development
  data.

---

## 6. Class imbalance decision

Do **not** oversample, undersample or create synthetic observations in the
primary benchmark.

Reasons:

- EDA-02 establishes imbalance but does not show that resampling is required;
- resampling could distort real geographic and seasonal prevalence structure;
- the project is explicitly interested in ranking species under the observed
  FrogID distribution.

Primary models therefore train on the natural class distribution.

Class imbalance is handled primarily through **evaluation**, not by silently
changing the training population:

- Macro-F1 is the primary classification metric;
- per-class recall is always reported;
- overall accuracy is secondary;
- ranking metrics are reported separately.

For model families with native class-weight support, a class-weighted version
may be run later as a **sensitivity analysis**, but it is not part of the
primary five-model benchmark and must not replace the natural-prevalence
result.

No weighting choice may use an outer assessment fold.

---

## 7. Validation design

Two outer validation regimes are required.

### 7.1 Conventional event-level validation

Use **3-fold stratified event-level cross-validation** on the 242,600-event
complete-case cohort.

Events are assigned independently subject to class stratification.

Repeated or nearby locations are intentionally allowed to occur in different
folds because this regime is the conventional reference condition.

Interpretation:

> Performance when assessment observations come from geographic contexts that
> can be similar to those represented during model development.

### 7.2 Spatially grouped validation

Use **3-fold validation grouped by 0.5-degree cells**.

Rules:

- every event from a given 0.5-degree cell must remain in the same outer fold;
- assign cells to folds with a fixed reproducible algorithm that attempts to
  balance total event counts and class representation without splitting cells;
- save the final fold assignment so every model and feature group uses exactly
  the same spatial folds;
- verify that every assessment fold contains all 18 target classes and that
  every corresponding development set contains all 18 classes;
- report per-fold class counts before fitting any model.

Interpretation:

> A harder assessment of transfer when exact coarse geographic cells are not
> shared between development and assessment data.

This is a **grouped spatial validation design**, not a claim that assessment
cells are geographically isolated from every nearby training cell.

### 7.3 Spatial sensitivity

A 1-degree grouped analysis may be run as a secondary sensitivity analysis if
actual fold construction retains adequate class support.

Two-degree grouping is not the primary design because EDA-09 found inadequate
effective support for several spatially concentrated species.

---

## 8. Hyperparameter tuning and leakage control

For every outer fold:

1. hold the outer assessment fold untouched;
2. tune hyperparameters using only the outer development data;
3. use an inner resampling scheme that follows the same broad grouping logic
   as the outer regime where feasible;
4. estimate scaling, PCA, class weights if tested, and all other
   data-dependent transformations inside the training portion only;
5. refit the selected configuration on the full outer development fold;
6. produce predictions once for the untouched outer assessment fold.

Persist:

- fold IDs;
- random seeds;
- preprocessing parameters;
- selected hyperparameters;
- outer-fold predictions.

The multi-species extension must not participate in any of these steps.

---

## 9. Evaluation metrics

### 9.1 Primary single-species metrics

**Primary model-selection metric**

- Macro-F1.

Macro-F1 is selected because the class distribution is strongly imbalanced and
the project should not select a model solely by performance on common species.

**Required secondary metrics**

- accuracy;
- per-class recall;
- balanced accuracy;
- mean reciprocal rank (MRR);
- Top-3 accuracy;
- Top-5 accuracy.

Always report assessment sample size and, where possible, fold-level
variability.

Top-5 and accuracy must be interpreted alongside the class distribution
because the five most frequent classes already contain about 71.8% of the
primary observations.

### 9.2 Confusion analysis

For the final candidate models, inspect:

- confusion matrix;
- per-class recall;
- common confusion pairs;
- whether errors correspond to species with strongly overlapping geographic or
  environmental footprints.

This is post-evaluation interpretation and must not be used to redefine the
target classes after seeing results.

---

## 10. Model-selection rule

The primary final-model decision is based on **Macro-F1 under 0.5-degree
grouped spatial validation**.

Supporting considerations are:

- MRR and Top-3 ranking performance under spatial validation;
- the size of the random-versus-spatial performance gap;
- per-class recall stability;
- computational cost and reproducibility.

Accuracy alone cannot select the final model.

If M4 improves strongly under event-level validation but provides little or no
improvement over M3 under spatial validation, interpret the coordinate gain as
primarily tied to already represented geographic structure rather than as
evidence of superior spatial transfer.

If M3 remains competitive under spatial validation, that supports the value of
environmental context beyond explicit position.

---

## 11. Temporal robustness

`year` is not used as a predictor.

After outer-fold predictions are available, report the selected model's
out-of-fold performance by complete calendar year for **2018-2022**.

The partial 2017 and 2023 periods may be shown separately but must be labelled
as incomplete and should not be compared directly with full years.

This gives a temporal robustness check without introducing an additional model
selection pathway or a potentially misleading partial-year holdout.

---

## 12. Multi-species ranking evaluation

Only the final selected model specification is evaluated on the disjoint
multi-species extension.

Run two views.

### 12.1 Strict evaluation

Use the 127,322 events for which every detected species is in the 18-class
vocabulary.

Primary metrics:

- Recall@3;
- Recall@5.

Report the structural ceilings alongside results:

- maximum attainable mean Recall@3: approximately 0.973;
- maximum attainable mean Recall@5: approximately 0.999.

Also report:

- per-species Recall@k;
- eligible sample size for each species;
- performance by number of species detected per event.

### 12.2 Restricted evaluation

Use all 213,675 extension events.

Score Recall@3 and Recall@5 only against target-vocabulary species present in
the recording; detections outside the 18-class vocabulary are ignored rather
than treated as model errors.

### 12.3 Weighting decision

Use **equal event weighting** as the primary multi-species summary.

Do not introduce an arbitrary weight based on the number of species in an
event.

Instead, report event-size-stratified results so that the dominance of
two-species recordings remains visible.

### 12.4 Interpretation

The strict and restricted evaluations answer different scope questions and
must both be labelled clearly.

Because EDA-09B shows that co-occurrence is extremely strongly associated with
geographic footprint overlap, cluster-specific results must not be interpreted
as evidence of ecological interaction without additional analysis.

---

## 13. Conservation and geoprivacy handoff

EPBC status remains metadata only and is never a predictor.

The final report should distinguish:

1. predictive performance for the public, spatially eligible 18-species
   modelling cohort; and
2. conservation applicability to confirmed EPBC-listed taxa.

The public data contain 6,749 raw recording events involving 24 confirmed
listed taxa, but none survives the strict public spatial QC.

Therefore:

- do not train a threatened-species spatial model from reconstructed or
  approximated locations;
- do not claim threatened-species predictive performance;
- state that public geoprivacy appropriately limits spatial precision for
  sensitive records;
- state that the same protection prevents direct evaluation of this
  public-coordinate spatial-context framework for confirmed listed taxa.

`Litoria verreauxii` remains an unresolved listed-subspecies-only case and must
not be described as confirmed species-level EPBC listed.

---

## 14. What the final report should show

Because the report is limited to six pages, figures should tell one connected
story rather than reproduce every EDA output.

A compact evidence sequence is:

1. **class distribution / imbalance** — establishes the multiclass evaluation
   challenge;
2. **mandatory missingness visual** — satisfies the dataset-quality
   requirement and justifies complete-case modelling;
3. **seasonal species-composition evidence** — justifies seasonal context;
4. **geographic structure / validation evidence** — motivates grouped spatial
   assessment;
5. **EDA-09B environmental-distance figure** — connects environment,
   geography and species composition;
6. **conservation/geoprivacy visual or concise numerical statement** — shows
   the public-data applicability limit.

The environmental correlation heatmap can be included if space permits, but
the main text can summarise the redundancy numerically.

---

## 15. Final modelling decision table

| Decision | Evidence | Final choice | Alternatives considered |
| --- | --- | --- | --- |
| modelling cohort | EDA-06 | 242,600 common complete-case primary events for fair M0-M4/model comparisons | model-specific row sets; imputation |
| seasonal representation | EDA-03 | cyclic month and day-of-year encodings; exclude year | raw month/day; year predictor |
| environmental missingness | EDA-06 | complete-case; no imputation | global imputation; model-native missing handling |
| scaling | EDA-05 | training-fold scaling for scale-sensitive/linear models | global scaling; no scaling |
| correlated BIO block | EDA-05 | model-specific handling | global deletion of correlated variables |
| BIO5/BIO6/BIO7 dependency | EDA-05 | PCA for LDA/kNN; regularisation for multinomial; retain for trees | global removal of one variable |
| class imbalance | EDA-02 | natural training distribution; no primary resampling; Macro-F1/per-class recall | over/undersampling; mandatory class weights |
| feature progression | EDA-03/05/09B | M0-M4 retained; M3-vs-M4 central | coordinates always in; coordinates always out |
| validation | EDA-04/09/09B | 3-fold event-level + 3-fold 0.5-degree grouped validation | random only; 1-degree primary; 2-degree primary |
| final model selection | EDA-02/09 | spatial Macro-F1 primary; ranking metrics secondary | accuracy-only selection |
| five classifier families | combined EDA | elastic-net multinomial, PCA-LDA, PCA-kNN, RF, XGBoost | single model family |
| temporal robustness | EDA-03 | report OOF metrics by complete year 2018-2022 | year as predictor; partial-year holdout |
| multi-species evaluation | EDA-07/09B | strict + restricted Recall@3/5, equal event weighting | train on multi-species events; count non-vocabulary species as errors |
| conservation claim | EDA-08 | public-data applicability limitation only | threatened-species performance claim |

---

## 16. Checks that remain for the modelling implementation

EDA is complete, but the following implementation checks must occur before
model fitting results are accepted:

1. construct the actual 0.5-degree three-fold assignment;
2. verify all 18 classes in every outer assessment and development partition;
3. inspect fold event counts and class balance;
4. lock and save fold IDs before comparing models;
5. predeclare bounded hyperparameter grids;
6. verify every scaling/PCA operation is fitted inside development data;
7. confirm no multi-species event enters fitting or tuning;
8. confirm no EPBC/privacy/generalisation field enters the predictor matrix;
9. store outer-fold probability/ranking predictions for reproducible metrics;
10. document runtime failures or model-family deviations rather than silently
    changing the comparison.

---

## 17. Boundary between EDA and modelling

EDA is now complete.

The exploratory phase established enough evidence to decide:

- how missingness is handled;
- how scale and correlation are handled;
- how class imbalance is evaluated;
- which feature groups are compared;
- which five model families are retained;
- how random and spatial validation differ;
- how multi-species ranking is evaluated;
- what temporal robustness check is required;
- what conservation claims the public data do and do not support.

No further exploratory analysis should be added unless a concrete modelling
failure reveals a previously unseen data issue.

The next phase is **formal model development, cross-validation and evaluation**
under the frozen handoff above.
