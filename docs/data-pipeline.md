# FrogID data preparation

This stage prepares data for STAT5003 multiclass classification; it performs no
EDA, model fitting, or species-absence inference. Run all commands from this
repository root, using its `.Rprofile` and `renv` library.

## Reproduce

```r
renv::restore(prompt = FALSE)
source("R/acquisition/download_frogid.R") # reuses existing immutable CSV
source("R/cleaning/build_cohorts.R")
source("tests/validate_cohorts.R")
```

Subsequent integration commands and final dimensions are documented as each
integration is validated. `R/setup_environment.R` installs only required direct
dependencies and snapshots the project. Downloads and RDS files stay under
ignored `data/raw/`, `data/interim/`, and `data/processed/`; only code, provenance,
and aggregate QC summaries are committed. No event coordinates, recording IDs,
or observer identifiers are published in the summary tables.

## Source and statistical unit

The original Australian Museum FrogID Dataset 6 CSV is
`data/raw/frogid/FrogID6_final_dataset.csv`. Its MD5 is
`fcd09f3c324985415850db718ca80535` and SHA256 is
`BD37E6AC13B677C93F95FDD598E61E2769EAD3650147CF4CF100894448C7E7DC`.
It contains 974,120 occurrence rows, 21 columns, 974,120 unique occurrence IDs,
542,287 events and 216 supplied scientific names, dated 2017-11-10 to 2023-11-09.
There are 301,378 single-species and 240,909 multi-species events (maximum 13
species), without duplicate occurrence IDs or exact duplicate rows.

One recording (`eventID`), not one occurrence, is the statistical unit. Before
collapsing any records, exact agreement is asserted for latitude, longitude,
date, time and recorder, including missing/nonmissing disagreements. Conflicting
events stop construction and remain in a private diagnostic RDS. The complete
original set of scientific names is formed before filtering. If any occurrence
fails a QC rule, its entire event is rejected, preventing incomplete labels and
false single-species events. Duplicate species labels within an event are
deduplicated as a set; different species are never collapsed into one label.

Official release descriptions say 226 species, while the supplied CSV has 216.
The official ALA metadata corroborates 974,120 rows and still says 226 species.
Public-data suppression and taxonomy changes are documented but do not establish
an exact ten-name reconciliation. We use the observed names and fabricate none.
See [source investigation](frogid-source-investigation.md) for evidence, source
links, licence, and the differing public-portal row count. No ALA data are added.

## Quality filtering and privacy

The main spatial cohort requires all of the following on every source row:

- Nonempty species labels and event IDs; unique occurrence IDs.
- Finite coordinates, latitude in [-90, 90] and longitude in [-180, 180].
- Finite `coordinateUncertaintyInMeters > 0` and `<= 1000`.
- `geoprivacy == "open"`.
- `dataGeneralizations == "No data generalization"`.
- A valid ISO calendar date.

The raw audit found 13 negative uncertainty values: -2147480 (9 rows), -2146620
(2), -2147180 (1) and -2140550 (1), plus 13 zeros. Their provenance is unresolved;
negative distances are invalid, not genuine precision. All nonpositive values
are rejected, never changed to zero. `coordinate_uncertainty_diagnostics.csv`
records their occurrence and event frequencies. The old upper-bound-only filter
was incorrect and has been replaced. `qc_filter_flow.csv` records sequential
event exclusions; the final cohort rows are parallel branches, not successive
filters (their exclusion count is NA). These QC fields stay in private source
cohorts and never enter the predictor whitelist.

## Objective species selection and target representation

Counts use all clean single-species events. Start at >=2,000 events per species.
Use all qualifying species if 15-25 qualify; if fewer than 15 qualify, lower to
>=1,000. If more than 25 qualify, retain the top 25 by clean count, breaking ties
by scientific name in ascending order. If even the fallback yields fewer than
15 classes, keep all qualifying classes and report that limitation. Freeze the
entire species table, including zero-count and unselected species, in
`outputs/tables/species_cohort.csv` before examining conservation status.

The primary cohort contains one row and one `scientificName` target per selected
single-species event. The multi-species extension contains one row per clean
event with >=2 original species and at least one selected species. It keeps the
complete `species_list`, `selected_species_list`, and original/selected counts.
`all_species_in_vocabulary` and `recall_at_k_eligible` are true only when every
original species is representable by the selected vocabulary. Partial-overlap
events are retained but explicitly ineligible for full-target Recall@k. There
is no expansion into contradictory training labels.

## Temporal features and predictor exclusions

`eventDate` is retained as supplied, parsed to Date. Features are month,
day_of_year, month sine/cosine, and day-of-year sine/cosine. Month uses phase
`2*pi*(month-1)/12`; day-of-year uses `2*pi*(day_of_year-1)/days_in_year`, with
365/366 determined by the Gregorian leap-year rule.

Actual event times mix `HH:MM:SS+HHMM` and `HH:MM:SSUTC`. Although syntactically
parseable, the clock hour is not uniformly local. `local_hour` is therefore
omitted, with format/suffix frequencies in `event_time_diagnostics.csv`. Raw
time and recorder remain in private audit/cohort files. Supplied dates are not
claimed to be reconstructed local dates.

Targets, occurrenceID, eventID, recordedBy, modified, datasetName,
machineObservation, taxonomic/common-name derivatives, all QC fields, and EPBC
listing/category are excluded from predictors. A positive predictor whitelist
will accompany final datasets so selecting all numeric columns cannot leak
quality, identifiers, or conservation status into a later model.

## Interpretation and scope

FrogID is citizen-science presence-only data. Detection depends on observer
effort, access, app use, calling activity, recording conditions and identification.
An unrecorded species is not established absent. Predictions will rank species
among these observed recording labels, not estimate causal environmental effects
or unrestricted ecological occupancy. Repeated observers, nearby sites and dates
can create dependence; future validation must address spatial/temporal leakage.

Public suppression and location generalisation disproportionately affect
sensitive species. Strict public-coordinate QC may leave little threatened-species
representation; objective class selection will not be overridden for a
conservation narrative. EPBC status is evaluation metadata, not a feature, and
current status may differ from status at recording time.

IBRA is optional future context. It will be skipped if it risks delaying the
core dataset. No BOM, ALA occurrence data, SoilGrids, satellite/audio processing,
range-map predictors, EDA or models are included.
