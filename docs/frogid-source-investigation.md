# FrogID Dataset 6 source investigation

Checked on 2026-09-19. This is a provenance and data-quality investigation, not
exploratory analysis. The original CSV was read only and was not replaced.

## Release and local identity

The acquisition script points to the public
[FrogID Dataset 6 CSV](https://d2pifd398unoeq.cloudfront.net/FrogID6_final_dataset.csv).
The local file is `data/raw/frogid/FrogID6_final_dataset.csv`, with recorded MD5
`fcd09f3c324985415850db718ca80535`. Independent streaming inspection confirmed
974,120 occurrence rows and 216 distinct, supplied `scientificName` strings.
Every occurrence has `modified = 2025-06-19`. The repository audit records 21
columns, 542,287 distinct events, and dates from 2017-11-10 through 2023-11-09.

The [official ALA FrogID resource metadata](https://collections.ala.org.au/public/show/dr14760)
describes Dataset 6 as **974,120 records and 226 species** for the same six-year
period. Its metadata update is dated 2025-07-01. It names the Australian Museum
as provider and gives the dataset licence as **CC BY-NC 4.0**. This corroborates
the exact local record count, but does not explain the species-count difference.
The metadata page's older automated data-check date is not evidence of the
version of the local CSV. No ALA occurrence data were added to this project.

The [FrogID map and data page](https://portal.frogid.net.au/science/map-and-data/)
instead describes 974,700 records and 226 species. Therefore the published
descriptions also differ by 580 records; this is distinct from the ten-name
discrepancy and should not be interpreted as an observed loss during this
pipeline.

## Evidence relevant to the ten-name discrepancy

The [Australian Museum Dataset 6 announcement, dated 2025-07-09](https://australian.museum/blog/amri-news/frogid-dataset-6/)
reports 226 species and over 974,700 records. It says that highly sensitive
species such as *Assa wollumbin* are excluded from the public dataset, refers to
over 600 withheld records, and explains that other sensitive records have
buffered locations. It also documents three newly recognised species added in
this release: *Litoria corbeni*, *Litoria pyrina*, and *Litoria larisonans*.

The following presence checks were made against the unchanged local CSV, using
exact supplied scientific names. These are provenance checks, not inferred
missing-species labels.

| Scientific name | Local occurrence rows | Relevance |
| --- | ---: | --- |
| Litoria corbeni | 8 | Announced taxonomic addition is present |
| Litoria pyrina | 15,748 | Announced taxonomic addition is present |
| Litoria larisonans | 241 | Announced taxonomic addition is present |
| Assa wollumbin | 0 | Explicit example of public-data suppression |
| Litoria kroombitensis | 0 | Announcement mentions three records, absent under this exact name locally |
| Crinia sloanei | 2,654 | Consistent with announcement's approximate count |

The three additions being present argues against a simple explanation that this
file predates those taxonomic updates. Suppression, differences between internal
and public releases, or an uncorrected metadata count are plausible explanations,
but **the authoritative sources inspected do not reconcile exactly which ten
names account for 226 versus 216**. In particular, the approximate withheld count
does not establish an exact reconciliation of the 580-row difference.

The analysis therefore uses the observed 216 raw names and applies the stated
quality and species-selection rules to those data. No names or records are
manufactured, no alternate taxonomy is silently substituted, and this unresolved
metadata discrepancy does not block preparation. Exact reconciliation would
require clarification from the FrogID data custodians; no contact was sent.

## Recording-time semantics

The [original FrogID data paper](https://doi.org/10.3897/zookeys.912.38253)
defines `eventTime` as the recording time, states that date/time and geographic
metadata are captured by the app, and defines `eventID` as a submission that can
contain several species records. It does not resolve the mixed timezone suffixes
in the Dataset 6 export. The paper also describes FrogID as presence-only data
and explains that privacy protection extends to all species in a sensitive
submission. These methodology statements support event-level handling, but its
first-release licence must not replace the current ALA release metadata licence.

All local time strings inspected have `HH:MM:SS` followed by one of these
suffixes (occurrence counts; not distinct events):

| Suffix | Occurrence rows |
| --- | ---: |
| `+1100` | 317,697 |
| `+1000` | 141,849 |
| `+0800` | 70,886 |
| `+0930` | 47,256 |
| `+1030` | 10,384 |
| `UTC` | 386,048 |

The strings are syntactically parseable, but their hour component is not a
uniformly local clock time. Treating `UTC` hours as local hours would be
unjustified, and a complete conversion would need reliable location-specific
timezone and daylight-saving handling plus confirmation of the source date
semantics. For this stage, retain the raw `eventTime` and parsing diagnostics in
audit metadata and omit `local_hour` from predictors. Calendar features use the
supplied `eventDate`; they should not be described as reconstructed local dates.
