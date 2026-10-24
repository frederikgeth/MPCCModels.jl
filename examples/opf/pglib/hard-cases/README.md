# Curated hard-case records

`ieee118-capability-082.toml` is a compact, portable receipt from the first
capability search, not a requirement that future CCOpt releases keep failing.
It preserves the original numerical inputs to the starts/solver, returned
points, diagnostics, effective options and an independently checked feasible
witness. Float64 point/start bit hashes detect accidental changes to arrays.

The network is PGLib-OPF v23.07 IEEE 118 at the recorded revision and source-file
hash. Only `ibr3`'s S limit changes to 0.82 of nominal; its availability and
control curves stay fixed. Rebuild it with `HardCaseSearch.capability_case(0.82)`.
The receipt records the complete-input snapshot hash and source/environment
fingerprint from the full local search. Full snapshots and all trials remain
under the ignored `search-results/` directory; this receipt keeps representative
outcomes without duplicating the entire upstream network in Git.

The four raw rows are current/flat (iteration limit), defaults/flat (solved
status with an original-curve accuracy gap), current/neighbor (recovery), and
current/witness (recovery). The witness is a separate exact-sector NLP point;
it does not replace any of these raw results. No global optimality or full MPCC
stationarity is asserted. Tests re-evaluate the archived points rather than
requiring new solves to reproduce historical failure statuses.

From the repository root in the optional PGLib environment:

```julia
using TOML
include("examples/opf/pglib/hard-search.jl")
using .HardCaseSearch
receipt = TOML.parsefile("examples/opf/pglib/hard-cases/ieee118-capability-082.toml")
trial = receipt["trials"][1]
run_trial(capability_case(receipt["factor"]), trial["start"], trial["profile"],
    "NEW_REPLAY_DIRECTORY"; start_label = trial["start_label"],
    provenance = Dict("curated_source" => receipt["environment"]))
```

PGLib network data retain their original attribution and **CC BY 4.0** license;
see [source attribution](../data/README.md) and [upstream license](../data/LICENSE).
The normalized records and modified case are derived study instances, not new
official PGLib benchmark releases.

`ieee118-capability-sweep.tsv` retains the complete 160-row first-search table,
including failures and accuracy gaps. The full request/result/point/log/source
archive is preserved locally as
`../search-results/ieee118-capability-2026-10-24.tar.gz`; it is excluded from Git
along with the expanded output. The compact receipt above provides the committed
point-level reproduction, while the TSV records the whole experiment matrix.

## Ratio-one transition/Q-limit receipt

`ieee118-transitions-q45.toml` preserves numerical witnesses for all nine
transition/Q-limit inputs and the six raw central-case trials (zero VW offset,
Q upper limit 0.35 pu). It also retains the two neighboring Q-sensitivity
witnesses, solver profiles/options, actual starts/points, bit hashes, original
physical checks and achieved activity. Reconstruct each input with
`transition_case(; knee=record["knee"], offset=record["offset"], qmax=record["qmax"])`.
The complete 54-row census is `ieee118-transitions-sweep.tsv`.

```julia
receipt = TOML.parsefile("examples/opf/pglib/hard-cases/ieee118-transitions-q45.toml")
trial = only(filter(t -> t["start_label"] == "flat", receipt["trials"]))
data = transition_case(; knee=trial["knee"], offset=trial["offset"], qmax=trial["qmax"])
run_trial(data, trial["start"], trial["profile"], "NEW_TRANSITION_REPLAY_DIRECTORY";
    start_label=trial["start_label"], provenance=Dict("curated_source" => receipt["environment"]))
```

All three devices share bus 95 and normalized profiles. Zero offset aligns the
VV deadband/absorption knee with VW onset; nonzero offsets separate the knees.
Generator 45 at bus 100 has the only changed network bound. The setup uses its
original Q limit and is retained separately. Independent selected-sector
witnesses establish numerical feasibility and achieved activity, without
certifying full MPCC stationarity. CI rechecks archived arrays; it does not
require a future solver to reproduce historical iteration limits.

