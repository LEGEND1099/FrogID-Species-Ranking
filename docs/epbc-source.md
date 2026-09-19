# EPBC conservation metadata

The pipeline uses the Australian Government Department of Climate Change,
Energy, the Environment and Water (DCCEEW) structured **Threatened Species State
Lists** CSV, published through [data.gov.au](https://data.gov.au/data/dataset/ae652011-f39e-4c6c-91b8-1dc2d2dfee8f)
from the Species Profile and Threats Database (SPRAT). It covers listed taxa
across Australia; this pipeline uses rows whose `Class` is `Amphibia`.

The current resource was discovered with the official
[CKAN package API](https://data.gov.au/data/api/3/action/package_show?id=ae652011-f39e-4c6c-91b8-1dc2d2dfee8f),
not by scraping HTML. At acquisition, the latest species resource was
[Threatened Species State Lists — 28 August 2026](https://data.gov.au/data/dataset/ae652011-f39e-4c6c-91b8-1dc2d2dfee8f/resource/78401dce-1f40-49d3-92c4-3713d6e34974/download/20260828spcs.csv).
The file contains 2,222 listed taxa, including 53 amphibian taxa; `Date extracted`
is `2026-Aug-28`. The package metadata was last modified on 31 August 2026.
This is the latest practical official structured snapshot found on retrieval,
not a claim that it incorporates every subsequent legal listing decision.

The publisher supplies a [Creative Commons Attribution 3.0 Australia licence](https://creativecommons.org/licenses/by/3.0/au/).
Attribution: Australian Government DCCEEW, Species Profile and Threats Database
(SPRAT), via data.gov.au. The source CSV and complete CKAN metadata are retained
locally under `data/raw/epbc/`, which is ignored by Git. The small committable
`outputs/tables/epbc_acquisition_metadata.csv` records the exact URL, extraction
date, actual UTC retrieval timestamp, publisher, licence, fields, byte count
and MD5 fingerprint. No locations are included in the EPBC output summaries.

## Reproducibility and fields

Run `Rscript R/acquisition/download_epbc.R` from the repository root. The first
run discovers the latest CSV and saves a local manifest; later runs verify and
reuse that frozen snapshot. To intentionally acquire a newer official snapshot,
use `Rscript R/acquisition/download_epbc.R --refresh`, then rerun integration
and validations. A corrupted or missing frozen file stops the pipeline.

Fields used are `Scientific Name`, `Current Scientific Name`, `Threatened
status`, `Class`, `Listed SPRAT TaxonID`, `Current SPRAT TaxonID`, `Profile` and
`Date extracted`. EPBC categories are retained exactly as supplied, including
`Critically Endangered`, `Endangered`, `Vulnerable` and `Extinct`.

## Name matching and unresolved taxa

`R/integration/integrate_epbc.R` reads the already frozen species-cohort table.
It first matches the scientific name to the official listed scientific name,
exactly and then with case and whitespace normalisation. If neither matches,
it tries the official `Current Scientific Name` field, exactly and then with
the same normalisation. The latter is authoritative source-provided equivalence;
every such mapping actually used is written to
`outputs/tables/epbc_authoritative_name_mappings.csv` with its SPRAT IDs and URL.
There is no fuzzy matching, epithet-only matching, or inferred genus replacement.
FrogID target labels are never renamed by this integration.

This source is a **threatened-only list**, not a complete taxonomic checklist.
Consequently a successful match gives `epbc_listed = TRUE` and the supplied
category. An unmatched name has `epbc_listed = NA`, `epbc_category = NA` and
an explicit match status. No unmatched species is relabelled as confirmed
unlisted, Least Concern, or non-threatened. No `FALSE` labels are manufactured.
The source may list a subspecies when FrogID identifies only a species. Such
cases remain unresolved and the listed subordinate taxa are recorded for
review; a subspecies status is not propagated to the entire species.

`outputs/tables/epbc_unmatched_species.csv` is the complete unresolved report.
`outputs/tables/species_conservation_summary.csv` has one row per FrogID species;
`outputs/tables/epbc_category_counts.csv` separately reports all raw taxa and
selected model taxa with their clean single-species-event counts.
The local `data/interim/epbc/species_conservation.rds` is the one-row-per-name
lookup for final integration. Joins assert unique names and unchanged row count.

## Interpretation

Conservation labels describe the retrieved contemporary EPBC snapshot, not
necessarily the status during FrogID recordings in 2017–2023. State and territory
listings and IUCN assessments are outside scope. Names absent from the snapshot
may be unlisted, taxonomically different, or identified above a listed
infraspecific rank; these possibilities are not distinguished without further
authoritative review.

Species selection occurs before conservation integration. No threatened taxon
is added to the model vocabulary to improve the conservation narrative. The
public open-coordinate and no-generalisation filters can disproportionately
exclude sensitive species. Only confirmed listed taxa represented by clean
selected events can support a later threatened-species subgroup evaluation.
`epbc_listed`, `epbc_category`, name-match fields, source IDs and other
conservation metadata are excluded from model predictors.

## Results for this frozen cohort

The 19 September 2026 (Australia/Sydney) preparation run matched 24 of the
216 raw FrogID species exactly to listed names: 12 Endangered and 12 Vulnerable.
All 24 have zero clean single-species events under the required public-location
quality filters. There are 192 unresolved names, including all 18 selected
model species (247,406 clean single-species events). None of the selected model
classes is a confirmed EPBC-listed match in this integration, so the dataset
does not currently support a threatened-class subgroup evaluation. This is
not evidence that all selected species are definitively unlisted.

Two unresolved names require special taxonomic care: selected `Litoria
verreauxii` (2,334 clean single-species events) has a listed subspecies,
`Litoria verreauxii alpina`; `Heleioporus australiacus` (zero clean events)
has listed subspecies `Heleioporus australiacus australiacus` and `Heleioporus
australiacus flavopunctatus`. Species-level FrogID names cannot determine
membership of these listed infraspecific taxa. No authoritative current-name
aliases were required by this particular CSV; the mapping report therefore
contains its header and zero mappings. The acquisition timestamp is recorded
in UTC (18 September), corresponding to the local preparation date above.
