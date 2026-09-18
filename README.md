# FrogID Species Ranking

STAT5003 Computational Statistics project investigating whether environmental,
seasonal and geographic context can be used to rank Australian frog species
likely to be detected in FrogID recordings.

## Research question

**Can environmental, seasonal and geographic characteristics be used to rank
the Australian frog species most likely to be detected in a FrogID recording,
and how effectively can these rankings surface threatened species among the
top candidate predictions?**

## Planned data sources

- Australian Museum FrogID occurrence data
- WorldClim 2.1 climate and elevation data
- Australian EPBC threatened-species information
- IBRA bioregions where useful

## Planned analysis

The primary task is multiclass frog-species prediction with Top-1, Top-3 and
Top-5 evaluation.

Single-species FrogID recording events will form the primary multiclass
dataset. Recordings containing multiple detected species will be retained as
a separate Top-k recommendation extension.

The project will compare environmental-only and geography-enhanced models and
will separately evaluate performance for threatened species represented in
the public FrogID data.

## Repository structure

- R/ - acquisition, cleaning, integration, feature engineering and modelling
- nalysis/ - data audit, EDA and modelling notebooks
- data/raw/ - original source data; not committed
- data/interim/ - cleaned/intermediate datasets; not committed
- data/processed/ - final modelling datasets; not committed
- outputs/ - figures and summary tables
- docs/ - methodology and data documentation
- eport/ - final report material
- 	ests/ - validation checks
