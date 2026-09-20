# EDA-02 findings — target class structure and imbalance

Work package: EDA-02 (`docs/eda-plan.md`).

Script: `analysis/02_class_structure.R`.

Input: `data/processed/frog_primary_multiclass.rds` (read-only).

Outputs:
- `outputs/tables/eda02_class_distribution.csv`
- `outputs/tables/eda02_imbalance_summary.csv`
- `outputs/figures/EDA02/eda02_class_distribution.png`

## Question

How balanced is the 18-class classification target, and what does that imply
for later evaluation?

## Findings

The primary cohort contains **247,406 recording events across 18 species**.

Class frequencies are substantially imbalanced:

- *Crinia signifera*: 87,536 events (**35.38%**)
- *Limnodynastes peronii*: 45,042 (**18.21%**)
- smallest class, *Litoria infrafrenata*: 2,154 (**0.87%**)
- largest-to-smallest ratio: **40.64:1**
- three most common species: **60.65%** of all events
- five most common species: **71.78%** of all events

Shannon entropy is **3.214 bits**, compared with a maximum of **4.170 bits**
for 18 equally common classes. The corresponding effective number of equally
common classes is **9.28**, despite 18 classes being present.

## Statistical interpretation

The response is therefore genuinely multiclass but strongly concentrated in a
small number of common species.

This matters because aggregate metrics can be dominated by common classes.
For example, the five most frequent species already account for 71.78% of the
observations. Consequently, a high later Top-5 or overall accuracy value would
not by itself demonstrate good performance on uncommon species.

The imbalance is descriptive evidence only. No balancing, weighting or
resampling decision is made in EDA-02.

## Implications for the project plan

The later evaluation plan should include metrics that give uncommon classes
visibility, particularly **Macro-F1 and per-class recall**, alongside overall
accuracy and ranking metrics.

Future train/validation splitting should preserve class representation where
possible. Whether class weighting or resampling is needed should be decided
during modelling rather than applied automatically from the class counts alone.

## Report-use recommendation

For the six-page report, the numerical summary is likely sufficient:

> The 18-class target is strongly imbalanced: the largest species contributes
> 35.4% of the 247,406 observations, the largest-to-smallest ratio is 40.6:1,
> and the five most frequent species account for 71.8%.

The class-distribution figure should only be included if space permits or if a
visual is needed to make the imbalance easier to communicate.

## Constraints respected

- No classifier was fitted.
- No observations were removed.
- No class balancing, weighting or resampling was applied.
- The processed dataset was read only.