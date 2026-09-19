# Canonical end-to-end FrogID data-preparation pipeline.
#
# Run from the repository root with:
#   Rscript R/run_data_preparation.R
#
# The project .Rprofile activates renv automatically.
#
# This script performs data acquisition/verification, cleaning, integration,
# processed-dataset construction, validation, conservation-retention
# preparation, and EDA-readiness summarisation.
#
# It does NOT perform exploratory analysis, imputation, scaling, balancing,
# feature selection, model fitting, or evaluation.

if (!all(file.exists(c(
  ".Rprofile",
  "R/pipeline_helpers.R",
  "config/source_checksums.csv"
)))) {
  stop(
    "Run R/run_data_preparation.R from the FrogID repository root.",
    call. = FALSE
  )
}

step_number <- 0L

run_step <- function(label, code) {
  step_number <<- step_number + 1L

  message("")
  message("============================================================")
  message(sprintf("STEP %02d: %s", step_number, label))
  message("============================================================")

  started <- Sys.time()

  result <- force(code)

  elapsed <- as.numeric(
    difftime(Sys.time(), started, units = "secs")
  )

  message(sprintf(
    "Completed STEP %02d in %.1f seconds.",
    step_number,
    elapsed
  ))

  invisible(result)
}


# -------------------------------------------------------------------------
# 1. FrogID acquisition / source-integrity verification
# -------------------------------------------------------------------------

run_step(
  "Acquire or verify immutable FrogID Dataset 6 source",
  source(
    "R/acquisition/download_frogid.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 2. Build clean event cohorts and frozen model vocabulary
# -------------------------------------------------------------------------

run_step(
  "Build FrogID clean, primary and multispecies cohorts",
  source(
    "R/cleaning/build_cohorts.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 3. Validate cohort construction independently
# -------------------------------------------------------------------------

run_step(
  "Validate FrogID cohorts",
  source(
    "tests/validate_cohorts.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 4. Acquire/verify WorldClim and integrate environmental context
#
# integrate_worldclim() validates the existing coordinate cache and reuses it
# when the clean coordinates and frozen raster fingerprints are unchanged.
# -------------------------------------------------------------------------

run_step(
  "Integrate WorldClim environmental context",
  {
    source("R/integration/integrate_worldclim.R")
    integrate_worldclim()
  }
)


# -------------------------------------------------------------------------
# 5. Acquire or verify the frozen official EPBC/SPRAT source
# -------------------------------------------------------------------------

run_step(
  "Acquire or verify official EPBC/SPRAT source",
  source(
    "R/acquisition/download_epbc.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 6. Attach conservation metadata to the frozen species vocabulary
# -------------------------------------------------------------------------

run_step(
  "Integrate EPBC conservation metadata",
  source(
    "R/integration/integrate_epbc.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 7. Build final processed analysis datasets and predictor matrices
# -------------------------------------------------------------------------

run_step(
  "Build final processed datasets",
  source(
    "R/integration/build_processed_data.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 8. Validate all integrated processed datasets
# -------------------------------------------------------------------------

run_step(
  "Validate processed datasets and integrations",
  source(
    "tests/validate_processed_data.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 9. Prepare conservation/geoprivacy retention aggregates
# -------------------------------------------------------------------------

run_step(
  "Build conservation and geoprivacy retention summaries",
  {
    source("R/summary/build_conservation_retention.R")
    build_conservation_retention()
  }
)


# -------------------------------------------------------------------------
# 10. Validate conservation/geoprivacy aggregates independently
# -------------------------------------------------------------------------

run_step(
  "Validate conservation retention summaries",
  source(
    "tests/validate_conservation_retention.R",
    local = new.env(parent = globalenv())
  )
)


# -------------------------------------------------------------------------
# 11. Generate and validate the complete EDA-readiness handoff
#
# summarise_for_eda() writes the aggregate handoff tables and docs/data-summary.md.
# It also runs tests/validate_summary_data.R before evaluating the live
# readiness checklist.
# -------------------------------------------------------------------------

eda_result <- run_step(
  "Generate and validate EDA-readiness handoff",
  {
    source("R/summary/summarise_for_eda.R")
    summarise_for_eda()
  }
)


# -------------------------------------------------------------------------
# Final status
# -------------------------------------------------------------------------

readiness <- eda_result$readiness

if (is.null(readiness) ||
    !all(c("check", "status", "detail") %in% names(readiness))) {
  stop(
    "EDA-readiness result was not returned correctly.",
    call. = FALSE
  )
}

failed <- readiness[readiness$status != "PASS", , drop = FALSE]

message("")
message("============================================================")
message("FINAL DATA-PREPARATION STATUS")
message("============================================================")

if (!nrow(failed)) {

  message("All readiness checks passed.")
  message("DATA PREPARATION STATUS: READY FOR EDA")

} else {

  message(
    "The data pipeline completed, but the following live readiness ",
    "checks are not yet PASS:"
  )

  for (i in seq_len(nrow(failed))) {
    message(
      " - ",
      failed$check[i],
      ": ",
      failed$detail[i]
    )
  }

  message("")
  message(
    "A Git-cleanliness failure is expected when this runner itself has ",
    "uncommitted edits. Commit the verified pipeline and rerun the summary ",
    "to obtain the final clean-state certification."
  )

  message("DATA PREPARATION STATUS: NOT READY")
}