# FrogID STAT5003 data summary
This reproducible handoff certifies data preparation and supplies the requested descriptive aggregates for future EDA. No EDA plots, statistical models, machine-learning models, imputation, scaling, class balancing, or correlated-feature removal have been performed.
Processed validation timestamp (UTC): **2026-09-19T09:12:59Z**. Readiness checks at the end are evaluated against the current files and Git state.
Research framing: "To what extent can environmental, seasonal and geographic context rank Australian frog species detected in FrogID recordings, and how do public geoprivacy protections constrain the applicability of such models to threatened species?"

## SOURCE / PROVENANCE
### FrogID
Release: Australian Museum FrogID Dataset 6; supplied datasetName values: 
`FrogID`.
Source: [FrogID Dataset 6 CSV](https://d2pifd398unoeq.cloudfront.net/FrogID6_final_dataset.csv).
Raw rows **974,120**; columns **21**; unique events **542,287**; unique occurrence IDs **974,120**; supplied scientific names **216**. No duplicate occurrence IDs, exact duplicate rows, or event metadata conflicts were found by validation.
Raw dates: **2017-11-10 to 2023-11-09**. Broad coordinate bounds (rounded outward to whole degrees): latitude -44 to -9; longitude 113 to 160. These are bounding limits, not published point locations.
Published release descriptions state 226 species, while the supplied CSV contains 216 distinct scientificName strings. The exact ten-name discrepancy remains unresolved; public suppression/taxonomy documentation does not prove a complete reconciliation. The analysis uses observed names and invents no records. See [source investigation](frogid-source-investigation.md). No ALA occurrence data were added.
Supplied stateProvince values/counts (raw event counts use distinct recordings):
| stateProvince | raw_occurrence_rows | raw_events | clean_public_events |
| --- | --- | --- | --- |
| New South Wales | 436,422 | 240,967 | 229,847 |
| Queensland | 203,391 | 110,569 | 105,220 |
| Victoria | 171,701 | 94,381 | 90,624 |
| Western Australia | 71,716 | 44,106 | 43,349 |
| Northern Territory | 36,959 | 15,609 | 14,858 |
| South Australia | 21,196 | 15,055 | 14,702 |
| Australian Capital Territory | 17,842 | 11,386 | 11,036 |
| Tasmania | 14,601 | 10,040 | 9,631 |
| Other Territories | 292 | 174 | 147 |
Supplied eventTime formats:
| format_pattern | suffix | occurrence_rows | events |
| --- | --- | --- | --- |
| DD:DD:DD+DDDD | +0800 | 70,886 | 43,604 |
| DD:DD:DD+DDDD | +0930 | 47,256 | 23,341 |
| DD:DD:DD+DDDD | +1000 | 141,849 | 89,878 |
| DD:DD:DD+DDDD | +1030 | 10,384 | 7,026 |
| DD:DD:DD+DDDD | +1100 | 317,697 | 165,582 |
| DD:DD:DDUTC | UTC | 386,048 | 212,856 |

### WorldClim
WorldClim **2.1**, **Australia (AUS)**, **30 arc-second** (1/120 degree), reference period **1970-2000**. CRS: **WGS84 / EPSG:4326**. Raster extent: longitude **112.5 to 159.5**, latitude **-55.5 to -9**; each raster grid has **5,580 rows x 5,640 columns**.
Variables: BIO1-BIO19 (19 layers), elevation (1), monthly mean temperature/tavg (12), and monthly precipitation/prec (12): **44 source layers**. Final event features use all 19 BIO variables, elevation, and the tavg/prec layer for the supplied event month: **22 environmental features**.
| variable | worldclim_version | reference_period | country | resolution_arcseconds | n_layers | retrieval_utc |
| --- | --- | --- | --- | --- | --- | --- |
| bio | 2.1 | 1970-2000 | AUS | 30 | 19 | 2026-09-18T23:22:30Z |
| elev | 2.1 | 1970-2000 | AUS | 30 | 1 | 2026-09-18T23:22:33Z |
| tavg | 2.1 | 1970-2000 | AUS | 30 | 12 | 2026-09-18T23:22:38Z |
| prec | 2.1 | 1970-2000 | AUS | 30 | 12 | 2026-09-18T23:22:43Z |
Extraction used one row per unique clean coordinate: **371,054 coordinates**, mapped to **519,414 events**. Cache verification compares exact coordinates, layer structure and source checksums. Latest integration reused the validated cache: **no (cache was created)**.
WorldClim provides climatology, not weather observed on the recording date. Source temperature values retain WorldClim 2.1 published units; no legacy temperature rescaling or raster interpolation is applied. [Source details and units](worldclim-source.md).

### EPBC
Agency: **Australian Government Department of Climate Change, Energy, the Environment and Water**. Source: DCCEEW Species Profile and Threats Database (SPRAT), [official Threatened Species State Lists CSV](https://data.gov.au/data/dataset/ae652011-f39e-4c6c-91b8-1dc2d2dfee8f/resource/78401dce-1f40-49d3-92c4-3713d6e34974/download/20260828spcs.csv).
Retrieved (UTC): **2026-09-18T23:21:33Z**; source extraction: **2026-Aug-28**. Source rows: **2,222**; amphibian rows: **53**.
Official source category counts (whole source and amphibian subset are separate scopes):
| source_scope | epbc_category | taxa |
| --- | --- | --- |
| all_source_taxa | Conservation Dependent | 7 |
| all_source_taxa | Critically Endangered | 458 |
| all_source_taxa | Endangered | 870 |
| all_source_taxa | Extinct | 102 |
| all_source_taxa | Extinct in the wild | 1 |
| all_source_taxa | Vulnerable | 784 |
| amphibian_taxa | Critically Endangered | 18 |
| amphibian_taxa | Endangered | 15 |
| amphibian_taxa | Extinct | 4 |
| amphibian_taxa | Vulnerable | 16 |
FrogID exact listed-name matches: **24**; normalized listed-name matches: **0**; official current-name matches: **0**; names not confirmed listed or unresolved: **192**.
The source is a threatened-species list, not a complete checklist. A non-match remains epbc_listed=NA, with its explicit match status; it is never relabelled non-threatened. Current source status is context, not reconstructed status at the 2017-2023 recording dates. [EPBC provenance and matching rules](epbc-source.md).
### Frozen source checksums
| source | file | md5 |
| --- | --- | --- |
| frogid_dataset6 | data/raw/frogid/FrogID6_final_dataset.csv | fcd09f3c324985415850db718ca80535 |
| worldclim_bio | data/raw/worldclim/climate/wc2.1_country/AUS_wc2.1_30s_bio.tif | 43ce12f88e87ffd56f4319c8bf6f8d7b |
| worldclim_elev | data/raw/worldclim/climate/wc2.1_country/AUS_wc2.1_30s_elev.tif | f9f0b151c68b0293ce007c4ca479bed3 |
| worldclim_tavg | data/raw/worldclim/climate/wc2.1_country/AUS_wc2.1_30s_tavg.tif | ffecdc4a0ea3ef6a9d47c428d82410f2 |
| worldclim_prec | data/raw/worldclim/climate/wc2.1_country/AUS_wc2.1_30s_prec.tif | 7d1c313faadb7c3b28f670cb49cf1d8f |
| epbc_sprat | data/raw/epbc/20260828spcs.csv | acfa6eb9893fea4b1141a8c28d30367c |
All six files are verified against the committed config/source_checksums.csv before this report is generated. WorldClim source URLs/geometry and EPBC provenance are retained in the acquisition metadata tables.

## QC FLOW
An event is rejected if any original occurrence row fails a condition. The following stages are sequential; excluded events sum to the total loss. Percent retained/excluded of raw uses the original event count; the final column uses the immediately preceding stage.
| stage | events_remaining | events_excluded | retained_percent_of_raw | excluded_percent_of_raw | excluded_percent_of_previous |
| --- | --- | --- | --- | --- | --- |
| raw_events | 542,287 | 0 | 100 | 0 | 0 |
| complete_species | 542,287 | 0 | 100 | 0 | 0 |
| valid_coordinates | 542,287 | 0 | 100 | 0 | 0 |
| positive_uncertainty_at_most_1000m | 519,414 | 22,873 | 95.7821 | 4.2179 | 4.2179 |
| open_geoprivacy | 519,414 | 0 | 95.7821 | 0 | 0 |
| no_data_generalization | 519,414 | 0 | 95.7821 | 0 | 0 |
| valid_event_date | 519,414 | 0 | 95.7821 | 0 | 0 |
Final clean events: **519,414**; excluded: **22,873**; retained: **95.7821%**.
Independent QC reason counts below are **non-exclusive**. Negative and zero uncertainty are subsets of nonpositive uncertainty. Privacy/generalisation can overlap excessive uncertainty, so these rows must not be summed. The precision filter occurs before privacy in the sequential flow; zero later exclusions do not imply no privacy effect.
| reason | occurrence_rows | events | percent_events |
| --- | --- | --- | --- |
| negative_coordinate_uncertainty | 13 | 7 | 0.0013 |
| zero_coordinate_uncertainty | 13 | 9 | 0.0017 |
| nonpositive_coordinate_uncertainty | 26 | 16 | 0.003 |
| uncertainty_over_1000m | 48,285 | 22,857 | 4.2149 |
| nonfinite_or_missing_uncertainty | 0 | 0 | 0 |
| obscured_geoprivacy | 25,185 | 10,582 | 1.9514 |
| not_open_geoprivacy | 25,185 | 10,582 | 1.9514 |
| generalised_location | 25,185 | 10,582 | 1.9514 |
| missing_generalization_flag | 0 | 0 | 0 |
| invalid_coordinates | 0 | 0 | 0 |
| invalid_dates | 0 | 0 | 0 |
| incomplete_species | 0 | 0 | 0 |

## EVENT STRUCTURE
| dataset | n_events | single_species_events | multispecies_events | max_species_per_event | recall_at_k_eligible_events |
| --- | --- | --- | --- | --- | --- |
| raw | 542,287 | 301,378 | 240,909 | 13 | NA |
| clean | 519,414 | 291,103 | 228,311 | 13 | NA |
| primary | 247,406 | 247,406 | 0 | 1 | NA |
| multispecies | 213,675 | 0 | 213,675 | 13 | 127,322 |
Primary recordings contain exactly one original species, selected by the frozen vocabulary. The extension retains complete original species lists and their selected-species intersections. Full-target Recall@k eligibility requires every original species to belong to the vocabulary.
Species-per-event distribution (original labels; no truncation):
| dataset | n_species | events | percent_events |
| --- | --- | --- | --- |
| raw | 1 | 301,378 | 55.5754 |
| raw | 2 | 130,252 | 24.019 |
| raw | 3 | 60,925 | 11.2348 |
| raw | 4 | 29,652 | 5.468 |
| raw | 5 | 12,955 | 2.389 |
| raw | 6 | 4,816 | 0.8881 |
| raw | 7 | 1,608 | 0.2965 |
| raw | 8 | 485 | 0.0894 |
| raw | 9 | 145 | 0.0267 |
| raw | 10 | 45 | 0.0083 |
| raw | 11 | 20 | 0.0037 |
| raw | 12 | 5 | 0.0009 |
| raw | 13 | 1 | 0.0002 |
| clean | 1 | 291,103 | 56.0445 |
| clean | 2 | 124,678 | 24.0036 |
| clean | 3 | 57,444 | 11.0594 |
| clean | 4 | 27,586 | 5.311 |
| clean | 5 | 11,983 | 2.307 |
| clean | 6 | 4,499 | 0.8662 |
| clean | 7 | 1,480 | 0.2849 |
| clean | 8 | 450 | 0.0866 |
| clean | 9 | 132 | 0.0254 |
| clean | 10 | 38 | 0.0073 |
| clean | 11 | 16 | 0.0031 |
| clean | 12 | 4 | 0.0008 |
| clean | 13 | 1 | 0.0002 |
| primary | 1 | 247,406 | 100 |
| multispecies | 2 | 115,818 | 54.2029 |
| multispecies | 3 | 54,482 | 25.4976 |
| multispecies | 4 | 26,211 | 12.2668 |
| multispecies | 5 | 11,158 | 5.2219 |
| multispecies | 6 | 4,056 | 1.8982 |
| multispecies | 7 | 1,346 | 0.6299 |
| multispecies | 8 | 418 | 0.1956 |
| multispecies | 9 | 127 | 0.0594 |
| multispecies | 10 | 38 | 0.0178 |
| multispecies | 11 | 16 | 0.0075 |
| multispecies | 12 | 4 | 0.0019 |
| multispecies | 13 | 1 | 0.0005 |

## SPECIES / CLASS SUMMARY
Raw supplied scientific names: **216**; clean scientific names: **171**; selected model classes: **18**. Objective threshold: **>=2,000 clean single-species events**; selection was frozen before EPBC integration.
| scientificName | event_count | percent_primary | cumulative_percent_primary | rank |
| --- | --- | --- | --- | --- |
| Crinia signifera | 87,536 | 35.3815 | 35.3815 | 1 |
| Limnodynastes peronii | 45,042 | 18.2057 | 53.5872 | 2 |
| Litoria fallax | 17,485 | 7.0673 | 60.6546 | 3 |
| Litoria peronii | 14,867 | 6.0092 | 66.6637 | 4 |
| Limnodynastes tasmaniensis | 12,669 | 5.1207 | 71.7844 | 5 |
| Litoria caerulea | 12,397 | 5.0108 | 76.7952 | 6 |
| Litoria ewingii | 9,345 | 3.7772 | 80.5724 | 7 |
| Limnodynastes dumerilii | 7,720 | 3.1204 | 83.6928 | 8 |
| Crinia glauerti | 7,179 | 2.9017 | 86.5945 | 9 |
| Adelotus brevis | 5,489 | 2.2186 | 88.8131 | 10 |
| Litoria quiritatus | 4,579 | 1.8508 | 90.6639 | 11 |
| Litoria pyrina | 4,566 | 1.8455 | 92.5095 | 12 |
| Litoria gracilenta | 4,393 | 1.7756 | 94.2851 | 13 |
| Crinia parinsignifera | 3,917 | 1.5832 | 95.8683 | 14 |
| Litoria moorei | 3,579 | 1.4466 | 97.3149 | 15 |
| Litoria verreauxii | 2,334 | 0.9434 | 98.2583 | 16 |
| Crinia georgiana | 2,155 | 0.871 | 99.1294 | 17 |
| Litoria infrafrenata | 2,154 | 0.8706 | 100 | 18 |
Largest class **87,536**; smallest **2,154**; median **6,334**; max/min imbalance ratio **40.6388**.
Largest-class share: **35.3815%**; cumulative top 3: **60.6546%**; cumulative top 5: **71.7844%**. No balancing has been performed.

## DATE / TIME SUMMARY
| dataset | n_events | date_min | date_max | calendar_years | missing_dates |
| --- | --- | --- | --- | --- | --- |
| raw | 542,287 | 2017-11-10 | 2023-11-09 | 7 | 0 |
| clean | 519,414 | 2017-11-10 | 2023-11-09 | 7 | 0 |
| primary | 247,406 | 2017-11-10 | 2023-11-09 | 7 | 0 |
| multispecies | 213,675 | 2017-11-10 | 2023-11-09 | 7 | 0 |
Counts refer to distinct recording events. Calendar year and month use the supplied eventDate.
Events by year:
| dataset | year | events |
| --- | --- | --- |
| raw | 2,017 | 8,397 |
| raw | 2,018 | 34,412 |
| raw | 2,019 | 35,235 |
| raw | 2,020 | 92,072 |
| raw | 2,021 | 140,115 |
| raw | 2,022 | 147,735 |
| raw | 2,023 | 84,321 |
| clean | 2,017 | 8,014 |
| clean | 2,018 | 32,307 |
| clean | 2,019 | 33,108 |
| clean | 2,020 | 87,130 |
| clean | 2,021 | 134,167 |
| clean | 2,022 | 142,506 |
| clean | 2,023 | 82,182 |
| primary | 2,017 | 4,475 |
| primary | 2,018 | 14,980 |
| primary | 2,019 | 15,605 |
| primary | 2,020 | 38,996 |
| primary | 2,021 | 62,271 |
| primary | 2,022 | 67,243 |
| primary | 2,023 | 43,836 |
| multispecies | 2,017 | 2,688 |
| multispecies | 2,018 | 12,011 |
| multispecies | 2,019 | 12,949 |
| multispecies | 2,020 | 37,645 |
| multispecies | 2,021 | 57,866 |
| multispecies | 2,022 | 61,061 |
| multispecies | 2,023 | 29,455 |
Events by month:
| dataset | month | events |
| --- | --- | --- |
| raw | 1 | 46,269 |
| raw | 2 | 35,291 |
| raw | 3 | 29,038 |
| raw | 4 | 21,116 |
| raw | 5 | 19,002 |
| raw | 6 | 21,190 |
| raw | 7 | 30,340 |
| raw | 8 | 43,475 |
| raw | 9 | 61,685 |
| raw | 10 | 70,853 |
| raw | 11 | 112,715 |
| raw | 12 | 51,313 |
| clean | 1 | 44,549 |
| clean | 2 | 33,705 |
| clean | 3 | 27,552 |
| clean | 4 | 19,445 |
| clean | 5 | 17,782 |
| clean | 6 | 20,057 |
| clean | 7 | 28,669 |
| clean | 8 | 41,688 |
| clean | 9 | 59,414 |
| clean | 10 | 68,378 |
| clean | 11 | 109,080 |
| clean | 12 | 49,095 |
| primary | 1 | 19,449 |
| primary | 2 | 14,840 |
| primary | 3 | 14,170 |
| primary | 4 | 10,922 |
| primary | 5 | 10,827 |
| primary | 6 | 12,585 |
| primary | 7 | 17,895 |
| primary | 8 | 22,322 |
| primary | 9 | 26,416 |
| primary | 10 | 29,245 |
| primary | 11 | 47,515 |
| primary | 12 | 21,220 |
| multispecies | 1 | 18,146 |
| multispecies | 2 | 13,300 |
| multispecies | 3 | 8,927 |
| multispecies | 4 | 4,471 |
| multispecies | 5 | 3,148 |
| multispecies | 6 | 4,667 |
| multispecies | 7 | 7,902 |
| multispecies | 8 | 16,109 |
| multispecies | 9 | 28,847 |
| multispecies | 10 | 34,017 |
| multispecies | 11 | 52,380 |
| multispecies | 12 | 21,761 |
eventTime mixes UTC clocks and explicit UTC offsets. UTC clock fields are not uniformly local time, and the pipeline does not reconstruct a common local timezone/date. local_hour is therefore omitted. The six temporal predictors use only the supplied date and correctly account for leap years in annual phase.

## GEOGRAPHIC SUMMARY
Clean/public recordings only. Bounds are rounded outward to whole degrees; no event IDs, observer IDs, exact sensitive locations, or point-coordinate pairs are published.
| dataset | events | unique_coordinates | min_latitude_broad | max_latitude_broad | min_longitude_broad | max_longitude_broad |
| --- | --- | --- | --- | --- | --- | --- |
| clean | 519,414 | 371,054 | -44 | -9 | 113 | 160 |
| primary | 247,406 | 188,075 | -44 | -9 | 113 | 154 |
| multispecies | 213,675 | 155,416 | -44 | -10 | 114 | 154 |
Clean/public stateProvince event counts:
| stateProvince | clean_public_events |
| --- | --- |
| New South Wales | 229,847 |
| Queensland | 105,220 |
| Victoria | 90,624 |
| Western Australia | 43,349 |
| Northern Territory | 14,858 |
| South Australia | 14,702 |
| Australian Capital Territory | 11,036 |
| Tasmania | 9,631 |
| Other Territories | 147 |
Coordinates were supplied consistently within each event; stateProvince mapping is checked for one value per event before aggregate counting.

## FEATURE SUMMARY
Geographic (2): `decimalLatitude`, `decimalLongitude`. Latitude/longitude retain their original decimalLatitude/decimalLongitude field names.
Temporal (6): `month`, `day_of_year`, `month_sin`, `month_cos`, `day_of_year_sin`, `day_of_year_cos`.
Environmental (22): `BIO1`, `BIO2`, `BIO3`, `BIO4`, `BIO5`, `BIO6`, `BIO7`, `BIO8`, `BIO9`, `BIO10`, `BIO11`, `BIO12`, `BIO13`, `BIO14`, `BIO15`, `BIO16`, `BIO17`, `BIO18`, `BIO19`, `elevation`, `climatological_tavg_event_month`, `climatological_prec_event_month`.
The positive predictor whitelist contains exactly 30 numeric columns. It excludes target labels, IDs, observer identity, QC/privacy flags, eventDate, conservation fields, and target-derived counts. Conservation status is evaluation/context metadata and never a predictor.
PRIMARY numeric summaries: n is the total primary row count; mean/SD/quantiles use available values. Standard deviation is sample SD and quartiles use R's default type-7 quantile. Geographic statistics describe clean/public positions only and do not publish point pairs.
| feature | feature_group | n | missing_n | missing_percent | mean | sd | min | p25 | median | p75 | max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| decimalLatitude | geographic | 247,406 | 0 | 0 | -32.7282 | 5.0018 | -43.6093 | -35.4161 | -33.7546 | -31.0346 | -9.4119 |
| decimalLongitude | geographic | 247,406 | 0 | 0 | 147.3123 | 8.3535 | 113.538 | 145.51 | 150.6151 | 151.434 | 153.63 |
| month | temporal | 247,406 | 0 | 0 | 7.5839 | 3.5109 | 1 | 5 | 9 | 11 | 12 |
| day_of_year | temporal | 247,406 | 0 | 0 | 215.328 | 107.1266 | 1 | 128 | 244 | 310 | 366 |
| month_sin | temporal | 247,406 | 0 | 0 | -0.2779 | 0.6758 | -1 | -0.866 | -0.5 | 0.5 | 1 |
| month_cos | temporal | 247,406 | 0 | 0 | 0.0597 | 0.6801 | -1 | -0.5 | 0 | 0.5 | 1 |
| day_of_year_sin | temporal | 247,406 | 0 | 0 | -0.2534 | 0.677 | -1 | -0.8359 | -0.5161 | 0.3366 | 1 |
| day_of_year_cos | temporal | 247,406 | 0 | 0 | 0.124 | 0.6798 | -1 | -0.5197 | 0.2595 | 0.7383 | 1 |
| BIO1 | environmental | 247,406 | 4,806 | 1.9426 | 16.8165 | 3.074 | 3.8708 | 14.6042 | 17.125 | 18.5708 | 28.4333 |
| BIO2 | environmental | 247,406 | 4,806 | 1.9426 | 10.4775 | 1.6308 | 4.5583 | 9.2667 | 10.3417 | 11.575 | 16.4667 |
| BIO3 | environmental | 247,406 | 4,806 | 1.9426 | 48.6352 | 2.7124 | 34.1549 | 46.8699 | 48.2228 | 50.3713 | 68.4588 |
| BIO4 | environmental | 247,406 | 4,806 | 1.9426 | 405.5839 | 68.6149 | 100.8177 | 370.3282 | 397.0295 | 430.2712 | 664.1324 |
| BIO5 | environmental | 247,406 | 4,806 | 1.9426 | 27.6489 | 2.5206 | 15.3 | 26 | 27.3 | 29.3 | 40.5 |
| BIO6 | environmental | 247,406 | 4,806 | 1.9426 | 6.0941 | 3.332 | -7.7 | 4.2 | 6.2 | 7.9 | 22.7 |
| BIO7 | environmental | 247,406 | 4,806 | 1.9426 | 21.5549 | 3.2339 | 8.8 | 19.4 | 21.3 | 23.2 | 32.5 |
| BIO8 | environmental | 247,406 | 4,806 | 1.9426 | 18.2977 | 5.8442 | -0.4167 | 12.65 | 21.1333 | 22.5333 | 31.55 |
| BIO9 | environmental | 247,406 | 4,806 | 1.9426 | 15.5375 | 4.0515 | 2.6667 | 12.9 | 15.0667 | 18.65 | 27.45 |
| BIO10 | environmental | 247,406 | 4,806 | 1.9426 | 21.6674 | 2.6684 | 9.3167 | 19.7 | 21.8333 | 23.35 | 31.9167 |
| BIO11 | environmental | 247,406 | 4,806 | 1.9426 | 11.6536 | 3.4221 | -2.4333 | 9.45 | 11.85 | 13.5333 | 25.6333 |
| BIO12 | environmental | 247,406 | 4,806 | 1.9426 | 1,045.274 | 370.3021 | 162 | 765 | 1,002 | 1,246 | 5,182 |
| BIO13 | environmental | 247,406 | 4,806 | 1.9426 | 144.8442 | 85.9741 | 24 | 90 | 134 | 163 | 1,176 |
| BIO14 | environmental | 247,406 | 4,806 | 1.9426 | 41.8825 | 15.7003 | 0 | 34 | 43 | 51 | 128 |
| BIO15 | environmental | 247,406 | 4,806 | 1.9426 | 36.4491 | 20.8854 | 8.9634 | 23.5234 | 29.8819 | 44.4997 | 143.4056 |
| BIO16 | environmental | 247,406 | 4,806 | 1.9426 | 395.981 | 211.869 | 65 | 251 | 378 | 451 | 2,765 |
| BIO17 | environmental | 247,406 | 4,806 | 1.9426 | 147.807 | 51.4603 | 1 | 121 | 151 | 184 | 570 |
| BIO18 | environmental | 247,406 | 4,806 | 1.9426 | 311.5181 | 198.511 | 28 | 163 | 303 | 397 | 2,045 |
| BIO19 | environmental | 247,406 | 4,806 | 1.9426 | 213.7268 | 87.044 | 1 | 154 | 208 | 250 | 884 |
| elevation | environmental | 247,406 | 4,806 | 1.9426 | 187.5565 | 255.0741 | -3 | 26 | 76 | 218 | 2,130 |
| climatological_tavg_event_month | environmental | 247,406 | 4,806 | 1.9426 | 16.8431 | 5.2353 | -0.3 | 12.8 | 17.1 | 20.9 | 32.5 |
| climatological_prec_event_month | environmental | 247,406 | 4,806 | 1.9426 | 91.659 | 57.6462 | 0 | 59 | 79 | 109 | 1,110 |
No missing values have been imputed, no features scaled, and no correlated features removed. Those are later EDA/modelling decisions.

## MISSINGNESS SUMMARY
Primary environmental NA events: **4,806 / 247,406 (1.9426%)**; extension: **2,009 / 213,675 (0.9402%)**; all clean: **7,633 / 519,414 (1.4695%)**.
**No NA rows were silently dropped.** Every cohort event remains in its integrated dataset and predictor companion. Per-feature environmental missingness is reported below; geographic/temporal missingness is in the feature summary.
| dataset | feature | n_events | missing_n | missing_percent |
| --- | --- | --- | --- | --- |
| all_clean_events | BIO1 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO2 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO3 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO4 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO5 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO6 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO7 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO8 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO9 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO10 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO11 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO12 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO13 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO14 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO15 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO16 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO17 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO18 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | BIO19 | 519,414 | 7,633 | 1.4695 |
| all_clean_events | elevation | 519,414 | 7,633 | 1.4695 |
| all_clean_events | climatological_tavg_event_month | 519,414 | 7,633 | 1.4695 |
| all_clean_events | climatological_prec_event_month | 519,414 | 7,633 | 1.4695 |
| all_clean_events | any_environmental_feature | 519,414 | 7,633 | 1.4695 |
| frog_primary_multiclass | BIO1 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO2 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO3 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO4 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO5 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO6 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO7 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO8 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO9 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO10 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO11 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO12 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO13 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO14 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO15 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO16 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO17 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO18 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | BIO19 | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | elevation | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | climatological_tavg_event_month | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | climatological_prec_event_month | 247,406 | 4,806 | 1.9426 |
| frog_primary_multiclass | any_environmental_feature | 247,406 | 4,806 | 1.9426 |
| frog_multispecies_extension | BIO1 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO2 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO3 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO4 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO5 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO6 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO7 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO8 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO9 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO10 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO11 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO12 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO13 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO14 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO15 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO16 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO17 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO18 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | BIO19 | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | elevation | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | climatological_tavg_event_month | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | climatological_prec_event_month | 213,675 | 2,009 | 0.9402 |
| frog_multispecies_extension | any_environmental_feature | 213,675 | 2,009 | 0.9402 |
| multispecies_recall_at_k_eligible | BIO1 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO2 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO3 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO4 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO5 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO6 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO7 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO8 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO9 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO10 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO11 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO12 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO13 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO14 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO15 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO16 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO17 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO18 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | BIO19 | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | elevation | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | climatological_tavg_event_month | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | climatological_prec_event_month | 127,322 | 1,251 | 0.9825 |
| multispecies_recall_at_k_eligible | any_environmental_feature | 127,322 | 1,251 | 0.9825 |
Source-cell diagnostics remain in environmental_na_diagnostics.csv and worldclim_na_neighbourhood.csv. An inside-extent NA or nearby valid cell does not authorize moving a point or filling an NA. Final preprocessing decisions remain for EDA and training/evaluation design.

## CONSERVATION SUMMARY
Confirmed EPBC-listed FrogID taxa by their exact official category, plus explicitly unresolved/not-confirmed names:
| conservation_group | epbc_category | species_count | raw_occurrence_rows | clean_occurrence_rows | raw_events | clean_events | raw_single_species_events | clean_single_species_events | retention_percent | selected_species_count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| confirmed_EPBC_listed | Endangered | 12 | 3,212 | 0 | 3,212 | 0 | 494 | 0 | 0 | 0 |
| confirmed_EPBC_listed | Vulnerable | 12 | 3,559 | 0 | 3,545 | 0 | 1,133 | 0 | 0 | 0 |
| not_confirmed_listed_or_unresolved | not_confirmed_listed_or_unresolved | 192 | 967,349 | 925,809 | 540,647 | 519,414 | 299,751 | 291,103 | 96.0727 | 18 |
Category event counts are distinct unions within category and can overlap across categories. Conservation group totals below also use event unions, never sums of species-event totals. Occurrence counts here refer to focal taxon rows.
| scope | species_count | raw_occurrence_rows | clean_occurrence_rows | raw_events | clean_events | raw_single_species_events | clean_single_species_events | retention_percent | selected_species_count |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| all_events | 216 | 974,120 | 925,809 | 542,287 | 519,414 | 301,378 | 291,103 | 95.7821 | 18 |
| confirmed_EPBC_listed | 24 | 6,771 | 0 | 6,749 | 0 | 1,627 | 0 | 0 | 0 |
| not_confirmed_listed_or_unresolved | 192 | 967,349 | 925,809 | 540,647 | 519,414 | 299,751 | 291,103 | 96.0727 | 18 |
Confirmed listed species: **24**; listed species surviving QC: **0**; listed species selected for modelling: **0**; unresolved/not-confirmed names: **192**.
Listed taxa contribute **6,771 raw records across 6,749 distinct recordings**, including **1,627 single-species recordings**. After whole-event QC these become **0 records / 0 events / 0 singles**.
Non-exclusive reasons for recordings containing a confirmed listed taxon (row counts include all co-detected source records in those recordings):
| reason | occurrence_rows | events | percent_events |
| --- | --- | --- | --- |
| negative_coordinate_uncertainty | 0 | 0 | 0 |
| zero_coordinate_uncertainty | 0 | 0 | 0 |
| nonpositive_coordinate_uncertainty | 0 | 0 | 0 |
| uncertainty_over_1000m | 17,892 | 6,749 | 100 |
| nonfinite_or_missing_uncertainty | 0 | 0 | 0 |
| obscured_geoprivacy | 17,892 | 6,749 | 100 |
| not_open_geoprivacy | 17,892 | 6,749 | 100 |
| generalised_location | 17,892 | 6,749 | 100 |
| missing_generalization_flag | 0 | 0 | 0 |
| invalid_coordinates | 0 | 0 | 0 |
| invalid_dates | 0 | 0 | 0 |
| incomplete_species | 0 | 0 | 0 |
The aggregate preparation data support later EDA quantifying public geoprivacy/QC retention and exclusion of confirmed listed taxa. The current 18-class vocabulary contains no confirmed listed species, so it cannot support a threatened-class predictive subgroup evaluation. This is not evidence that unmatched selected species are non-threatened. Subspecies-only matches remain unresolved and are documented in epbc_unmatched_species.csv; objective class selection is unchanged.

## FINAL DATASET INVENTORY
| dataset | rows | columns | unit | target | number_of_classes | predictor_count | date_min | date_max | missing_rows | purpose | missingness_basis |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| frog_primary_multiclass | 247,406 | 36 | one clean single-species recording event | scientificName | 18 | 30 | 2017-11-10 | 2023-11-09 | 4,806 | primary 18-class classification | at_least_one_environmental_feature_missing |
| frog_primary_predictors | 247,406 | 30 | primary recording; row-aligned predictors | NA | 18 | 30 | 2017-11-10 | 2023-11-09 | 4,806 | predictors only; target in aligned primary dataset | at_least_one_environmental_feature_missing |
| frog_multispecies_extension | 213,675 | 38 | clean recording with >=2 original species and >=1 selected species | species_list | 18 | 30 | 2017-11-10 | 2023-11-09 | 2,009 | future Top-k / Recall@k evaluation | at_least_one_environmental_feature_missing |
| frog_multispecies_predictors | 213,675 | 30 | extension recording; row-aligned predictors | NA | 18 | 30 | 2017-11-10 | 2023-11-09 | 2,009 | predictors only; targets in aligned extension dataset | at_least_one_environmental_feature_missing |
| species_metadata | 216 | 18 | one supplied raw scientific name | NA | NA | 0 | NA | NA | 192 | taxonomy/cohort/conservation lookup; 216 names, 18 selected | unresolved_or_not_confirmed_EPBC_listing |
For the four event/predictor datasets, missing_rows counts events missing at least one environmental predictor. For species_metadata, it counts unresolved/not-confirmed EPBC listing rows. Predictor companions contain no target column and align row-for-row with their corresponding labelled dataset. number_of_classes=18 refers to the selected model vocabulary; the extension's complete original labels may also contain unselected taxa.
PRIMARY TARGET: **scientificName**
PRIMARY UNIT: **one clean single-species FrogID recording event**
PRIMARY CLASSES: **18**
PRIMARY PREDICTORS: **30**
MULTISPECIES UNIT: **one clean recording with >=2 original detected species and >=1 selected species**
MULTISPECIES PURPOSE: **future Top-k / Recall@k evaluation**
The extension contains **142 distinct original species labels**; **127,322 recordings** have all original targets in the 18-class vocabulary.
Prepared RDS files:
- `data/processed/frog_primary_multiclass.rds`
- `data/processed/frog_primary_predictors.rds`
- `data/processed/frog_multispecies_extension.rds`
- `data/processed/frog_multispecies_predictors.rds`
- `data/processed/species_metadata.rds`
Key public handoff tables:
- `outputs/tables/class_distribution.csv`
- `outputs/tables/date_range_summary.csv`
- `outputs/tables/events_by_year.csv`
- `outputs/tables/events_by_month.csv`
- `outputs/tables/state_distribution.csv`
- `outputs/tables/geography_summary.csv`
- `outputs/tables/event_structure_summary.csv`
- `outputs/tables/species_per_event_distribution.csv`
- `outputs/tables/qc_flow_summary.csv`
- `outputs/tables/feature_summary.csv`
- `outputs/tables/dataset_inventory.csv`
- `outputs/tables/epbc_source_category_counts.csv`
- `outputs/tables/event_time_summary.csv`
- `outputs/tables/environmental_missingness.csv`
- `outputs/tables/conservation_species_retention.csv`
- `outputs/tables/conservation_category_retention.csv`
- `outputs/tables/conservation_group_retention.csv`
- `outputs/tables/conservation_qc_exclusion_summary.csv`
Reproduction instructions and validation evidence: [data pipeline](data-pipeline.md).

## EDA READINESS CHECK
PASS is recorded only for checks actually verified against the current inputs, validation evidence, renv environment, and Git state. A later edit requires regenerating this checklist.
[PASS] raw data present - data/raw/frogid/FrogID6_final_dataset.csv
[PASS] checksums validated - Six source files compared to committed MD5 pins
[PASS] processed primary data present - Primary RDS and aligned 30-column predictor RDS
[PASS] processed multispecies data present - Extension RDS and aligned predictor RDS
[PASS] species metadata present - One metadata row per original scientific name
[PASS] WorldClim integrated - Validated source/cache/event mapping fingerprints
[PASS] EPBC metadata integrated - Validated official source and one-row-per-name lookup fingerprints
[PASS] tests passed - cohorts=PASS; processed_data=PASS; conservation_retention=PASS; summary_data=PASS
[PASS] renv consistent - No issues found -- the project is in a consistent state.
[PASS] no uncommitted pipeline changes - git status verified; generated tables/report are excluded from pipeline-change check
[PASS] no raw/interim/processed files tracked by Git - git ls-files data/raw data/interim data/processed returned no files

