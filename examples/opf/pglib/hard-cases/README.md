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
