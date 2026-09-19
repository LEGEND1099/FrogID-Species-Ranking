# FrogID project status

Last major preparation milestone: **data preparation certified ready for EDA**.

## Research question

> To what extent can environmental, seasonal and geographic context rank
> Australian frog species detected in FrogID recordings, and how do public
> geoprivacy protections constrain the applicability of such models to
> threatened species?

## Current stage

### Complete

- FrogID Dataset 6 acquired and checksum-pinned
- raw occurrence/event audit completed
- event-level QC implemented
- objective species-selection rule frozen
- single-species modelling cohort constructed
- multi-species evaluation extension constructed
- temporal/calendar features constructed
- WorldClim 2.1 source acquired and validated
- WorldClim extraction completed and cached by unique coordinate
- EPBC/SPRAT source acquired and validated
- conservation metadata integrated after species selection
- processed analysis datasets built
- conservation/geoprivacy retention aggregates built
- non-sensitive EDA handoff summaries produced
- full preparation pipeline executed end-to-end
- `renv` lockfile verified
- independent validation suite passed
- EDA readiness gate passed

### Current analysis objects

#### Primary multiclass dataset

`data/processed/frog_primary_multiclass.rds`

- rows: 247,406
- target: `scientificName`
- classes: 18
- unit: one clean single-species recording event
- predictors: 30
- environmental-NA rows: 4,806

Aligned predictor-only object:

`data/processed/frog_primary_predictors.rds`

#### Multi-species extension

`data/processed/frog_multispecies_extension.rds`

- rows: 213,675
- unit: one clean recording with at least two original species and at least
  one selected species
- full Recall@k-eligible events: 127,322

Aligned predictor-only object:

`data/processed/frog_multispecies_predictors.rds`

#### Species metadata

`data/processed/species_metadata.rds`

- rows: 216 supplied FrogID scientific names
- 18 selected modelling species
- conservation metadata retained for interpretation/evaluation only

## Predictor design

### Geographic — 2

- decimalLatitude
- decimalLongitude

### Seasonal/calendar — 6

- month
- day_of_year
- month_sin
- month_cos
- day_of_year_sin
- day_of_year_cos

### Environmental — 22

- BIO1-BIO19
- elevation
- climatological_tavg_event_month
- climatological_prec_event_month

Total: **30 predictors**.

No imputation, scaling, balancing or correlation-based feature removal has yet
been performed.

Those decisions belong to EDA and modelling.

## Selected species

The objective threshold selected every species with at least 2,000 clean
single-species recording events.

| Species | Events |
| --- | ---: |
| Crinia signifera | 87,536 |
| Limnodynastes peronii | 45,042 |
| Litoria fallax | 17,485 |
| Litoria peronii | 14,867 |
| Limnodynastes tasmaniensis | 12,669 |
| Litoria caerulea | 12,397 |
| Litoria ewingii | 9,345 |
| Limnodynastes dumerilii | 7,720 |
| Crinia glauerti | 7,179 |
| Adelotus brevis | 5,489 |
| Litoria quiritatus | 4,579 |
| Litoria pyrina | 4,566 |
| Litoria gracilenta | 4,393 |
| Crinia parinsignifera | 3,917 |
| Litoria moorei | 3,579 |
| Litoria verreauxii | 2,334 |
| Crinia georgiana | 2,155 |
| Litoria infrafrenata | 2,154 |

The resulting max/min class-count ratio is approximately 40.6:1.

## Missingness

No environmental NA rows were silently removed.

Events with at least one environmental NA:

- all clean events: 7,633 / 519,414
- primary events: 4,806 / 247,406
- multi-species extension: 2,009 / 213,675
- Recall@k-eligible extension: 1,251 / 127,322

The current data preserve these rows so the handling strategy can be chosen
after EDA.

## Conservation/geoprivacy result established during preparation

The supplied FrogID names contain:

- 24 confirmed EPBC-listed taxa
- 12 Endangered
- 12 Vulnerable
- 6,749 distinct recording events containing at least one confirmed listed taxon
- 1,627 single-species listed-taxon recordings

All 6,749 listed-taxon recordings fail the strict public spatial QC because
their public locations are obscured/generalised and exceed the project's
1,000 m uncertainty limit.

Therefore:

- zero confirmed listed taxa survive into the clean spatial cohort;
- zero confirmed listed taxa enter the selected 18-class vocabulary;
- threatened-species predictive subgroup performance cannot be evaluated
  from the current modelling cohort.

This should be analysed as a public-data representation/geoprivacy constraint,
not as evidence about threatened-species ecology or model performance.

## Interpretation constraints

The data are presence-only.

Do not infer:

- ecological absence from an unrecorded species;
- abundance from recording frequency;
- causal climate effects from predictive association;
- threatened/non-threatened status from an unmatched EPBC lookup.

WorldClim describes long-term climatology, not recording-day weather.

Latitude/longitude are legitimate context variables for the ranking task but
may allow strong geographic memorisation. Their apparent value must therefore
be compared under both ordinary and spatially blocked validation.

## Deferred scope

Intentionally not included in the current analysis:

- IBRA
- BOM historical weather
- additional ALA occurrence records
- SoilGrids
- satellite/land-cover features
- species range maps as predictors
- FrogID audio processing

These are possible future extensions, not missing preparation work.

## Next work

Current next stage: **exploratory data analysis**.

See:

- `docs/eda-plan.md`
- `docs/data-summary.md`
- `docs/data-pipeline.md`

EDA findings are allowed to change later preprocessing and modelling choices,
provided those decisions are documented and do not invalidate the frozen raw
data or objective target construction.