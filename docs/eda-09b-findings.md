# EDA-09B findings — integrated ecological versus geographic structure

Work package: EDA-09B, follow-up to EDA-04, EDA-05, EDA-07 and EDA-09.

Script: `analysis/09b_integrated_context_eda.R`.

Inputs:
- `data/processed/frog_primary_multiclass.rds`
- `outputs/tables/eda04_pairwise_cell_overlap.csv`
- `outputs/tables/eda07_cooccurrence_pairs.csv`

## Question

How much of the species structure identified in earlier EDA is geographically
organised, and does environmental context retain descriptive association with
species composition after geographic separation is approximately controlled?

Two linked questions are examined:

1. whether species that frequently co-occur in multi-species FrogID recordings
   also occupy overlapping geographic footprints; and
2. whether environmentally dissimilar geographic cells have more different
   species composition when geographic separation is held approximately
   constant.

No classifier is fitted and no predictive performance is estimated.

## 1. Multi-species co-occurrence is extremely strongly aligned with geography

The analysis links all 153 possible pairs among the 18 target species from
EDA-07 with their geographic occupied-cell overlap from EDA-04.

The association between multi-species co-occurrence Jaccard and geographic
footprint Jaccard is:

- 0.5-degree cells: Spearman rho = 0.955;
- 1-degree cells: Spearman rho = 0.948.

Using the geographic overlap coefficient instead of Jaccard gives similarly
strong associations:

- 0.5-degree cells: rho = 0.907;
- 1-degree cells: rho = 0.911.

Thus, species that are frequently recorded together also tend to occupy the
same parts of the public FrogID geographic footprint.

Examples include `Crinia georgiana` and `Crinia glauerti`, which have the
highest multi-species co-occurrence Jaccard (0.484) and very high geographic
overlap.

## Statistical interpretation of co-occurrence

The EDA-07 co-occurrence clusters should therefore not be interpreted as
evidence of ecological interaction by themselves.

Much of the observed co-occurrence structure is consistent with shared
geographic opportunity: species whose public recording footprints overlap
have more opportunity to appear in the same recording.

This does not establish that geography fully explains co-occurrence, but it
shows that geography is a major organising factor.

## 2. Environmental structure is lower-dimensional at the cell level

For the environmental-distance analysis, broad static environmental context
was represented using BIO1-BIO19 plus elevation.

The two event-month climatology variables were excluded from this particular
analysis to avoid mixing seasonal recording context into the broad
environment-geography comparison.

PCA was performed on median environmental values for occupied 0.5-degree
cells, giving each cell equal weight rather than allowing heavily sampled
cells to dominate the environmental representation.

Four principal components capture approximately 90.0% of the static
environmental variation across usable cells.

Environmental distance is therefore measured in these first four scaled PCA
dimensions.

## 3. Geography is strongly associated with both environment and species
composition

Of 762 occupied 0.5-degree cells:

- 760 contain usable static environmental information;
- 391 contain at least 20 recording events.

The stable-cell subset generates 76,245 cell pairs.

Across those stable pairs:

- environmental distance versus species-composition TVD:
  Spearman rho = 0.503;
- geographic distance versus species-composition TVD:
  rho = 0.719;
- geographic distance versus environmental distance:
  rho = 0.562.

Geography therefore has the stronger overall association with species
composition, while environmental context is itself substantially spatially
structured.

## 4. Environmental differences remain associated with composition after
accounting descriptively for geography

A descriptive partial-rank analysis gives, among stable cell pairs:

- environment versus species composition, controlling geographic distance:
  partial rho = 0.173;
- geography versus species composition, controlling environmental distance:
  partial rho = 0.611.

The corresponding values using all environmentally usable cells are
approximately 0.158 and 0.517.

These are descriptive partial associations only. Cell-pair observations are
not independent, so no inferential p-values are used.

The result indicates that geography remains the dominant organising
association, but environmental context retains additional structure that is
not completely reduced to geographic distance.

## 5. Environmental separation matters within comparable geographic-distance
bands

The stable-cell analysis groups pairs into geographic-distance bands and then
divides environmental distance into quartiles within each band.

