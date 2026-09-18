# The project .Rprofile activates renv. Install only direct pipeline dependencies.
required <- c("readr", "dplyr", "tidyr", "stringr", "lubridate", "tibble", "terra", "geodata", "jsonlite")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) renv::install(missing)
renv::snapshot(packages = c(required, "renv"), prompt = FALSE)
renv::status()
