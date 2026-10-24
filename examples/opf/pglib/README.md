# PGLib transmission OPF with volt-var and volt-watt controls

This optional example complements the small synthetic regime tests with full
balanced transmission AC OPF. It uses pinned PGLib-OPF v23.07 IEEE 14 and 118
networks and their congested `api` variants. See the [roadmap](ROADMAP.md) for the
activation matrix, acceptance rules and further development, and the
[data provenance](data/README.md) for attribution, license and checksums.

## Run

From the repository root, using Julia 1.10 or newer:

```julia
using Pkg
Pkg.activate("examples/opf/pglib")
Pkg.develop(path = pwd())
Pkg.instantiate()
```

```sh
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee14 canonical
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee118 both
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee118_api both
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee14 both watt_limited
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl ieee14 both capability_limited
julia --project=examples/opf/pglib examples/opf/pglib/solve.jl all
```

The arguments are `network [laws [scenario]]`. Networks are `ieee14`, `ieee118`,
`ieee14_api`, `ieee118_api`; laws are `canonical`, `dispatchable`, `vv`, `vw`,
`both`. Default scenario `mixed` is available on all four networks. The
`watt_limited` and `capability_limited` scenarios are developed for IEEE 14.

## Formulation and package design

`TransmissionOPFModel(data)` returns an ordinary `ADNLPModel` for canonical or
fully dispatchable cases, and an `MPCCModel(nlp, r, s)` when a law is enabled.
There is no new core model type or package runtime dependency. The optional
environment contains PowerModels for MATPOWER parsing, and PowerModels/JuMP/Ipopt
for independent baseline validation. Solves use CCOpt/MadNLP as in the original
example. Data should be treated as immutable after constructing a model.

The canonical model preserves conventional generator P/Q bounds and polynomial
production costs, bus voltage bounds and shunts, line charging, fixed transformer
taps and phase shifts, both branch-end apparent-power limits, and branch
angle-difference limits. Only the reference angle is fixed; its voltage magnitude
is optimized. The importer disables PowerModels' network repair pass and converts
units explicitly. It supports these connected, single-network AC fixtures,
active equipment and degree-at-most-two polynomial costs. Unsupported DC lines,
storage, switches and cost models are rejected. This is not a general MATPOWER
import interface.

Added inverters are separate from the conventional generator fleet. Every law
variant retains the same P/Q hardware bounds, availability, S circle and costs.
VV fixes Q; VW caps P and permits further curtailment. Profiles are fixed and
continuous, with constant extrapolation. The same hinge implementation as the
synthetic example is used: `r - s - v = -k`, `r,s >= 0`, `r ⟂ s`, and slope-change
weights recover each piecewise-linear curve. There is no clipping or priority
policy. Each device carries four VV knots and two VW knots when both laws apply.

All quantities use the system three-phase per-unit base, **100 MVA** for these
files. Inverter S ratings are `(25,35,20)` MVA at buses `(5,9,14)` on IEEE 14 and
`(80,120,100)` MVA at buses `(20,45,95)` on IEEE 118. Availability is 80% of those
nominal ratings. Default Q boxes are ±50%, and VV plateaus ±40%, of nominal S.
The curves are synthetic transmission study profiles, not grid-code settings.
The canonical case has no added devices; the dispatchable comparison has the
same devices as its controlled variants. These are different baselines.

`transmission_layout(data)` exposes variable and constraint maps. Variables are
all voltage magnitudes, all angles, conventional P/Q, inverter P/Q and hinge
pairs. Linear rows contain hinge definitions, law links and angle differences;
nonlinear rows contain bus balances, inverter circles and branch-end ratings.

| Network size | Canonical variables / constraints | Three devices with both laws | Pairs |
| --- | ---: | ---: | ---: |
| 14 buses | 38 / 88 | 80 / 115 | 18 |
| 118 buses | 344 / 794 | 386 / 821 | 18 |

