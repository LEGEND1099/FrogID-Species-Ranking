# FrogID data preparation

This stage prepares data for STAT5003 multiclass classification; it performs no
EDA, model fitting, or species-absence inference. Run all commands from this
repository root, using its `.Rprofile` and `renv` library.

## Reproduce

From the repository root, restore the frozen R environment and run the
canonical preparation pipeline:

```sh
Rscript -e "renv::restore(prompt = FALSE)"
Rscript R/run_data_preparation.R
```

`R/run_data_preparation.R` is the single end-to-end entry point. It:

1. acquires or verifies the immutable FrogID Dataset 6 source;
2. rebuilds and validates the event-level FrogID cohorts;
3. acquires/verifies WorldClim 2.1 and integrates environmental context;
4. acquires/verifies the frozen official EPBC/SPRAT source;
5. integrates conservation metadata after the species vocabulary is frozen;
6. materialises the final labelled datasets and 30-column predictor matrices;
7. independently validates the complete processed data;
8. builds and validates conservation/geoprivacy retention aggregates; and
9. generates and validates the EDA-readiness handoff.

A validated WorldClim coordinate cache is reused when the clean coordinates
and source-raster fingerprints are unchanged, so reruns do not repeat the
371,054-coordinate raster extraction unnecessarily.

`R/setup_environment.R` installs only required direct dependencies and
snapshots the project. Downloads and RDS files stay under ignored
`data/raw/`, `data/interim/`, and `data/processed/`; only code, provenance,
aggregate QC summaries and non-sensitive handoff outputs are committed.
No event coordinates, recording IDs, or observer identifiers are published
in the summary tables.

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

IBRA is outside this project scope. No BOM, ALA occurrence data, SoilGrids, satellite/audio processing,
range-map predictors, EDA or models are included.

## Validation and immutable inputs

The preserved integration was resumed from `4d9c139` on `data-integration`.
All five processed RDS files and required cohort, environmental and EPBC interim
artifacts were present. `config/source_checksums.csv` pins the original FrogID,
four WorldClim TIFFs and official EPBC CSV independently of regenerated manifests.
Acquisition and validation reject changed sources; updating a checksum requires
an explicit, reviewed source revision rather than silently accepting a new file.

The final validator checks every retained original occurrence, proves the clean
event set equals all events satisfying the rules, regenerates objective species
selection, checks original multi-species lists, verifies source raster geometry
and all event-month mappings, and audits conservation joins and the 30-column
predictor whitelist. All cohort missingness tables are mandatory. Successful
tests save local evidence with script and artifact fingerprints under ignored
`data/interim/validation/`, so later readiness checks can reject stale results.

### Checkpoint 1 certification

Validated at 2026-09-19T07:55:24Z (UTC). Both tests/validate_cohorts.R and
 tests/validate_processed_data.R passed after repairing two preserved validator
syntax errors and making all cohort missingness checks mandatory. The source
cohorts and integrations themselves required no regeneration. Final dimensions:

| Dataset | Rows | Columns |
| --- | ---: | ---: |
| Clean events | 519414 | 17 |
| frog_primary_multiclass | 247406 | 36 |
| frog_primary_predictors | 247406 | 30 |
| frog_multispecies_extension | 213675 | 38 |
| frog_multispecies_predictors | 213675 | 30 |
| species_metadata | 216 | 18 |

The 18 classes still follow the >=2000 clean single-species-event rule.
All 371054 clean coordinates map uniquely to the cached 44-layer extraction.
Environmental missingness remains 7633 all-clean, 4806 primary and 2009
multispecies events; none was dropped. All six source checksums, official EPBC
source-row matches, unique event joins and the predictor exclusions passed.
Raw/interim/processed paths are ignored and contain no Git-tracked files.

## Conservation and geoprivacy retention preparation

`Rscript R/summary/build_conservation_retention.R` reads original occurrences,
the clean event IDs and the authoritative EPBC name lookup. It creates four
non-sensitive aggregate tables:

- `conservation_species_retention.csv`: one row per supplied scientific name,
  original/clean occurrences and events, original/clean single-species events,
  independently eligible open-location and precision events, model selection,
  exact matched EPBC category and retention percentages. Zero denominators
  yield NA.
- `conservation_category_retention.csv`: distinct event unions within each
  confirmed official category or the unresolved group, plus species counts.
- `conservation_group_retention.csv`: distinct event unions for all recordings,
  confirmed listed taxa and names not confirmed listed or unresolved.
- `conservation_qc_exclusion_summary.csv`: both sequential exclusions matching
  `qc_filter_flow.csv` and independent, explicitly non-exclusive reason counts.

An event belongs to a category/scope if any of its original species belongs.
Mixed recordings can belong to several categories/scopes, so those rows must
not be summed to obtain an overall event total. Species-level event totals also
count a mixed recording once for each detected taxon. The all-events scope is
the deduplicated overall denominator. Open-location and precision eligibility
are independent checks, not cumulative stages; complete clean eligibility
requires every original occurrence to pass every rule.

