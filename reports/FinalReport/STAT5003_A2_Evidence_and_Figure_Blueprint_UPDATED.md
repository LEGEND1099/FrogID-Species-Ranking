# STAT5003 Assignment 2 — Final Evidence & Figure Blueprint

**Group:** W11G03  
**Status:** Evidence selection complete; **not** a drafted or rendered final report.  
**Submission authority:** Week 12 written-report guide and 30-mark rubric provided by the group; HTML maximum 10 printed pages; folded, inspectable code; APA 7; accurate AI-use statement.  
**Authoritative inputs:** Full-mark A1 `STAT5003_W11G03_Plan_EDA_v4.qmd` and submitted HTML; consolidated A2 `reports/STAT5003_A2_Report.qmd`; implemented scripts, saved aggregate tables and generated figures on `main` of `LEGEND1099/FrogID-Species-Ranking`. The earlier `STAT5003_W11G03_Plan_EDA(1).qmd` is a draft, **not** the submitted A1 source.

## A. Locked narrative

**Research:** Can a model rank 18 frog species from recording time, WorldClim context, elevation and optionally public location **without listening to the audio**, and how does apparent performance change when geographic cells are held out? **Data story:** public FrogID data have imbalance, clustering and unequal environmental coverage → objective cleaning and feature engineering → common, separated random/spatial assessment → five complementary classifier families → random performance overstates spatial transfer → XGBoost wins the declared spatial Macro-F1 metric narrowly; RF is a transparently post-hoc, application-dependent preference for better *mean* coverage of the six least-recorded species. The results **do not** prove abundance, ecological absence, causal environmental effects, conservation performance or superiority on all species.

**Cohort lineage:** 974,120 occurrence rows / 542,287 distinct events → 519,414 events after event-level public-location QC (**22,873 event exclusions**) → 291,103 clean single-species events; among those, 247,406 events belonging to the objectively selected 18 species → 242,600 common modelling complete cases after excluding **4,806** events with all 22 environmental variables missing. The single-species selection is a cohort branch, **not** a sequential QC loss. A distinct 213,675-event multi-species extension was prepared but **not evaluated as a completed A2 model experiment**.

**Evidence standards:** A1 EDA data commonly use 247,406; A2 results use 242,600. Do not silently mix denominators. Six least-recorded means six species with smallest observed sample support, **not necessarily threatened taxa**. XGBoost's 0.351575 versus RF's 0.348764 is an observed three-fold mean difference, **not** a statistically tested advantage. RF's rare-six recall 0.401 is higher **than XGBoost's 0.365**, but PCA-LDA's rare-six mean recall was 0.447 (with much poorer F1 and overall shortlist performance); never claim RF has the best rare-species recall of *every* classifier. Inner-tuned hyperparameters and early stopping were not chosen from outer assessment folds.

## B. Ten-section report architecture and evidence-to-claim map

### 1. Introduction, Motivation & Research Question (~0.5 page)
- **Evidence:** A1 `STAT5003_W11G03_Plan_EDA_v4.qmd`, `# Framing & Dataset Selection`; A2 `reports/STAT5003_A2_Report.qmd`, executive summary and interpretation sections.
- **Use:** Accessible definition of contextual 18-class species ranking; no audio; scientist/expert-review shortlist; risk of misleading performance on new locations; concern for sampling and public geoprivacy.
- **Do not:** Claim autonomous species identification, conservation-grade detection, abundance or occupancy.
- **Visual:** None; save space.

### 2. Dataset, Integration & Four-Criterion Justification (~0.7 page)
- **Evidence:** A1 `# Consider & Gather Data`; `docs/data-pipeline.md`, `docs/data-summary.md`, `outputs/tables/dataset_inventory.csv`, `outputs/tables/worldclim_extraction_summary.csv`.
- **Prove:** **Large** (974,120 occurrence rows / 542,287 events, >10,000); **Messy** (22,873 location-QC exclusions; 4,806 environmental-missing primary events); **Integrated** (FrogID location/month → WorldClim BIO1–19, elevation, climatological monthly temperature and precipitation; scientific name → EPBC metadata *for context only*); **Multiclass** (18 species, ~41:1 frequency imbalance). Explicitly say **not Complex >100 predictors** (30 A1 whitelisted; 28 in A2 M4).
- **Visual:** One 4-row concise dataset-qualification table, not a figure.
- **Accuracy:** Climate values are long-term WorldClim 1970–2000 averages, not date-specific weather; input records cover 2017–2023.

