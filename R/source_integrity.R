# Committed fingerprints freeze the exact research inputs across fresh clones.
verify_source <- function(path) {
  pins <- utils::read.csv("config/source_checksums.csv", stringsAsFactors = FALSE)
  pin <- pins[pins$file == gsub("\\\\", "/", path), , drop = FALSE]
  if (nrow(pin) != 1L || !file.exists(path) ||
      !identical(unname(tools::md5sum(path)), pin$md5)) {
    stop("Source missing, unpinned, or changed: ", path,
         ". Restore the frozen source; do not silently update its fingerprint.")
  }
  invisible(TRUE)
}