## Initial accepted matrix

The suite contains **22 cases**: four canonical networks, all four matched
controller-law variants on each network, and two additional IEEE 14 VV+VW
scenarios. Expected regions, finite-segment fraction windows and tight/slack
limits are explicit data in `cases.jl`. They do not initialize the optimizer,
select its complementarity sector or get regenerated from solver output.

The first mixed VV+VW cases give these simultaneous outcomes:

| Network/scenario | VV outcomes | VW and equipment outcomes |
| --- | --- | --- |
| IEEE 14 / mixed | Absorption ramp, deadband, injection ramp | Device 1 availability with slack VW; device 3 VW/availability crossover; generator 2 Q upper bound |
| IEEE 118 / mixed | Two absorption ramps, one injection ramp | Devices 1 and 3 at crossover; branch 163 from end tight and to end slack |
| IEEE 14 API / mixed | Two deadbands, one injection ramp | Device 3 at crossover; added devices relieve original branch 2/3 congestion |
| IEEE 118 API / mixed | Two injection ramps, one injection plateau | All availability-limited with slack VW; branch 116 from end tight and to end slack; lower and upper bus voltage bounds |
| IEEE 14 / watt_limited | Absorption and injection ramps | Device 3 strictly VW-limited near 54% of its ramp; availability/S/Q limits slack |
| IEEE 14 / capability_limited | Absorption and injection ramps | Device 3 S circle binding; availability/VW/Q limits slack |

The watt-limited scenario changes only device 3's VW cap to a gentle 0.70–0.69
fraction of nominal S over 1.02–1.05 pu. Its upper plateau is already below
availability; the optimum lies inside the ramp. The capability scenario reduces
device 3's S rating to 78% of nominal while retaining availability and Q bounds,
and moves its VW onset to 1.05 pu. Both modifications are intentional study
parameters, not changes to the original PGLib equipment.

The original synthetic curves cannot simply be pasted onto these networks:
their VW ramp starts at 1.07 pu, whereas IEEE 14's voltage upper bound is 1.06 pu.
Targets are checked for compatibility with bus voltage bounds before building.
The present transmission matrix does not yet cover every plateau, knee, ramp
stratum or isolated network-limit mechanism; those remain tracked in the roadmap.

## Validation and limits of the results

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-model.jl
julia --project=examples/opf/pglib examples/opf/pglib/validate-baselines.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-solves.jl
```

Model tests compare every branch with PowerModels at non-flat voltage/angle
points, independently evaluate complex-current AC balances, test nonzero phase
shifts/unequal end shunts, and finite-difference Jacobians and Lagrangian Hessians.
Independent PowerModels/Ipopt canonical solves are evaluated in our model, and
their objectives are compared with our flat-start solves for all four fixtures.

The solver gate requires successful status, all original residual checks at
`1e-5`, and achieved controller/network targets. Physical checks include AC
balance evaluated directly from original branch data, nonnegative hinge members,
complementarity and direct VV/VW curves. Coverage reports per-controller curve
regions/fractions and physical S/P/Q margins, every bus voltage margin, generator
P/Q margin, both branch ends and angle-difference margins. Squared S constraint
residuals and unsquared S margins are reported separately.

Matched cases check hardware/network equality and the observed objective ordering
relative to dispatchable P/Q. Small independent relaxations of the strict VW cap
and S limit must increase device 3 dispatch and reduce production cost; mere
tightness is insufficient. Negative tests reject feasible points that miss the
declared coverage. Remaining network-limit sensitivities are future work.

Conditional refinement can solve the complementarity sector selected from a
successful homotopy iterate when original feasibility or declared coverage
misses. Raw and refined statuses/results are retained. Passing these checks
establishes local numerical feasibility and the specified activity, not global
optimality or full MPCC stationarity. An exploratory IEEE 118 capability overlay
failed the homotopy gate and is not included among accepted cases.
