# FrogID Species Ranking

STAT5003 Computational Statistics project investigating:

> **To what extent can environmental, seasonal and geographic context rank
> Australian frog species detected in FrogID recordings, and how do public
> geoprivacy protections constrain the applicability of such models to
> threatened species?**

The project uses Australian Museum FrogID citizen-science records together
with WorldClim environmental context and official EPBC/SPRAT conservation
metadata.

## Current project status

**Data preparation is complete and certified ready for EDA.**

The reproducible preparation pipeline has been executed end-to-end and all
readiness checks pass.

Current primary analysis dataset:

- **247,406** clean single-species recording events
- **18** selected frog species
- **30** whitelisted predictors
- **2** geographic predictors
- **6** seasonal/calendar predictors
- **22** WorldClim environmental predictors

A separate multi-species extension contains:

- **213,675** clean multi-species recording events with selected-species overlap
- **127,322** events for which every detected species belongs to the 18-species
  vocabulary and full-target Recall@k evaluation is therefore possible

See:

- [Project status](docs/project-status.md)
- [EDA execution plan](docs/eda-plan.md)
- [Data preparation pipeline](docs/data-pipeline.md)
- [Certified data summary](docs/data-summary.md)

## Analysis design

The primary task is **18-class species ranking/classification** using one
clean single-species FrogID recording event as the statistical unit.

The intended model-development progression is:

1. species-prevalence baseline;
2. season only;
3. season + climate;
4. season + climate + elevation;
5. season + climate + elevation + latitude/longitude.

Performance will later be assessed using metrics appropriate to ranking and
class imbalance, including Top-1, Top-3, Top-5 accuracy, Macro-F1 and mean
reciprocal rank.

A separate extension will train on the single-species events and evaluate
whether the ranked predictions recover species observed in multi-species
recordings.

## Important interpretation

FrogID is **presence-only citizen-science data**.

A recording of a species establishes a detected label for that recording;
failure to record another species does **not** establish ecological absence.

The project therefore aims to rank species associated with the supplied
recording context. It does not estimate unrestricted species occupancy,
population abundance, causal environmental effects, or ecological absence.

Observer effort, access, app usage, calling behaviour, recording conditions,
geography and repeated observations can all influence the supplied dataset.

## Predictors

The final predictor whitelist contains exactly **30 numeric columns**.

### Geographic

- `decimalLatitude`
- `decimalLongitude`

### Seasonal / calendar

- `month`
- `day_of_year`
- `month_sin`
- `month_cos`
- `day_of_year_sin`
- `day_of_year_cos`

### Environmental

- WorldClim BIO1-BIO19
- elevation
- climatological mean temperature for the recording month
- climatological precipitation for the recording month

WorldClim values describe **1970-2000 climatological context**, not weather
observed on the recording date.

Targets, identifiers, observer identity, QC/privacy fields, conservation
status and target-derived variables are excluded from predictor matrices.

## Conservation and geoprivacy

EPBC/SPRAT conservation status is retained only as **context and evaluation
metadata**. It is never a model predictor and did not influence selection of
the 18 modelling classes.

The supplied FrogID data contain **24 confirmed EPBC-listed taxa** represented
across **6,749 distinct raw recording events**.

All of those listed-species recordings are publicly obscured/generalised and
exceed the project's 1,000 m coordinate-uncertainty threshold. Consequently,
none survive the strict public spatial QC and none enter the current
18-species modelling vocabulary.

The conservation component of the project therefore concerns the
**representation and applicability constraint created by public
geoprivacy/QC**, rather than threatened-species predictive performance.

An unmatched FrogID species is not interpreted as confirmed non-threatened;
the official EPBC source is a threatened-species list rather than a complete
Australian frog checklist.

## Data sources

The frozen project scope uses only:

1. **Australian Museum FrogID Dataset 6**
2. **WorldClim 2.1 Australia**, 30 arc-second rasters
3. **Official DCCEEW/SPRAT EPBC threatened-species data**

IBRA, BOM historical weather, additional ALA occurrence records, SoilGrids,
satellite land cover, species-range polygons and audio-derived features are
outside the current scope.

## Reproduce data preparation

Restore the frozen R environment and run the canonical pipeline from the
repository root:

```sh
Rscript -e "renv::restore(prompt = FALSE)"
Rscript R/run_data_preparation.R
```

The pipeline verifies/acquires the frozen sources, rebuilds the FrogID
cohorts, integrates WorldClim and EPBC metadata, constructs the processed
datasets, produces conservation/geoprivacy summaries, independently validates
the outputs and generates the EDA-readiness report.

A validated WorldClim coordinate-extraction cache is reused when its source
and coordinate fingerprints remain unchanged.

See [docs/data-pipeline.md](docs/data-pipeline.md) for the full methodology,
QC rules, source provenance and reproducibility certification.

## Repository structure

- `R/acquisition/` — source acquisition and integrity checks
- `R/cleaning/` — FrogID event construction and QC
- `R/integration/` — WorldClim, EPBC and final dataset integration
- `R/features/` — feature-related code
- `R/modelling/` — future model-development code
- `R/summary/` — preparation summaries and readiness reporting
- `analysis/` — EDA and later analysis scripts/notebooks
- `data/raw/` — immutable/downloaded sources, local and Git-ignored
- `data/interim/` — validated cohorts/caches, local and Git-ignored
- `data/processed/` — final analysis RDS files, local and Git-ignored
- `outputs/figures/` — generated analysis figures
- `outputs/tables/` — non-sensitive aggregate tables
- `docs/` — methodology, status, source and analysis documentation
- `tests/` — independent preparation/integration validation

No sensitive event-level coordinates, recording IDs or observer identifiers
are published in committed summary outputs.

## Next stage

The project is now entering **exploratory data analysis**.

The EDA is intentionally staged so individual components can be completed
independently while later steps remain responsive to earlier findings.

See [docs/eda-plan.md](docs/eda-plan.md) for the execution plan.