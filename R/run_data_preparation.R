# Reproducible preparation only. Run: Rscript R/run_data_preparation.R
# renv is automatically activated by the project .Rprofile.
source("R/cleaning/build_cohorts.R", local = new.env(parent = globalenv()))
source("tests/validate_cohorts.R", local = new.env(parent = globalenv()))
source("R/integration/integrate_worldclim.R")
integrate_worldclim()
source("R/acquisition/download_epbc.R", local = new.env(parent = globalenv()))
source("R/integration/integrate_epbc.R", local = new.env(parent = globalenv()))
source("R/integration/build_processed_data.R", local = new.env(parent = globalenv()))
source("tests/validate_processed_data.R", local = new.env(parent = globalenv()))
