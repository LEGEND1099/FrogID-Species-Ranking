# STAT5003 A2 report-assets consolidation manifest

Prepared: 2026-10-31 (Australia/Sydney).
Repository: `LEGEND1099/FrogID-Species-Ranking`.
Verified local `main` and freshly fetched `origin/main` baseline:
`98c44d6fe708161e19501c192a942e970bc878a1`.
Intended review branch: `review/stat5003-a2-report-assets`.

## Canonical approved assets

Paths below are relative to the repository root. SHA-256 values identify exact
file bytes, not rendered Markdown or Git object IDs.

| Canonical path | Authority / purpose | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `R/reporting/04_final_report_figures.R` | Authoritative figure source | 20097 | `bcd452dcbbbeb11afb042c67249dde0a4f82127acf2e7817892e7d7d0a5235c7` |
| `reports/FinalReport/final_report_theme.css` | Authoritative report theme | 6444 | `f9b9ef8faefe1f2ea482ea72abc1444aa7cf9ad93b2766d9e257280c081573d3` |
| `outputs/figures/final_report/report_final_cleaning_flow.png` | Approved cleaning flow | 135438 | `731ec6970860c0e0f52dab7b8c540d32a1cbee9e162bd42c23c3453e8d808f90` |
| `outputs/figures/final_report/report_final_geographic_examples.png` | Approved four-species geography | 223209 | `58abe53732eff7464eab1d4cdd1ac0024fcaba089b6d9a63b762d8454e55d6d5` |
| `outputs/figures/final_report/report_final_rf_vs_xgb_rare_species.png` | Approved rare-six F1 and recall | 136677 | `a7c0a3bdb48d0914fa4fc45c63480347036e18116670cb60a7410fce40777fd1` |
| `outputs/figures/final_report/report_final_rf_vs_xgb_all_species.png` | Approved all-18-species F1 | 268962 | `99f29d7a16e1bdd3ef8cef7c91af9b67210720e74e03b7656f646f1fb9147637` |
| `reports/FinalReport/STAT5003_A2_Evidence_and_Figure_Blueprint_UPDATED.md` | Authoritative planning blueprint | 23851 | `1e7ed0c31075eea48c6c4ee2c7ace109497b7f523ca5c5ba475783d49a0116fe` |

This manifest is the eighth authorised review file. Its own hash is verified
externally against the staged and remote bytes; it is not embedded here.

## Source fidelity and verification

- The six reviewed figure/theme files match the SHA-256 hashes recorded at the
  end of the approved repair pass. They were not edited or regenerated during
  consolidation.
- The current `R/reporting/04_final_report_figures.R` is authoritative. Neither
  its `.bak` nor the script in `Colour_Refresh_Temp/` was used as a replacement.
- The current `reports/FinalReport/final_report_theme.css` is authoritative.
  Preview/package copies are preserved locally and are not staged.
- The updated blueprint was copied from
  `Final Report/STAT5003_A2_Evidence_and_Figure_Blueprint_UPDATED.md` to the
  canonical path above. Source and copy are byte-identical: SHA-256
  `1e7ed0c31075eea48c6c4ee2c7ace109497b7f523ca5c5ba475783d49a0116fe`,
  23,851 bytes. Original content, including Markdown hard line breaks, is retained.
- R parsing passed without executing the plotting script. All four PNGs decoded
  successfully and were visually inspected. Dimensions are: cleaning 2550 x 1225;
  geography 2375 x 1650; rare-six 2750 x 1250; all-species 1850 x 1750 pixels.
- The saved cohort and CSV checks reconfirmed 247,406 selected recordings,
  4,806 missing the 22-variable environmental block, and 242,600 complete cases
  across all 18 species. The single-species and class-threshold restrictions are
  cohort selection rather than quality-control failures.
- Saved RF/XGBoost M4 spatial Macro-F1 values remain
  0.34876372963704877 / 0.3515746935854938. Rare-six mean F1 remains
  0.36616470998015765 / 0.35176866230636833; mean recall remains
  0.4008538628497746 / 0.3649472501467951. XGBoost has higher F1 on 12/18 species.
- The illustrative map retains four named species, all their complete-case
  recordings (140,806), fixed 0.5-degree cells and 695 species/cell combinations.
  It is not an all-18-species map or a biological-range estimate.
- Statistical outputs and model code were not modified. No training, tuning,
  package installation, lockfile update or figure regeneration was performed.
- R issued nonfatal startup warnings for the unavailable `C.UTF-8` locale.
  Parsing and statistical checks passed.
- The default staged whitespace check reports the blueprint's existing two-space
  Markdown hard line breaks on lines 3-5. The user explicitly approved these three
  exceptions so the canonical copy stays byte-identical to the preserved source.
  No whitespace normalisation or Git configuration change is applied. All other
  staged whitespace findings must remain absent before committing.

## Local files preserved but excluded from this checkpoint

The following original untracked files remain in their existing locations;
nothing in this list is moved, deleted, archived or staged:

- `Colour_Refresh_Temp/04_final_report_figures_COLOUR.R`
- `Colour_Refresh_Temp/STAT5003_Colour_Refresh_README.md`
- `Colour_Refresh_Temp/STAT5003_Colour_Theme_Preview.html`
- `Colour_Refresh_Temp/final_report_theme.css`
- `Final Report/STAT5003_A2_Evidence_and_Figure_Blueprint.md`
- `Final Report/STAT5003_A2_Evidence_and_Figure_Blueprint_UPDATED.md`
- `Final Report/STAT5003_group_project_Quarto_template.qmd`
- `Final Report/STAT5003_group_project_RMarkdown_template.Rmd`
- `R/reporting/04_final_report_figures.R.bak`
- `STAT5003_Codex_Audit_Prompt.md`
- `STAT5003_Colour_Refresh_Package.zip`
- `STAT5003_Final_Review.zip`
- `reports/FinalReport/STAT5003_Colour_Refresh_README.md`
- `reports/FinalReport/STAT5003_Colour_Theme_Preview.html`

The original `Final Report/` directory, both templates and both original
blueprints remain untouched. Local-only/ignored `data/interim/`,
`renv/library/`, `renv/staging/` and `reports/.Rhistory` remain outside the
checkpoint. Existing ignore rules are unchanged.

Existing tracked Assignment 1 v4 QMD/HTML, Assignment 2 draft QMD/HTML, submitted
presentation, `R/modelling/`, `analysis/`, `data/`, saved folds/results,
`outputs/tables/` and `renv.lock` are preserved unchanged.

## Submission and review limits

The final Quarto submission
`reports/FinalReport/STAT5003_A2_Final_Report.qmd` does not exist yet.
The updated blueprint is planning material, not the final submission.
Full ten-page printed A4 compliance has not been verified against a final HTML.

The separate prevalence-correction sensitivity is not established as independently
reproducible end to end from committed source. Multi-species and temporal
extensions are not represented as completed model experiments.

This is an additions-only review checkpoint: exactly the seven canonical assets
plus this manifest. No deletions, renames, historical overwrites, archival,
cleanup, direct push to `main`, merge or auto-merge are authorised by this task.
GitHub `main` verification after an independently reviewed and separately approved
merge is a prerequisite to any future cleanup; no cleanup is performed here.