Complete inputs, logs, all raw attempts, source/environment snapshots, a raw
replay and Q sensitivities are retained locally under
`../search-results/ieee118-transitions-2026-10-24/` and its sibling `.tar.gz`.
These research artifacts are excluded from Git; the receipt and TSV above are
portable committed records.

## Controlled reduction records

`ieee118-reductions.toml` preserves all 12 constructed feasible witnesses, ten
representative raw points and the separate 2,000-iteration reference. Rebuild
inputs using `reduction_case(; encoding=Symbol(row["encoding"]),
controlled=row["controlled"], plateau=Symbol(row["plateau"]))`. The witnesses
are transfers of the archived central physical point, independently checked
against each target input; they are explicitly labelled as constructions with
no new solver invocation or optimum claim.

The records include the smallest observed iteration-limit example: one
controller and five shared hinges, with a crossover inside the VW ramp, failing
from flat. Its separate-hinge counterpart passes from the identical physical
start. Other records retain the reverse contrast, where sharing resolves a
solved-status accuracy gap, and the original three-controller failure followed
by a larger-budget solved status that still violates the direct VV law.

```julia
receipt = TOML.parsefile("examples/opf/pglib/hard-cases/ieee118-reductions.toml")
trial = only(filter(t -> t["encoding"] == "shared" && t["controlled"] == 1 &&
    t["plateau"] == "crossing" && t["start_label"] == "flat", receipt["trials"]))
data = reduction_case(; encoding=Symbol(trial["encoding"]),
    controlled=trial["controlled"], plateau=Symbol(trial["plateau"]))
run_trial(data, trial["start"], trial["profile"], "NEW_REDUCTION_REPLAY_DIRECTORY";
    start_label=trial["start_label"], trace_every=trial["trace_every"])
```

`ieee118-reductions-sweep.tsv` holds all 60 raw outcomes and physical residuals.
`ieee118-reductions-traces.tsv` holds representative iteration series for the
separate/shared one-controller equal/crossing contrasts and the larger-budget
reference. Original complete logs, inputs, starts, points, witnesses, source and
environment snapshots remain in the two local ignored directories
`../search-results/ieee118-reductions-2026-10-25/` and
`../search-results/ieee118-reduction-seeds-2026-10-25/`, with sibling `.tar.gz`
archives. Source PGLib attribution and license remain unchanged.

## Application catalog records

`ieee118-applications.toml` preserves nine physically verified application
reference points, nine matched dispatchable NLP points, eight representative raw
trials and six paired local physical-parameter comparisons. Inputs rebuild with
`TransmissionOPF.application_case(Symbol(row["family"]);
level=Symbol(row["level"]))`; sensitivity rows additionally supply their recorded
physical overrides. Every point has a Float64 bit hash and original residuals.
Source/input/request/environment hashes and actual starts/solver settings are
retained. Tests evaluate the archived numerical evidence without requiring
future CCOpt versions to reproduce failures.

These are application inputs with a spread of difficulty, not reductions of one
solver pathology. The nominal/elevated/severe labels describe physical parameters.
The elevated/severe reactive-support inputs fail both tested profiles from both
starts despite verified witnesses; renewable-surplus inputs pass throughout.

```julia
receipt = TOML.parsefile("examples/opf/pglib/hard-cases/ieee118-applications.toml")
trial = only(filter(t -> t["family"] == "reactive_support" &&
    t["level"] == "severe" && t["profile"]["name"] == "ratio_one", receipt["trials"]))
data = HardCaseSearch.TransmissionOPF.application_case(:reactive_support; level=:severe)
run_trial(data, trial["start"], trial["profile"], "NEW_APPLICATION_REPLAY_DIRECTORY";
    start_label=trial["start_label"])
```

`ieee118-application-catalog.tsv` records the nine measured reference operating
points. `ieee118-applications-sweep.tsv` retains every raw combined-policy trial,
including failures. Complete artifacts and sibling `.tar.gz` archives remain in
local ignored `../search-results/ieee118-applications-2026-10-25/` and
`../search-results/ieee118-application-sensitivities-2026-10-25/`.
The [application guide](../APPLICATIONS.md) defines scope, parameters, intended
versus observed effects, paired comparisons and remaining coverage gaps. Original
PGLib attribution and license remain unchanged.
