# FrogID Species Ranking

STAT5003 Computational Statistics project investigating whether environmental,
seasonal and geographic context can rank Australian frog species likely to be
detected in a FrogID recording, and how rankings might surface threatened species.

The primary task is multiclass classification on single-species recording events.
Multi-species recordings are preserved as a separate future Top-k evaluation
extension. Current work is **data preparation only**: no EDA or models are fitted.

## Data preparation

See [the data pipeline](docs/data-pipeline.md) for reproduction, quality rules,
source provenance, exclusions, dataset dimensions, and limitations.

Sources are Australian Museum FrogID Dataset 6, WorldClim 2.1 Australian country
rasters at 30 arc-seconds, and official DCCEEW/SPRAT EPBC metadata. IBRA remains
optional future context.

Restore the R environment with `renv::restore(prompt = FALSE)`. The original raw
FrogID CSV belongs at `data/raw/frogid/FrogID6_final_dataset.csv`. Follow the
pipeline documentation to build and validate the local analysis datasets.

Raw, interim and processed datasets are ignored by Git. Only code, documentation,
package versions, and aggregate summaries are committed. Exact recording
locations and observer identifiers are not included in public outputs.

## Repository structure

- `R/`: acquisition, quality filtering, feature creation, and integration scripts.
- `data/raw/`: immutable/downloaded sources, local only.
- `data/interim/`: audited event cohorts and extraction caches, local only.
- `data/processed/`: final analysis tables and predictor matrices, local only.
- `outputs/tables/`: small public aggregate validation summaries.
- `docs/`: methodology and source documentation.
- `tests/`: preparation and integration validation.
