# WorldClim environmental context

The pipeline uses **WorldClim 2.1**, a **1970-2000 climatological baseline**, at
**30 arc-second** resolution (1/120 degree, approximately 1 km at the equator).
The latitude/longitude grid is WGS84 / EPSG:4326. Angular resolution does not
represent the same physical distance at every Australian latitude.

## Official sources and acquisition

- [WorldClim 2.1 historical climate documentation](https://www.worldclim.org/data/worldclim21.html)
- [Official geodata package reference](https://rspatial.github.io/geodata/reference/worldclim.html)
- [Official geodata implementation](https://github.com/rspatial/geodata/blob/master/R/worldclim.R)
- [Official country-specific raster directory](https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/)
- [Bioclimatic variable definitions](https://www.worldclim.org/data/bioclim.html)

`R/acquisition/download_worldclim.R` calls:

```r
geodata::worldclim_country(
  country = "AUS", var = variable, path = "data/raw/worldclim", version = "2.1"
)
# variable is each of "bio", "elev", "tavg", and "prec"
```

The package obtains `AUS_wc2.1_30s_{variable}.tif` from the official country
directory. It does not download global rasters. There is no lower-resolution
fallback. A failed download or an unexpected CRS, layer count/order, resolution
or geometry is an error requiring investigation.

`outputs/tables/worldclim_raster_metadata.csv` records the actual source URL,
package call, retrieval date/time, version, reference period, layer names,
layer count, WKT CRS, extent, grid resolution, byte size, MD5 and package versions.
Retrieval dates are preserved on subsequent loads of unchanged files. The raw
TIFFs and local acquisition manifest stay in ignored `data/raw/worldclim/`.

On the development Windows machine, PostgreSQL/PostGIS had set `PROJ_LIB` to
an older incompatible coordinate-system database. The acquisition script uses
terra's bundled PROJ/GDAL data within the current R process when available.
It does not alter machine settings and still requires successful EPSG:4326
validation. The installed geodata version caches country files under
`data/raw/worldclim/climate/wc2.1_country/`.

## Features and units

The source consists of 44 layers: BIO1-BIO19, elevation, 12 monthly mean
temperature layers and 12 monthly precipitation layers. Each event receives
22 environmental features: `BIO1` through `BIO19`, `elevation`,
`climatological_tavg_event_month` and `climatological_prec_event_month`.

Mean temperature is in degrees Celsius, monthly precipitation in millimetres,
and elevation in metres (WorldClim's SRTM-derived elevation layer). BIO1, BIO2,
BIO5-BIO11 use temperature units; BIO3 is an isothermality ratio multiplied by
100; BIO4 is temperature standard deviation multiplied by 100; BIO12-BIO14 and
BIO16-BIO19 are precipitation quantities in millimetres; BIO15 is precipitation
seasonality expressed as a coefficient of variation. Values are used in their
published WorldClim 2.1 units, without WorldClim 1-era temperature rescaling.

Monthly features select the layer corresponding to the recording's parsed
calendar month. They describe typical climate for that month during 1970-2000;
they are **not observed weather on the recording date**. The environmental
baseline predates the 2017-2023 FrogID recordings.

## Extraction, preservation and missingness

`R/integration/integrate_worldclim.R` reads the clean event table and extracts
all source layers once per distinct longitude/latitude pair using the
containing raster cell (`terra::extract(..., method="simple")`). Multiple
occurrence rows within an event and repeated coordinates across events do not
cause repeated extraction. Exact coordinate keys map results back to eventID,
and explicit checks prevent row multiplication or reordering.

The coordinate cache is reused only when coordinates, raster checksums and
layer structure agree. `data/interim/environmental/event_environment.rds`
contains one row per clean event and 22 features. Other private files retain
coordinate-level extraction values, validation metadata and event-level NA
diagnostics. None is committed.

The small public tables `environmental_missingness.csv`,
`worldclim_source_missingness.csv`, `worldclim_extraction_summary.csv` and
`environmental_na_diagnostics.csv` report missing values and integration counts
without coordinates or event IDs. Diagnostics distinguish points outside the
Australian raster extent, source NA cells inside the extent and missing event
month. Source NA cells can occur at coastline/land-mask boundaries or uncovered
islands; an inside-extent NA alone does not prove which cause applies. No NA is
interpolated and no event is removed by environmental integration. Any later
imputation or complete-case policy must be specified within training/evaluation
design; no such analysis is performed in this data-preparation stage.

The completed extraction covered **519,414 events at 371,054 distinct
coordinates**. **7,633 events (1.469541%)** have source NA in every one of the
22 final environmental features. All fall inside the raster extent. A source
grid neighbourhood check found valid elevation in an immediately adjacent cell
for **7,610** of those events (99.698677% of missing events), consistent with a
land-mask boundary. The remaining **23** have no valid immediate neighbour and
remain unresolved location/coverage cases. This diagnostic does not prove that
the recorded positions are on land or authorize moving them. The aggregate is
in `worldclim_na_neighbourhood.csv`; private diagnostics retain event IDs and
coordinates for review. Neighbouring cells are inspected only for diagnosis,
never to substitute environmental values.

## Citation and limitations

Fick, S.E. and Hijmans, R.J. (2017). WorldClim 2: new 1-km spatial resolution
climate surfaces for global land areas. *International Journal of Climatology*,
37(12), 4302-4315. See the official historical climate documentation above.

WorldClim's spatial interpolation, historical baseline and grid-cell scale
limit ecological interpretations. Raster context is not microhabitat, recording
conditions or direct evidence of a species' absence. These environmental
covariates do not remove citizen-science sampling bias or justify causal claims.