Median species-composition TVD for the most environmentally similar versus
most environmentally different quartiles is:

| Geographic distance | Environmental Q1 | Environmental Q4 |
| --- | ---: | ---: |
| <50 km | 0.208 | 0.317 |
| 50-100 km | 0.242 | 0.347 |
| 100-250 km | 0.300 | 0.525 |
| 250-500 km | 0.360 | 0.680 |
| 500-1000 km | 0.431 | 0.770 |

The pattern is not perfectly monotonic in every short-distance quartile; for
example, Q2 is slightly below Q1 in the <50 km band.

Nevertheless, species composition generally becomes more different as
environmental distance increases within comparable geographic-separation
bands, particularly from 100 to 500 km.

Within-band environmental-distance versus composition correlations in the
stable-cell subset are approximately:

- <50 km: rho = 0.223;
- 50-100 km: rho = 0.220;
- 100-250 km: rho = 0.323;
- 250-500 km: rho = 0.375;
- 500-1000 km: rho = 0.325.

Thus, environmental differentiation remains descriptively associated with
species turnover even when cell pairs are compared over similar geographic
distances.

## Integrated interpretation

The earlier EDA posed the central methodological question:

> Are models learning environmental and seasonal context, or merely memorising
> Australian geography?

EDA-09B suggests that this should not be framed as an either-or explanation.

Geography is the stronger organising structure in the public FrogID data:

- species geographic footprints are highly structured;
- species composition changes strongly with geographic distance;
- multi-species co-occurrence is extremely closely aligned with geographic
  footprint overlap.

However, environmental context also retains a smaller but persistent
association with species composition after geographic separation is controlled
descriptively.

The evidence therefore supports treating geography and environment as
overlapping but non-identical sources of information.

## Modelling implications

The planned feature progression should be retained:

- M0: prevalence baseline;
- M1: seasonal context;
- M2: season + climate;
- M3: season + climate + elevation;
- M4: season + climate + elevation + latitude/longitude.

The M3 versus M4 comparison is especially important.

If M4 substantially improves performance under ordinary random validation but
the improvement weakens under spatially grouped validation, that would be
consistent with explicit coordinates exploiting geographic structure that does
not transfer as strongly to new regions.

If M3 remains effective under spatial validation, that would support the
generalisation value of environmental context beyond exact geographic
position.

These are modelling hypotheses to be tested later; EDA-09B does not establish
predictive performance.

## Validation implications

EDA-09B reinforces the EDA-09 decision to compare:

- ordinary event-level validation; and
- 3-fold validation grouped by 0.5-degree cells.

Random validation answers how well models rank species in geographic contexts
similar to those already represented in training.

Spatially grouped validation asks the harder question of transfer to
geographically separated observations.

Both are relevant, but they should not be interpreted as measuring the same
generalisation condition.

## Multi-species evaluation implication

Because co-occurrence structure is extremely strongly associated with
geographic footprint overlap, performance differences among co-occurrence
clusters should not automatically be interpreted as ecological-community
effects.

Any future cluster-specific Recall@k analysis should acknowledge geography as
a major potential organising mechanism.

The multi-species extension should remain completely outside model fitting and
hyperparameter tuning.

## Report-use recommendation

The strongest EDA-09B visual for the final report is the
environmental-distance-quartile figure.

It directly connects geography, environment and the classification outcome in
one visual and supports the project's central methodological narrative:

> At similar geographic separations, environmentally more different areas
> generally contain more different observed species compositions.

The co-occurrence-versus-geographic-overlap scatterplot is valuable supporting
evidence, particularly when discussing the multi-species extension, but may be
omitted if the six-page report requires space.

## Constraints respected

- No classifier was fitted.
- No predictive performance was calculated.
- No inferential p-values were used for non-independent cell pairs.
- Environmental and geographic associations are descriptive, not causal.
- Static environmental PCA was used only as an exploratory distance
  representation.
- No exact coordinates, cell identifiers or event identifiers were written to
  output.
- Multi-species co-occurrence was not interpreted as ecological interaction.
- No modelling feature was accepted or rejected on predictive-performance
  grounds.