For QC summaries, independent occurrence counts count directly failing source
rows within the scope's events, including co-detected taxa. Sequential occurrence
counts count all rows belonging to events removed at that stage. These bases
are labelled in the CSV. Negative and zero uncertainty are separate diagnostic
subsets of nonpositive uncertainty and must not be added to that combined row.
Privacy, generalisation and excessive uncertainty can overlap completely;
zero additional sequential privacy exclusions does not mean privacy had no
effect. Whole-event exclusion preserves complete species lists.

`tests/validate_conservation_retention.R` independently reconstructs the species
counts, category event unions, every exclusion reason/scope and all-events
sequential flow from original rows. No event/observer identifiers or point
coordinates are written to these public tables. An unmatched threatened-list
name remains `epbc_listed = NA`, never confirmed non-threatened.

The prepared aggregates contain 24 confirmed listed taxa (12 Endangered and
12 Vulnerable), with 6,771 focal-taxon occurrence rows across 6,749 distinct
recordings, including 1,627 single-species recordings. All 6,749 are obscured,
generalised and above the uncertainty threshold; none survives QC or enters
the selected vocabulary. Endangered recordings number 3,212 and Vulnerable
recordings 3,545, with eight shared events; their sum is not the listed union.
The 192 other names remain not confirmed listed or unresolved.

Across the entire source, negative uncertainty affects 13 rows/7 events, zero
affects 13 rows/9 events, and uncertainty >1,000 m affects 48,285 rows/22,857
events. Obscured and generalised locations each affect 25,185 rows/10,582 events,
already included in the excessive-uncertainty exclusions. Exactly 22,873 events
are excluded, leaving 519,414 (95.7821227505%). These are preparation counts,
not a causal estimate of privacy effects. The conservation question can be
examined through retention aggregates; threatened-class predictive performance
cannot be evaluated from the current selected cohort.

## EDA handoff report

`Rscript R/summary/summarise_for_eda.R` reads the final raw, interim and processed
objects, writes `docs/data-summary.md` and public tables under `outputs/tables/`,
and prints the complete Markdown report to the console. It computes only the
requested preparation descriptives: class sizes, date/state/event structure,
numeric feature summaries, missingness, provenance and inventory. It does not
balance classes, impute, scale, remove correlated predictors, fit models or
perform exploratory hypothesis analysis.

The generator runs `tests/validate_summary_data.R` against its aggregate tables
before writing the final checklist. Checklist PASS values require current
artifact/script fingerprints from successful cohort, processed, conservation
and summary tests; six matching source checksums; a synchronized `renv`; and
live Git checks. Failed or stale evidence is reported as FAIL. Test evidence
stays local in `data/interim/validation/` and is regenerated on reproduction.

The Git checklist entry means no uncommitted source/configuration/documentation
changes, excluding the generated report and tables themselves. Report generation
can change those derived outputs, which must subsequently be committed. A
separate final `git status` establishes that the entire working tree is clean.
The report's certification timestamp records validated evidence rather than
changing on every harmless report rerun.

During development, the readiness report can legitimately show FAIL for
`no uncommitted pipeline changes` while a checkpoint's source or validation
files have not yet been committed. This does not indicate a data-validation
failure. After the checkpoint is committed, rerunning
`R/summary/summarise_for_eda.R` regenerates the summary validation evidence and
the live Git-based readiness checklist. A fully certified EDA handoff therefore
requires both successful validation and a clean committed pipeline state.

## End-to-end reproducibility certification

The canonical `R/run_data_preparation.R` pipeline was executed successfully
from the repository root on 2026-09-19.

All 11 preparation stages completed without error. The run verified the
existing immutable FrogID source rather than redownloading it, rebuilt the
event cohorts from 974,120 original occurrence rows, and reproduced 519,414
clean events, 247,406 primary multiclass events, 213,675 relevant
multi-species events, 127,322 Recall@k-eligible multi-species events,
18 selected target species and exactly 30 whitelisted predictors.

WorldClim acquisition verified all 44 source layers and reused the validated
371,054-coordinate extraction cache. No raster extraction was repeated.
EPBC acquisition reused the frozen official SPRAT snapshot and reproduced
24 confirmed listed FrogID taxa, with no confirmed listed taxon surviving
the strict public-coordinate whole-event QC.

The following independent validation stages all passed during the same run:

- `tests/validate_cohorts.R`
- `tests/validate_processed_data.R`
- `tests/validate_conservation_retention.R`
- `tests/validate_summary_data.R`

The processed-data validator confirmed that no rows were multiplied, the raw
FrogID source remained unchanged, the environmental extraction was not
repeated, and the final primary and multi-species datasets retained their
certified dimensions.

After the run, `renv::snapshot(prompt = FALSE)` reported that the lockfile was
already up to date and `renv::status()` reported no issues. `git diff --check`
reported no whitespace errors, and `git ls-files data/raw data/interim
data/processed` returned no tracked files.

The only readiness failure during this certification run was the expected
Git-cleanliness check because `R/run_data_preparation.R` itself was being
updated and had not yet been committed. After committing the certified runner,
the EDA summary/readiness report must be regenerated once more against the
clean pipeline state.