### 3. Data Cleaning & Cohort Construction (~0.4–0.5 page)
- **Evidence:** `docs/data-pipeline.md` and `outputs/tables/qc_filter_flow.csv`; A1 source description; `outputs/tables/eda06_missingness_summary.csv`.
- **Use:** Recording-event identity, species-label/date/coordinate consistency; coordinate uncertainty >0 and <=1 km; open geoprivacy; no location generalisation; full-event exclusion if any source occurrence row fails QC; 18 classes selected with >=2,000 clean single-species events; complete-case reduction to 242,600 with no imputation.
- **Visual:** Compact one-line flow/table (542,287 → 519,414 → 247,406 → 242,600), with a clear *branch* label to avoid treating omitted multispecies observations as corrupt. Not a large separate graphic.
- **Critical:** QC reason counts overlap; do not sum overlapping geoprivacy/uncertainty counts. Explain geographically uneven missingness as an external validity limitation.

### 4. EDA & Hypothesis-to-Decision Chain (~1.3–1.6 pages)
- **Evidence:** A1 final v4 QMD (figures 1,2,4,5,6 and correlation table); `outputs/tables/eda05_environmental_correlation_pairs.csv`, `eda03_species_season_summary.csv`, `eda06_missingness_summary.csv`, `eda09_validation_summary.csv`, `eda09b_environment_quartile_summary.csv`.
- **Claims/decisions:** (a) top two species ~53.4% in complete cases and ~41:1 skew → Macro-F1 and per-class audit; (b) 30.2% events share exact coordinates and top ten 0.5-degree cells contain 40.1% → geographic grouping; (c) 4,806 environmental NAs geographically concentrated, top ten 1-degree cells contain ~77.2% of missing events → transparent complete-case limitation; (d) within-species seasonality (Cramér's V 0.197 in A1, peak month differences) → cyclic month/day features; (e) 8 environmental pairs with |Spearman rho|>=0.90 (BIO13/BIO16 .990, BIO1/BIO11 .970), BIO7≈BIO5−BIO6 → regularisation/PCA; (f) A1 environment-vs-species-mix relationship is descriptive after accounting for distance, not causal.
- **Visuals:** F1 frequency and F2 missingness map are **core**; F3 restricted geographic footprints **core if legible**. Seasonality chart and A1 environment-composition graph are **reserve**. Compact correlation 2–3-row table instead of all 8 pairs.

### 5. Preprocessing, Features & Validation (~0.9–1.1 page)
- **Evidence:** `R/modelling/modelling_helpers.R`, `01_build_folds.R`, model scripts, A2 report.
- **Use:** M0 (frequency, no predictors), M1 (4 cyclic), M2 (25), M3 (26 with elevation), M4 (28 with coordinates); 30 A1 whitelist includes two original calendar fields excluded from actual modelling set; model-specific standardisation (elastic-net glmnet; LDA + kNN); environmental-only PCA for LDA/kNN (22 features; retain >=95% training variance); kNN whitening but not LDA whitening; tree models no PCA/scaling. Spatial metadata used for folds even in M3 without lat/lon model predictors.
- **Validation:** frozen three random stratified outer folds versus three 0.5-degree cell-blocked spatial outer folds; inner ~80/20 fit/tune within each outer development partition; entire development refit; assessment untouched, preprocessing refitted inside training only. Grouping prevents *same-cell*, not adjacent-cell, overlap.
- **Visual:** F4 conceptual validation schematic; concise M0–M4 feature table.

### 6. Model Implementation & Improvement (~1.4–1.6 pages)
- **Evidence:** `R/modelling/02_m0_baseline.R`, `03_elastic_net.R`, `04_pca_lda.R`, `05_pca_knn.R`, `06_random_forest.R`, `07_xgboost.R`; `model_*_selected.csv`, `model_*_tuning.csv`, A2 report 'Why these parameters'.
- **Use:** Five classifiers plus baseline; why each adds a different assumption; bounded, specific grids: elastic-net alpha 0/.5/1 and up to 30 lambda; PCA-LDA n95/n95+2/n95+4; PCA-kNN k 7/21/51 and n95 or n95+2; RF 200 fixed trees, mtry 5/10, minimum node size 5/20; XGB depth 3/6, eta .07/.15, min child weight 2/8, up to 300 rounds, inner log-loss early stopping patience 25, inner Macro-F1 candidate selection.
- **Show refinement *outcomes*, not just settings:** spatial LDA retained 11/8/7 PCs; kNN k 21/21/7; RF mtry 5/5/10 + node 5/5/5; XGB 58/82/121 rounds. Elastic-net tested early M1–M4; other four families only M3/M4. Compare M3→M4 to isolate incremental coordinates.
- **Visual:** One narrow tuning grid + selected-outcomes table, not five separate plots. At least one genuine folded, executable R code block importing actual saved tables/plotting (not just `eval=FALSE` pseudocode). Refer to full model scripts for training implementation.

### 7. Model Evaluation & Final Selection (~2.0–2.2 pages)
- **Evidence:** `outputs/tables/report_m4_spatial_leaderboard.csv`, `report_model_summary.csv`, `report_m3_m4_effect.csv`, `report_species_equity_scorecard.csv`, `report_species_equity_rf_vs_xgb.csv`; figures `report_v1_m4_comparison.png`, `report_v1_coordinate_effect.png`, `report_v1_species_equity_heatmap.png`.
- **Must report:** Primary metric spatial Macro-F1; M4 XGB .352, RF .349, kNN .321, LDA .290, elastic-net .266; M0 .029. Random-vs-spatial: RF .692→.349, XGB .656→.352; do not equate gap with proven overfitting. M3→M4: XGB +.02462, RF +.00640 spatial. Compare overall accuracy and Top-3 as ranking utility. Near tie not statistically resolved on three folds.
- **Species audit:** For **rare six**, RF vs XGB means: recall .401/.365; Top-3 .775/.740; F1 .366/.352. But XGB higher individual F1 in 12/18 species. RF choice **post-hoc preference**, not primary-metric winner. Explicitly note PCA-LDA had higher mean recall for rare six than both, but unacceptable weak average F1/overall performance for the chosen task, to avoid falsely claiming RF won every equity measure.
- **Figures:** F5 random/spatial bar chart, F6 paired coordinate differences, F7 all-18-species RF/XGB F1 chart at `outputs/figures/final_report/report_final_rf_vs_xgb_all_species.png` (six lowest-support classes shaded); preferable to the dense five-model heatmap. The six-only F1/recall graphic remains an optional diagnostic. Plus a small 5-row leaderboard table.
- **Imbalance sensitivity:** One short paragraph: separate elastic-net prior-correction gamma 0/.5/1, tuned gamma .5, spatial Macro-F1 .266→.344 but Top-3 .837→.811, accuracy .497→.448 and MRR .683→.647; **not** SMOTE or model-wide RF/XGB effect. F8 trade-off graphic is **conditional** because its independently rerunnable original experiment source is not yet in `main`; disclose the provenance/reproducibility limit if included. The exploratory correction-strength curve was not used for hyperparameter selection.

### 8. Data Investigation Process Reflection (~0.4–0.5 page)
- **Evidence:** A1 `# Project Planning` vs A2 actual scripts/results. Explain diagnose → choose features/metrics/folds → tune independently → compare → reconsider utility and limitations. Concrete deviations: A1 proposed XGB M1–M4 but implementation only M3/M4; proposed multi-species/temporal extensions not completed; geographic transfer concern confirmed. Avoid a generic paragraph that claims all original plans were executed.
- **Visual:** None.

### 9. Conclusion, Limitations & Implications (~0.5–0.6 page)
- **Use:** Direct answer to the research question: context helps vs prevalence alone, but held-out spatial performance materially weaker than random. XGB best prespecified Macro-F1; RF application-specific and exploratory due to better average rare-six coverage; still weak minimum species F1. Limitations: observational presence-only records, geoprivacy exclusions, clustered missingness, adjacent-block dependence, 18-class/single-species-only scope, WorldClim historical normals, no independent temporal-transfer test, only 3 folds; require expert review.
- **Visual:** None.

### 10. APA 7 References & AI-use Declaration (~0.7–0.9 page)
- **Evidence:** A1 v4 reference list for Australian Museum FrogID Dataset 6, Gillard/Rowley, Rowley/Callaghan, WorldClim Fick/Hijmans, DCCEEW; A2 references Breiman, Chen/Guestrin, Roberts, Valavi, Sokolova/Lapalme. Confirm claims are actually cited near the relevant passage; URLs/author/year/DOIs checked before submission. A1 AI disclosure names ChatGPT, Claude, Codex; final A2 disclosure must accurately describe **actual** A2 uses and model versions/publishers as required by template; do not invent versions. Fold code and report code; state limitations of entirely independent regeneration of the separate class-imbalance experiment.

## C. Figure register — selection decisions

| ID | Priority | Figure in final report | Source / asset | Primary purpose | Treatment |
|---|---|---|---|---|---|
| **F1** | **LOCKED** | 18-class frequency bars | A2 `outputs/figures/report_v1_species_frequency.png` | Unequal class support → Macro-F1 | Use A2 **242,600** cohort graphic, not A1's different denominator; 0.35–0.45 printed page |
| **F2** | **LOCKED** | Geographic missingness | A1 `fig-missingness-map` in `STAT5003_W11G03_Plan_EDA_v4.qmd`; underlying `eda06_grid_missingness_1deg.csv` | Justify complete-case exclusions, discuss spatial bias | Reuse A1 figure/code, clear 1° grid versus modelling 0.5° grid distinction; 0.35–0.45 page |
| **F3** | **GENERATED** | Selected-species geographic footprints, 2×2 rather than 18 small panels | A1 `fig-species-footprints` plotting code and the existing event-level processed RDS, aggregated to 0.5° cells; original A1 18-panel figure | Demonstrate geographically uneven species observations | Generated as `outputs/figures/final_report/report_final_geographic_examples.png`. Keep the **four-species illustrative panel** with shared geographic scale; not a range map |
| **F4** | **LOCKED** | Conceptual random-versus-spatial fold schematic | A2 `outputs/figures/report_v1_validation_schematic.png` | Explain validation without misrepresenting scheme | Compact 1/4–1/3 page; caption must say illustrative only, **not real fold map** |
| **F5** | **LOCKED** | M4 random versus spatial Macro-F1 by family | A2 `outputs/figures/report_v1_m4_comparison.png` | Main result and geographic-transfer gap | Full-width chart; SD whiskers explicitly fold SD **not confidence intervals** |
| **F6** | **LOCKED** | M4 minus M3 paired coordinate effect | A2 `outputs/figures/report_v1_coordinate_effect.png` | Feature refinement / geography value | Use spatial values XGB +0.0246, RF +0.0064, avoid causal claim |
| **F7** | **GENERATED** | RF versus XGB per-species F1; visibly tag rare six | `outputs/figures/final_report/report_final_rf_vs_xgb_all_species.png`, built from saved `report_species_equity_rf_vs_xgb.csv` and `report_species_equity_scorecard.csv` | Explain genuine post-hoc model-selection trade-off | Use all 18 F1 rows (ordered by class support), shade the six least-recorded, annotate that XGB wins F1 on 12/18 and rare-six mean F1 and recall favour RF. Do **not** imply RF wins every less-recorded species; retain the six-species F1/recall image only as an optional diagnostic |
| **F8** | **RESERVE** | Species–season heatmap | A1 `fig-season` / `eda03_species_month_distribution.csv` | Justify cyclic calendar features | Use only if EDA section needs a third substantive relationship figure and 10-page test allows; else report Cramér's V=0.197 and species peaks in prose |
| **F9** | **CONDITIONAL** | Elastic-net nested prevalence-correction trade-off | `outputs/figures/class_imbalance/prior_correction_nested_tradeoffs.jpeg` | Demonstrate optimization objective trade-off | Include only if enough pages and source/provenance adequately documented; otherwise concise supported numeric paragraph with explicit independent-rerun limitation |
| **F10** | **OMIT** | Full 18-panel species map | A1 `fig-species-footprints` or A2 `report_v1_geographic_footprints.png` | Same as F3 but too dense | Do not force unreadable panel into final |
| **F11** | **OMIT** | Four univariate histograms | A1 `fig-univariate-environment` | Feature distributions | Retain 1–2 lines on skew/outliers; not highest-value use of page space |
| **F12** | **OMIT** | Environmental distance/composition chart | A1 `fig-environment-composition` | Environmental association after geographic matching | Summarise descriptively in prose if space; not central to post-model results, no causal language |
| **F13** | **OMIT** | Exploratory correction-strength curves | `prior_correction_metric_curves.jpeg` | Post-hoc assessment sensitivity | Distinguish from properly nested tuning; avoid redundant/ambiguous plot |
| **F14** | **OMIT** | Five-model × 18-species heatmap | A2 `report_v1_species_equity_heatmap.png` | Species-by-family comparisons | Replace with F7 for actual decision question and legibility |
| **F15** | **OMIT** | Individual recall-shift bars | `prior_correction_species_recall.jpeg` | Effect of correction per species | Explain mixed gains/losses textually; reserve for appendix only if allowed |

**Figure budget:** 5 unchanged core assets (F1/F2/F4/F5/F6) plus F7 all-18 comparison and F3 four-species geography if print-legible: **target 7 core figures**. F8 (seasonality) and F9 (correction sensitivity) are optional, chosen only after a first real Quarto HTML-to-PDF pagination test. The figure register is final: no additional figures are necessary to justify the investigation. Figure numbering and captions will be generated automatically at render time.

## D. Table register — deliberate, compact

| ID | Where | Contents | Source |
|---|---|---|---|
| **T1** | §2 | Four dataset characteristics, evidence and importance | A1 v4 `# Consider & Gather Data` |
| **T2** | §3 | One-line cohort/QC flow with correctly distinguished filtering/branching | `qc_filter_flow.csv`, `docs/data-pipeline.md` |
| **T3** | §4 | 2–3 strongest BIO correlations and modelling implications; seasonality/spatial metrics in narrative | `eda05_environmental_correlation_pairs.csv` |
| **T4** | §5 | M0–M4 blocks, predictor counts and role | `R/modelling/modelling_helpers.R` |
| **T5** | §6 | Five model families + **actual** grid + example selected outcome in concise rows | `model_*_selected.csv`, actual scripts |
| **T6** | §7 | M4 spatial leaderboard: Macro-F1, accuracy, Top-3 | `report_m4_spatial_leaderboard.csv` |
| **T7** | §7 | RF/XGB rare-six mean F1, recall, Top-3 and qualification | `report_species_equity_scorecard.csv` |

All seven are **content slots**, not seven full-size tables. Where adjacent numbers fit in two sentences or a graphic already conveys them, use prose instead. No large grids of all fold/candidate results in the printed ten-page report; those remain in folded R code / linked saved outputs.

## E. Rubric-to-evidence coverage

| 3-mark criterion | Primary sections and evidence | Compliance test |
|---|---|---|
| Problem & motivation | §1; A1 high-scoring framing | Explicit task, question, stakeholders and use case |
| Dataset justification | §2 T1 | At least three requirement classes with *quantified* evidence (four supplied) |
| EDA | §4 F1/F2/F3/T3 | Univariate + pairwise relationships + nontrivial insights leading to hypotheses |
| Data preprocessing | §3 T2 + §5 T4 | Actual QC, missingness, feature transformations, leakage control, *why* |
| Model fitting | §6 T5; executable script refs | Explain five actual models, inputs and shared protocol |
| Model improvement | §5 T4, §6 T5, §7 F6 | Chosen grids, actual per-fold selections, meaningful feature refinement |
| Model evaluation & selection | §7 F5/F7/T6/T7 | Prespecified XGB winner versus post-hoc RF preference explicit |
| Final results & conclusion | §§7–9 | Direct research answer, limits, stakeholders |
| Writing/visualisation | Entire report | Print-legible figures, consistent cohorts, coherent story |
| Technical/academic | §10 plus folded genuine R chunks | A4 <=10 pages, inspectable code, APA7, accurate AI-use, safe reproducibility claims |

## F. Confirmed evidence gaps and risk controls

1. **Class-imbalance standalone reproduction:** The README and figures are committed; original executable source and all intermediate output are not yet archived. Do not claim full independent rerun. F9 conditional.
2. **Multi-species/temporal extension:** A1 proposed these. No completed A2 evidence shown; do not count as experiments.
3. **Geographic validation independence:** 0.5° cells prevent exact same-cell leakage but not dependence across borders; do not claim fully spatial-independent test or continent-wide out-of-distribution performance.
4. **Small near-tie:** XGB > RF by .00281 average spatial Macro-F1 (two of three outer folds). No valid significance conclusion from three folds.
5. **Post-hoc RF preference:** Rare-six per-class audit was performed after leaderboard inspection; not an unbiased preregistered tie-break. State this openly; don't claim all rare species improved or RF wins all rare-class recall metrics.
6. **Class imbalance data:** Never equate fewer *recorded* events with genuinely ecologically rare or officially threatened species.
7. **Cohort denominator:** A1 summary 247,406 and A2 model 242,600 have different shares. Label cohorts in every graphic/table.
8. **APA/AI/DIP:** The pasted Week 12 guide references a DIP diagram not supplied in this chat. Current A1 and A2 documents give an adequate process narrative, but incorporate course-specific stage names only if diagram is available. AI disclosure needs verification of exact actual tools/versions and contributions; do not invent them.
9. **Full reproduction:** Report can render from frozen aggregate CSVs/PNGs without refitting; recreating the whole pipeline requires access to verified raw datasets and local package dependencies. Document both levels transparently.

## G. Build constraints (for drafting stage, not action taken now)

- Draft in a **new** file in `FrogID-A2-Integration/reports/FinalReport/`, keeping A1 v4 and existing `reports/STAT5003_A2_Report.qmd` unchanged.
- Resolve project root robustly for source being in nested `reports/FinalReport/`; naive `normalizePath('..')` will point at `/reports`, **not** the repo root. Use an explicit/project-root-detecting path helper and test it.
- Preserve official template expectations: embedded standalone HTML, folded code, bibliography, AI statement, figure captions/alt text and output reproducibility.
- Use genuine, folded R code that loads committed CSVs, computes tables or creates at least some of the figures; **do not** rely entirely on nonexecuting pseudocode, and do not trigger costly model refitting as part of HTML rendering.
- Test with the **exact Quarto/browser PDF conversion** method chosen for submission. Page count includes references and AI statement; do not solve overflow by making plots unreadable. If over 10 pages, first remove F8/F9 and tighten duplicate method prose before compressing font size.
- Do not overwrite or commit anything until the reviewed `.qmd`, HTML, exact figure evidence and print count are approved.

**Decision:** Evidence/figure selection is complete. The only pending items before authoring are (a) selecting which reserve visual(s) fit after render, (b) user-confirmed AI-use details if the final declaration requires them, and (c) sourcing the course-specific DIP diagram if the group wants an exact stage-by-stage mirror. No new model training or unrelated folder clean-up is required.
