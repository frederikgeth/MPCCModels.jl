# IEEE 300 application families

The optional transmission example now imports the unmodified IEEE 300 case from
[PGLib v23.07 at the pinned revision](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/pglib_opf_case300_ieee.m).
Its SHA-256 is recorded in `data/SHA256SUMS`; the imported Git blob matches upstream
`92d03963ed36dd4072915b1cdfabf5a7273b02cc`. Source attribution and CC BY 4.0 licensing
are retained. These application overlays are synthetic studies, not official
PGLib instances or prescribed inverter/grid-code settings.

## Canonical AC OPF

The source contains 300 buses, 411 branches and 69 generators, with 23,525.85 MW
and 7,787.97 Mvar aggregate demand on a 100-MVA base. Bus IDs are nonconsecutive,
including transformer-side and low-voltage IDs up to 9533. All source IDs map
explicitly to model positions. Taps, phase shifts, shunts, line charging, both
branch-end thermal limits, angle bounds, voltage bounds and conventional P/Q
boxes/costs are retained. Only the reference angle is fixed.

The canonical model is an ordinary ADNLPModel with 738 variables and 1,833
constraints. Independent PowerModels/Ipopt and our MadNLP solve agree at an
objective of approximately **565,219.990890** (local solutions, no global
certificate). The PowerModels point is also evaluated in our formulation and
by independent complex-current balance. Run:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/validate-baselines.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-ieee300.jl
```

## Physical study matrix

The [application parameter table](APPLICATIONS.md#physical-case-definitions)
applies on both IEEE 118 and IEEE 300: three application families, each at
nominal/elevated/severe operating levels. Network-specific connection points
and rating templates distinguish IEEE 300. These are explicit topology/load
placements, not sensitivity rankings. The six-plant full rating is 6,600 MVA,
roughly 28% of original demand in MW; the three-plant export template is
3,800 MVA. Installed size is subsequently multiplied by each level's penetration.
No assumption of equal achievable output or comparable difficulty across grids
follows from these rating choices.

| Family | Original connection bus IDs | Rating template, system-base pu | Placement rationale |
| --- | --- | --- | --- |
| `renewable_surplus` | 5,59,125,170,200,243 | 9,11,13,10,12,11 | Distributed load-area connections across the transmission network |
| `reactive_support` | 118,120,121,140,171,178 | 9,11,13,10,12,11 | Reactive-demand buses, including bus 118's 650-Mvar load and a 118/120/121 support cluster |
| `export_corridor` | 25,26,27 | 13,12,13 | Connected pocket 25/26/27/320, including bus 320's radial attachment; only its two boundary ratings scale |

VV is a continuous piecewise linear Q equality; VW is an active-power cap.
Independent hardware circles/boxes remain present. Heterogeneous voltage shifts
and normalized profiles match the original family definitions. All control knots
lie in the original connection-bus voltage bands. Conventional Q reductions scale
both original Q bounds toward zero. Curtailment is available minus dispatched P.
No inverter priority/clipping policy or dynamic behavior is modeled.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF
card = application_card(:export_corridor; network=:ieee300)
data = application_case(:export_corridor; network=:ieee300, level=:severe)
model = TransmissionOPFModel(data)
# The same physical inputs support matched policies:
vw_only = application_case(:export_corridor; network=:ieee300,
                           level=:severe, laws=:vw)
```

The constructor defaults to IEEE 118. Its nine inputs and all archived IEEE 118
snapshot hashes remain unchanged, as does the original 22-case solved registry.
`application_cases(network=:ieee300)` lists nine physical operating inputs;
choose `laws=:dispatchable/:vv/:vw/:both` separately. IEEE 300 intentionally does
not inherit the older overlays' solved-region targets.

## Characterization protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/search-applications.jl \
  --network=ieee300 --out=examples/opf/pglib/search-results/ieee300-applications \
  --profiles=current,ratio_one --max-iter=500 --max-wall=60
```

The plan records the selected network and complete source/environment hashes.
Each input has a matched dispatchable NLP. Raw flat/profile trials run first;
separate exact-sector reference attempts choose sectors from actual iterates,
with checked neighboring operating points available as fallback. Witness starts
are independently feasible for the original MPCC at 1e-7. Raw solver status and
six original residuals are retained; physical passes use 1e-5. Failed reference
attempts and unavailable starts remain recorded. No reference replaces a raw
failure or certifies full-MPCC stationarity/global optimality.

Coverage reports distinguish curve regions/fractions, inverter capability and
availability, conventional P/Q boxes, bus-voltage limits and individual branch
ends. Coverage is meaningful only alongside original feasibility. A curtailed
plant with slack device caps is a candidate network/control interaction, not a
causal attribution. Increasing physical severity or network size need not increase
solver difficulty.
