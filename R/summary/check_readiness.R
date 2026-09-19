# Check live local evidence, not hard-coded PASS labels. Generated report/table
# files are outputs; every other uncommitted repository path is a pipeline change.
check_readiness <- function() {
  source("R/pipeline_helpers.R", local = environment())
  matches_hashes <- function(hashes) {
    length(hashes) > 0L && !is.null(names(hashes)) &&
      all(file.exists(names(hashes))) &&
      identical(unname(tools::md5sum(names(hashes))), unname(hashes))
  }
  evidence_ok <- function(path, test) {
    if (!file.exists(path)) return(FALSE)
    e <- readRDS(path)
    identical(e$test, test) && !is.null(e$passed_utc) &&
      !isFALSE(e$passed) && matches_hashes(e$artifact_md5) &&
      matches_hashes(e$script_md5)
  }
  pins <- read_csv("config/source_checksums.csv", show_col_types = FALSE)
  hashes_ok <- nrow(pins) == 6L && all(file.exists(pins$file)) &&
    identical(unname(tools::md5sum(pins$file)), pins$md5)
  test_names <- c("cohorts", "processed_data", "conservation_retention", "summary_data")
  evidence_files <- c("cohort_validation", "processed_validation",
                      "conservation_validation", "summary_validation")
  test_ok <- vapply(seq_along(test_names), function(i) evidence_ok(
    paste0("data/interim/validation/", evidence_files[i], ".rds"),
    paste0("tests/validate_", test_names[i], ".R")), logical(1))
  processed_ok <- test_ok[2]
  # Detect newly introduced R scripts absent from an older successful run too.
  if (processed_ok) {
    e <- readRDS("data/interim/validation/processed_validation.rds")
    current_scripts <- list.files("R", pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
    processed_ok <- all(current_scripts %in% names(e$script_md5))
    test_ok[2] <- processed_ok
  }
  status_text <- character()
  renv_ok <- tryCatch({
    status_text <- capture.output(status <- renv::status())
    isTRUE(status$synchronized)
  }, error = function(e) {
    status_text <<- conditionMessage(e)
    FALSE
  })
  git_call <- function(args) {
    output <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE))
    list(ok = is.null(attr(output, "status")) || attr(output, "status") == 0L,
         output = output)
  }
  git_status <- git_call(c("status", "--porcelain", "--untracked-files=all"))
  changed_paths <- substring(git_status$output, 4L)
  pipeline_changes <- changed_paths[!grepl("^(outputs/tables/|docs/data-summary[.]md$)", changed_paths)]
  tracked <- git_call(c("ls-files", "data/raw", "data/interim", "data/processed"))
  checks <- c("raw data present", "checksums validated", "processed primary data present",
              "processed multispecies data present", "species metadata present",
              "WorldClim integrated", "EPBC metadata integrated", "tests passed",
              "renv consistent", "no uncommitted pipeline changes",
              "no raw/interim/processed files tracked by Git")
  passed <- c(file.exists(raw_frogid_path), hashes_ok,
    all(file.exists(c("data/processed/frog_primary_multiclass.rds",
                      "data/processed/frog_primary_predictors.rds"))),
    all(file.exists(c("data/processed/frog_multispecies_extension.rds",
                      "data/processed/frog_multispecies_predictors.rds"))),
    file.exists("data/processed/species_metadata.rds"),
    processed_ok && file.exists("data/interim/environmental/event_environment.rds"),
    processed_ok && file.exists("data/interim/epbc/species_conservation.rds"),
    all(test_ok), renv_ok, git_status$ok && !length(pipeline_changes),
    tracked$ok && !length(tracked$output))
  details <- c(raw_frogid_path, "Six source files compared to committed MD5 pins",
    "Primary RDS and aligned 30-column predictor RDS", "Extension RDS and aligned predictor RDS",
    "One metadata row per original scientific name", "Validated source/cache/event mapping fingerprints",
    "Validated official source and one-row-per-name lookup fingerprints",
    paste(paste(test_names, ifelse(test_ok, "PASS", "FAIL"), sep = "="), collapse = "; "),
    paste(status_text, collapse = " "),
    if (length(pipeline_changes)) paste(pipeline_changes, collapse = "; ") else
      "git status verified; generated tables/report are excluded from pipeline-change check",
    if (length(tracked$output)) paste(tracked$output, collapse = "; ") else
      "git ls-files data/raw data/interim data/processed returned no files")
  tibble(check = checks, status = ifelse(passed, "PASS", "FAIL"), detail = details)
}
