# Application-driven balanced OPF families

These families study steady-state economic dispatch with voltage-responsive
aggregate inverter plants in the pinned PGLib IEEE 118 transmission network.
Local VV/VW functions have an established PV voltage-regulation application;
see the [NREL/Hawaiian Electric simulation and field pilot report](https://research-hub.nlr.gov/en/publications/advanced-inverter-voltage-controls-simulation-and-field-pilot-fin/).
The inputs here are synthetic balanced transmission proxies: neither calibrated
feeders nor prescribed grid-code settings. They do not represent dynamic
stability, inverter priority logic, regulator switching or time-series energy
production. Conventional generation retains PGLib costs and P boxes.

## Physical case definitions

`application_case(family; level=:nominal, laws=:both, parameters=(;),
hinge_encoding=:separate)` creates an ordinary ADNLPModel-compatible data record.
`TransmissionOPFModel(data)` returns the existing ADNLPModel or MPCCModel.
`application_card(family)` describes the motivation, sites, rating template,
intended interactions and applicable knobs. `application_cases()` lists the
initial nine operating points, separately from the original 22 solved cases.

The system base is 100 MVA. Plant ratings below are system-base pu before the
penetration multiplier. Availability means `P_available/S`; all plant Q boxes
are ±0.5S. Plant active production costs are zero; conventional costs supply the
economic dispatch objective. Curtailment is availability minus dispatched P.

| Family | Physical interpretation | Sites (original bus IDs) | Rating template |
| --- | --- | --- | --- |
| `renewable_surplus` | Increasing renewable output with lighter demand and reduced inverter reactive headroom | 20,45,53,70,95,110 | 1.6,2.0,2.4,1.8,2.2,2.0 |
| `reactive_support` | Available conventional Q operating ranges shrink while load and inverter active availability increase | 44,45,46,94,95,96 | 1.6,2.0,2.4,1.8,2.2,2.0 |
| `export_corridor` | Three plants export from buses 20–22 through the two boundary circuits | 20,21,22 | 2.4,2.2,2.4 |

Sites are explicit study placements, not sensitivity-ranked or utility-calibrated
locations. Nominal/elevated/severe describe physical operating parameters, not
predictions of solver performance. Several parameters change together in these
named scenarios; use individual overrides for isolated sensitivities.

| Family | Level | Load P/Q factor | Plant S multiplier | P availability/S | Conventional Q factor | Corridor rating factor |
| --- | --- | --- | --- | --- | --- | --- |
| renewable surplus | nominal | 1.00 | .35 | .75 | 1 | 1 |
| renewable surplus | elevated | .85 | .65 | .90 | 1 | 1 |
| renewable surplus | severe | .65 | 1.00 | 1.00 | 1 | 1 |
| reactive support | nominal | 1.00 | .50 | .60 | 1 | 1 |
| reactive support | elevated | 1.05 | .75 | .85 | .5 | 1 |
| reactive support | severe | 1.10 | 1.00 | .95 | .2 | 1 |
| export corridor | nominal | 1.00 | .35 | .75 | 1 | 1 |
| export corridor | elevated | .95 | .70 | .90 | 1 | 1 |
| export corridor | severe | .90 | 1.00 | .98 | 1 | .7 |

Q factors multiply both original conventional Q bounds toward zero. All
conventional P bounds/costs, topology, taps, charging, shunts, bus bounds and
angle limits remain unchanged. The corridor is the exact cutset of buses
20,21,22: original branches **25** (19–20) and **29** (22–23), each originally
1.78 pu. Only those two ratings are scaled in the export family. All other
original thermal limits remain present in every family, so other constraints
may also bind. Files are unchanged; complete overlays/parameters are saved.

Each plant has a distinct profile shift from
`[-.006,+.006,0,-.003,+.003,-.004]` in site order (first three for export).
VV has Q/S `[.4,0,0,-.4]` at voltage knots `[.95,.99,1.01,1.05]` for renewable/
export, and `[.95,1.025,1.04,1.053]` for reactive support. VW has P/S `[1,.2]`
at `[1.022,1.052]`. Shifts apply to both curves. All default knots lie inside
original bus voltage bounds. A `profile_shift` override must keep them there.
VV is an equality and VW an upper bound; S circles and hardware boxes are
independent constraints. These curves do not implement a separate priority or
clipping policy. The reactive-support profiles represent a higher voltage
support setpoint than the other two families.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF

surplus = application_case(:renewable_surplus; level=:severe)
reactive = application_case(:reactive_support; level=:elevated,
    parameters=(q_support=.35,))
export_case = application_case(:export_corridor; level=:severe)
relaxed_export = application_case(:export_corridor; level=:severe,
    parameters=(export_rating=.8,))
dispatchable = application_case(:export_corridor; level=:severe, laws=:dispatchable)
```

The four matched policies `:dispatchable/:vv/:vw/:both` share the exact hardware,
availability, costs and network data. Only enabled laws differ. Knobs listed in
each card can be overridden independently. Population/placement builders remain
available for further studies; the initial catalog uses distinct sites and
heterogeneous profiles rather than a redundant same-bus fleet.

## Validation and characterization protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-applications.jl
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --out=examples/opf/pglib/search-results/ieee118-applications-2026-10-25
# Resume with the identical arguments plus --resume; or rebuild reports:
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --summarize=examples/opf/pglib/search-results/ieee118-applications-2026-10-25
```

The default records **36 raw both-law trials** (nine inputs × flat/witness ×
current/ratio_one), plus **nine matched dispatchable NLP counterfactuals**.
Budgets are 500 iterations and 60 seconds, inner tolerance `1e-9`, with original
physical acceptance at `1e-5` and strict witness verification at `1e-7`.
A one-iteration warmup per profile is retained separately. Optional explicit seeds
add perturbed witness starts; trace recording is available but off by default.
Flat results are saved before witness construction and never replaced.

A witness is an original-feasible raw point or a separately labelled exact-sector
solve selected by observed hinge signs from an actual returned iterate. When
necessary, a previously verified operating point in the same application family
provides a separately recorded neighboring start/sector. No desired regime or
bound target chooses a sector. A failed witness search remains unresolved
feasibility. These numerical witnesses do not establish full MPCC stationarity
or a global optimum. Witness-start raw trials remain independent recorded runs.

`application_coverage(data,x)` reports measured curve regions/fractions and
knot distances, P availability/injection/curtailment in MW, Q signs, VW/capability
activity, conventional P/Q limits, voltage bounds, both thermal ends and angles.
Fixed conventional boxes are excluded from activity counts. Intended effects
are card metadata, not constructor assertions. Use physical checks before
accepting a point's coverage. Curtailment with slack device caps is only a
candidate network/control interaction; a binding margin alone does not assign
causality or establish an economic sensitivity.

`summary.toml` separates per-input witness coverage, counterfactual results and
all raw outcomes. `summary.tsv` retains status, original residuals and curtailment
for every attempt, with superseded attempts labelled. Input snapshots, starts,
points, solver options, provenance and source/environment hashes follow the
[hard-search recorder](HARD_SEARCH.md). Constructor, matched-input, sparse
Jacobian/Hessian, snapshot and failure-retention tests run independently of
whether CCOpt happens to find a hard input on a future release.
