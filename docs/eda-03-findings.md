# EDA-03 findings — temporal and seasonal structure

Work package: EDA-03 (`docs/eda-plan.md`).

Script: `analysis/03_temporal_eda.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

Outputs:
- `outputs/tables/eda03_month_distribution.csv`
- `outputs/tables/eda03_year_distribution.csv`
- `outputs/tables/eda03_species_month_distribution.csv`
- `outputs/tables/eda03_species_season_summary.csv`
- `outputs/tables/eda03_year_class_tvd.csv`
- `outputs/tables/eda03_temporal_summary.csv`
- `outputs/figures/EDA03/eda03_species_month_heatmap.png`
- `outputs/figures/EDA03/eda03_relative_month_profile.png`
- `outputs/figures/EDA03/eda03_year_month_overview.png`

## Question

How does the timing of FrogID recordings vary through the year, and does the
observed species composition also vary with season?

## 1. Temporal coverage and recording pattern

The primary cohort covers **10 November 2017 to 9 November 2023** and contains
records on all **2,191 calendar days** in that interval.

The first and final calendar years are incomplete:

- 2017 begins on 10 November;
- 2023 ends on 9 November.

They should therefore not be interpreted as complete annual samples.

Recording volume is strongly uneven across months. November contains **47,515
events (19.21%)**, whereas April and May each contain about 4.4%.

This is a pattern in FrogID recordings and should not be interpreted directly
as frog abundance or population seasonality because recording activity itself
also changes over time.

## 2. Species composition varies with month

The species-by-month contingency table gives:

- chi-square = **106,028.8**
- df = **187**
- Cramér's V = **0.197**

With more than 247,000 observations, statistical significance alone is not
especially informative. Cramér's V is the more useful result: it indicates a
meaningful, but not overwhelming, association between calendar month and the
species recorded.

Individual species show substantially different seasonal concentration.

Examples include:

- *Crinia georgiana*: July peak, 33.7% of its records in that month,
  circular concentration R = **0.808**
- *Litoria moorei*: November peak, R = **0.783**
- *Litoria peronii*: November peak, R = **0.769**
- *Litoria ewingii*: June peak, R = **0.323**
- *Litoria verreauxii*: April peak, R = **0.287**
- *Crinia glauerti*: comparatively diffuse seasonal profile, R = **0.161**

Thus, season contains species-related structure, but that structure differs
considerably among classes.

## 3. Relative monthly recording profiles

The relative-month heatmap compares each species' monthly distribution with
the aggregate monthly distribution of all selected-species recordings.

This reduces the visual dominance of months with unusually high overall
recording volume, but it is **not a complete correction for observation
effort**. Differences may still reflect geography, recorder behaviour,
detectability and other sampling effects.

It should therefore be interpreted as a relative recording profile rather
than pure biological phenology.

## 4. Year-to-year class composition

For complete years, total-variation distance from the overall species
distribution is:

| Year | TVD |
| ---: | ---: |
| 2018 | 0.107 |
| 2019 | 0.113 |
| 2020 | 0.039 |
| 2021 | 0.038 |
| 2022 | 0.052 |

This shows some year-to-year change in observed species composition, especially
in 2018-2019. The much larger 2017 value (0.349) should not be compared directly
because 2017 contains only the final part of the year. The 2023 value is also
based on a partial year.

## Implications for the project plan

The data support retaining seasonal information in the future candidate
predictor set: species composition varies with month and individual species
show different seasonal recording patterns.

The existing cyclic month/day-of-year encodings are appropriate for later
models because the calendar is circular: December and January should be close,
not opposite ends of a linear scale.

Year should remain an EDA/robustness variable rather than a primary predictor.
The observed year-to-year composition changes provide a reason to check later
whether conclusions are stable across time, but EDA-03 does not fit or compare
models.

All temporal results must be described as patterns in **detections conditional
on FrogID recording activity**, not as estimates of species abundance.

## Report-use recommendation

A concise numerical statement can cover the overall recording pattern and
species-month association.

If one temporal figure is included in the final report, the
**species-by-month heatmap** or the **relative monthly recording-profile
heatmap** is more informative than a simple month-count plot because it directly
links a feature to the classification outcome.

## Constraints respected

- No classifier was fitted.
- No model performance was calculated.
- No observations were removed.
- No temporal variable was selected on the basis of predictive performance.
- The processed dataset was read only.