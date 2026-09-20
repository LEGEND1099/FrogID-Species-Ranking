# EDA-08 findings — conservation and geoprivacy

Work package: EDA-08 (`docs/eda-plan.md`).

Script: `analysis/08_conservation_geoprivacy.R`.

Inputs:
- `outputs/tables/conservation_species_retention.csv`
- `outputs/tables/conservation_category_retention.csv`
- `outputs/tables/conservation_group_retention.csv`
- `outputs/tables/conservation_qc_exclusion_summary.csv`

All inputs and outputs used for this EDA are aggregate and non-sensitive. No
exact locations, event identifiers or observer identifiers are analysed or
reported.

## Question

What does the public FrogID release permit and prevent for spatial-context
modelling of confirmed EPBC-listed taxa, and how do the project's spatial QC
requirements interact with public geoprivacy protections?

## 1. Confirmed EPBC-listed taxa are present in the raw FrogID release but do
not survive the project's strict public spatial QC

The retention table contains 216 FrogID taxa, of which 24 are confirmed
EPBC-listed taxa.

Those 24 confirmed listed taxa occur across 6,749 distinct raw FrogID
recording events.

After the project's whole-event spatial QC:

- confirmed EPBC-listed events retained: 0 / 6,749 (0%);
- other or unresolved events retained: 519,414 / 540,647 (96.07%).

The confirmed listed scope also contains 1,627 raw single-species events, but
none survives the same spatial QC.

Therefore the absence of confirmed listed taxa from the modelling cohort is
not because they are absent from FrogID. They are present in the raw public
release but their publicly available spatial information does not meet the
project's strict spatial eligibility rules.

## 2. All confirmed listed events share the same three key spatial/privacy
conditions

The non-exclusive QC diagnostics show that all 6,749 confirmed listed events
have:

- coordinate uncertainty greater than 1 km;
- obscured geoprivacy; and
- generalised location information.

Each condition therefore affects 100% of confirmed listed recording events.

Because every confirmed listed event satisfies each of the three conditions,
all 6,749 events lie in their three-way overlap.

These counts are non-exclusive and must not be added together.

The result should not be interpreted as geoprivacy being a data-quality error.
Rather, the public location information for confirmed listed taxa is
systematically less spatially precise, consistent with protective handling of
sensitive records.

## 3. Sequential QC removes the listed events at the uncertainty stage because
that check occurs first

The project's sequential QC order is:

1. complete species;
2. valid coordinates;
3. positive coordinate uncertainty no greater than 1 km;
4. open geoprivacy;
5. no data generalisation;
6. valid event date.

All 6,749 confirmed listed events pass the species and coordinate-validity
stages.

All 6,749 are then excluded at the coordinate-uncertainty stage, leaving zero
events for the later geoprivacy and generalisation stages.

The later sequential stages therefore report zero additional exclusions.

This does not mean obscured geoprivacy or generalisation are absent. The
non-exclusive diagnostics independently show that all 6,749 events also have
those conditions.

Sequential exclusion counts are therefore order-dependent and should not be
interpreted as causal attribution of the exclusion to a single privacy field.

## 4. Confirmed listed FrogID recordings occur in both Endangered and
Vulnerable categories

The 24 confirmed listed taxa comprise:

- 12 Endangered taxa;
- 12 Vulnerable taxa.

The raw FrogID release contains:

- 3,212 distinct recording events containing an Endangered confirmed-listed
  taxon;
- 3,545 distinct recording events containing a Vulnerable confirmed-listed
  taxon.

These category totals are distinct event unions within each category and are
not mutually exclusive.

Eight recordings contain taxa represented in both category scopes. Therefore
the two category totals sum to 6,757 while their union contains 6,749 distinct
confirmed-listed recording events.

No confirmed-listed event from either category survives the project's strict
public spatial QC.

## 5. Conservation-group event scopes can overlap in multi-species recordings

The confirmed-listed scope contains 6,749 raw events, while the other or
unresolved scope contains 540,647.

These groups are not mutually exclusive because one multi-species recording
can contain taxa from both scopes.

There are 5,109 raw recording events belonging to both conservation scopes.

Consequently, conservation-group event totals should not be summed to estimate
the total number of FrogID recordings.

## 6. The selected 18-species modelling cohort contains no confirmed
species-level EPBC-listed taxa

None of the 18 selected modelling species is a confirmed species-level
EPBC-listed taxon.

One selected target, `Litoria verreauxii`, has the status
`unresolved_listed_subspecies_only`.

This must not be interpreted as the species `Litoria verreauxii` itself being
confirmed EPBC-listed. The official conservation match applies only at a
subspecies level that cannot be resolved from the public species-level FrogID
label.

The unresolved case is therefore kept separate from the 24 confirmed
species-level listed taxa.

## Statistical interpretation

The conservation result is primarily an applicability constraint rather than
a predictive-performance result.

The public FrogID release contains substantial recording evidence for
confirmed EPBC-listed taxa, but the public spatial representation of those
records is systematically obscured, generalised and associated with
coordinate uncertainty greater than the project's 1 km eligibility threshold.

As a result, the public-coordinate modelling framework developed for the
selected common species cannot be directly trained or evaluated on confirmed
EPBC-listed taxa under the same spatial-QC rules.

This EDA does not establish how well a model would perform for threatened
species if finer protected coordinates were available.

## Conservation applicability decision

The final project should distinguish between:

- predictive performance for the public, spatially eligible common-species
  cohort; and
- conservation applicability to confirmed listed taxa.

The latter is constrained by public geoprivacy and spatial precision, not by
demonstrated model failure.

The report should therefore state that:

> Public geoprivacy appropriately limits spatial precision for sensitive
> records, but the same protection prevents direct evaluation of the proposed
> spatial-context ranking framework for confirmed EPBC-listed taxa using the
> public FrogID release.

No attempt should be made to reconstruct, infer or approximate protected
locations.

## Report-use recommendation

The strongest report visual is the confirmed-listed QC/privacy-condition
figure because it directly demonstrates that all confirmed listed events are
affected by the three spatial/privacy conditions.

The raw-to-clean retention figure provides a compact comparison between
confirmed listed and other/unresolved records.

The Endangered/Vulnerable recording-count figure provides useful descriptive
context but can be omitted if the six-page report requires space.

## Constraints respected

- No exact sensitive locations were read or written.
- No event identifiers or observer identifiers were published.
- No classifier was fitted.
- No threatened-species predictive performance was estimated.
- Geoprivacy was treated as a protective constraint rather than an error.
- Confirmed species-level EPBC status was kept separate from unresolved
  subspecies-level status.
- Non-exclusive QC reasons were not added together.
- Sequential QC results were interpreted according to their stage order.