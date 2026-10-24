# PGLib transmission OPF roadmap

## Aim and acceptance rules

Keep the 37 small synthetic cases as precise unit/regime regressions. Add a
separate, optional transmission benchmark family using PGLib-OPF v23.07, pinned
to commit `dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3`. Preserve original files,
licenses and attribution; express modifications in named, reproducible overlays.
No power-system or solver dependency is added to the MPCCModels runtime.

A correctness/regime regression is accepted after a successful solve, independent
physical feasibility checks, and achieved coverage checks. Hard-case search has a
separate retention rule: preserve all requested runs, including solver failures,
exceptions and interrupted attempts. A verified numerical witness establishes
feasibility independently of the failing solver; an unresolved witness search
does not establish infeasibility. A feasible constructed witness
is useful for debugging but does not establish an optimum or a solved regime.
Report local solutions and selected-sector refinement honestly; do not claim
global optimality or full MPCC stationarity from feasibility alone.

## Development stages

1. **Import and canonical foundation.** IEEE 14 (20 branches), then IEEE 118
   (186 branches), plus their `api` variants. Preserve shunts, line charging,
   fixed transformer taps/phase shifts, conventional generator P/Q bounds,
   quadratic production costs, both branch-end ratings, voltage bounds and
   branch angle-difference limits. Fix only the reference angle. Validate the
   uncontrolled NLP against PowerModels at the same operating point and compare
   independently solved objectives, allowing different local minima explicitly.
2. **Matched controller overlays.** Keep conventional generators; add explicitly
   rated inverter injections. Compare dispatchable P/Q, VV only, VW only and both
   on identical hardware, availability, costs and network data. Curves use local
   voltage but system-base power; record conversions from device bases. Do not
   assume every generator is a VV-controlled inverter.
3. **First accepted matrix.** Start with a few dispersed controllers on IEEE 14
   and IEEE 118. Add homogeneous and heterogeneous profiles. Use feasible
   in-band breakpoints, and freeze independently specified solved targets.
4. **Binding-limit studies.** Use `api` cases for congestion, then isolate
   capability circles, voltage bounds, conventional P/Q bounds, branch ends,
   availability and VW caps. Add load/availability variations and clustered or
   colocated controllers. Demonstrate effects with matched controls disabled
   and small limit perturbations; distinguish tightness from economic influence.
5. **Scaling.** Add RTS 24 and IEEE 300, then selected larger systems. Increase
   controller count separately from network size. Report dimensions, sparsity,
   residuals, starts, status, polishing, runtime and achieved activity. Keep
   expensive or unstable experiments outside the fast test gate.

## Matrix design

| Axis | Levels and acceptance evidence |
| --- | --- |
| Network | 14/118 first; original and congested `api`; later 24/300 |
| Laws | Dispatchable P/Q, VV, VW, VV+VW with matched hardware/costs |
| Placement | Dispersed, clustered, same-bus heterogeneous profiles |
| Population | Few devices, increasing count, increasing penetration |
| Operating point | Nominal, light load/high availability, stressed load |
| VV | Low plateau, injection ramp, deadband, absorption ramp, high plateau |
| VW | Upper plateau, ramp, lower plateau; availability tighter/equal/looser |
| Position | Interior fractions near 0.2/0.5/0.8, knees, left/right neighbors |
| Limits | Availability, VW, S circle, Q box, bus V, generator P/Q, each branch end, angle difference |

Use a compatible subset, not a Cartesian product. A controller has one voltage,
so VV and VW regions cannot be assigned independently when profiles overlap.
Identical profiles at the same bus imply identical curve regions. Different
availability or costs can change limiting constraints without changing region.

## Making the cases meaningful

- Check every requested region intersects the bus voltage interval before solving.
  The original synthetic VW threshold 1.07 is unreachable in IEEE 14's 1.06
  upper voltage bound. Use documented synthetic transmission profiles inside
  the existing band; do not silently relax the network's bounds.
- Choose ramp slopes and device ratings together. Ensure capability and Q boxes
  can accommodate intended VV values, or deliberately designate their conflict.
  Preserve VW as an upper bound: voltage on its ramp does not imply it binds.
- Explore load/availability/profile offsets with deterministic parameter grids;
  select scenarios by achieved regimes, then freeze their inputs and explicit
  target windows. Never select a complementarity sector using desired targets.
- Record per-controller region, normalized ramp position, breakpoint distance,
  margins to availability/VW/S/Q bounds; report all bus, generator and branch
  margins. Check all original equations, bounds, both hinge members and direct
  curves independently of solver stopping tests.
- Define tight/slack tolerances in physical units and normalize reporting by
  device or branch rating where useful. Squared S residuals are not S margins.
  Boundary neighbors must be separated from classifier/feasibility tolerances.
- Require targeted limits tight and named competitors strictly slack. A duplicate
  plateau/Q bound is a degeneracy study, not two distinct mechanisms. Check
  sensitivity to small RHS changes before claiming a limit drives dispatch.
- For multi-controller cases require simultaneous contrasting regions, e.g.
  injection/deadband/absorption plus availability-limited and VW-limited devices.
  Keep all controllers coupled through one consistent network solution.
- Keep a baseline with the same added devices but dispatchable P/Q. Also retain
  the unmodified PGLib baseline to validate import; these baselines differ.
- Report infeasible combinations and solver failures separately from accepted
  benchmarks. Avoid narrow solved voltage targets unless reproducible across
  supported solvers; report aggregate quantities when dispatch is nonunique.

## Progress

- [x] Agree the staged network/control/activation matrix.
- [x] Pin PGLib v23.07 provenance and define acceptance criteria.
- [x] Import original 14/118 and congested variants with license and hashes.
- [x] Implement and test canonical transmission NLP and hinged MPCC overlay.
- [x] Cross-check the baseline against PowerModels.
- [x] Freeze first solved multi-controller overlays and independent targets.
- [x] Add optional solver/coverage tests and runnable documentation.
- [x] Add sensitivity-backed isolated inverter VW and capability-limit studies.
- [x] Add isolated voltage/thermal/generator/angle-limit perturbation studies
      on IEEE 14, with within-family isolation and explicit competitor checks.
- [x] Develop matched three-device dispersed/clustered/colocated placement studies.
- [x] Develop fixed-total replica populations and growing distinct-site fleets.
- [x] Separate population, placement/profile and penetration experiments.
- [ ] Freeze plateau, ramp-stratum and knee-neighbor coverage in transmission cases.
- [ ] Develop heterogeneous distinct-site fleets with constant profile mixture.
- [ ] Compare shared `(bus,knot)` hinges with explicitly redundant formulations.
- [ ] Add the first IEEE 118 isolated network-limit sensitivity families.
- [ ] Add RTS 24/IEEE 300 after the coverage gaps are addressed.

## Initial implementation and validation

- Four unmodified, hash-verified source files retain upstream license and
  attribution. PowerModels parses them without its network repair pass; units
  are converted explicitly. Power-system and solver packages remain confined
  to the optional `examples/opf/pglib` environment.
- The canonical builder preserves the full pi/transformer network, costs,
  conventional generator boxes, bus bounds and branch-end/angle limits. All
  voltage magnitudes are optimized; only one reference angle is fixed.
- The first suite has 22 cases: four canonical baselines, four matched law
  variants on each network and two isolated IEEE 14 inverter-limit studies.
  Every overlay has three controllers; both-law overlays have 18 hinge pairs.
- The IEEE 14 mixed case simultaneously exercises VV absorption, deadband and
  injection. The congested IEEE 118 case exercises two injection ramps and a
  plateau. IEEE 118 thermal limits remain active with controllers; the IEEE 14
  API overlays relieve the two thermal limits active in its canonical baseline.
  These outcomes are explicit coverage assertions, not assumed from case names.
- Strict IEEE 14 VW curtailment occurs near the middle of a gentle ramp with
  availability and capability slack. A separate case activates the S circle
  with availability and VW slack. Small independent relaxations increase device
  dispatch and reduce cost. Broader network-limit sensitivities remain open.
- An exploratory IEEE 118 capability overlay failed homotopy termination and
  original-curve checks. It is excluded from accepted scenarios. Solver success
  and physical/coverage tolerances were not weakened to include it.
- Optional CI runs model checks, independent PowerModels/Ipopt baselines, and
  solved activity/sensitivity gates on Julia 1.12. Remote CI is pending a PR or
  workflow dispatch; local validation is recorded below.

## Local validation record

- Julia **1.10.12 and 1.12.6**: optional model tests **554 assertions**,
  independent PowerModels/Ipopt baseline comparison **16 assertions**, and
  solved activity/matched controls/limit perturbations **235 assertions**.
  All **22 accepted cases** solve from the documented flat-voltage starts and
  meet original residual and explicit coverage gates on both Julia versions.
- Julia 1.12.6: complete package suite **2050 assertions** passes. No core
  package code or dependencies changed in this transmission expansion.
- Baseline objectives (our local solves; PowerModels/Ipopt agrees within the
  tested tolerances) are 2178.080428 for IEEE 14, 97213.607396 for IEEE 118,
  5999.363314 for IEEE 14 API and 249614.524493 for IEEE 118 API. These are
  agreement checks between local solves, not global-optimum certificates.
- Validation environment: ADNLPModels 0.8.15, CCOpt 0.1.0, MadNLP 0.10.2,
  PowerModels 0.21.7, Ipopt.jl 1.16.0 and JuMP 1.32.1. Compatible versions are
  specified in the optional Project; the local manifests are not committed.
- Documenter builds successfully with the transmission overview. External link
  checking was disabled for the offline build; the committed configuration
  retains it. Pinned data hashes, local Markdown links, JuliaFormatter and
  `git diff --check` pass. CI definitions are added; remote results are pending.

## Sources

- [PGLib-OPF](https://github.com/power-grid-lib/pglib-opf/tree/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3)
- [Canonical formulation](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/MODEL.tex)
- [Baseline results](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/BASELINE.md)
- [Original synthetic case matrix](../CASE_DESIGN.md)

## Review and study expansion

The [implementation review](REVIEW.md) records the initial solved coverage census,
structurally unreachable regions, corrected overlay/target validation gaps,
placement/population experiments and recommended next named cases. The new study
constructors and runner are separate from the initial 22-case registry.

- Network overlays rebuild NLP records and independent-check data from one
  copied authoritative dictionary. Stale records are rejected. VV/VW target
  validation now intersects both laws and fraction windows at the shared voltage.
- Diagnostics distinguish fixed generator boxes from economic bound activity
  and expose normalized inverter margins and nearest-knot distances.
- IEEE 14/118 studies compare three-device placement and profile homogeneity;
  3/6/12 replica populations at fixed aggregate size; 1/3/6/12 controllers on
  nested distinct bus sets; and independent 0.5/1/2 penetration levels.
- IEEE 118 homogeneous clustering adds an observed VV knee. It still needs
  left/right neighbors. Redundant coincident hinges remain explicitly identified
  as a formulation characteristic, especially in replica/knee experiments.
- Eight IEEE 14 network studies perturb one RHS in both directions and at half
  step, assert target and competing bound activity, and compare dispatchable
  policies on the same modified network. Isolating one family does not imply
  every other network family is slack; the branch-1 thermal case additionally
  checks this stronger property.
- The branch-6 receiving-end study combines network-driven curtailment below a
  slack VW cap at one device with strict VW curtailment at another device.
- Remaining highest priorities are in-band absorption/lower-watt plateaus, ramp
  strata away from availability crossovers, knees with neighbors, hardware-Q/VV
  intersections and IEEE 118 location-sensitive thermal/controller interactions.

Validation of the review expansion: Julia 1.10.12/1.12.6 pass **578 model** and
**376 study** assertions. Julia 1.12.6 also passes the existing **235 solved-case**
and **16 independent baseline** assertions after the changes. Documentation
builds with offline external-link checking disabled. The expanded optional CI
gate is committed; remote execution is pending.

## Hard-case search: IEEE 118 capability intersection

The immediate objective is to identify reproducible CCOpt difficulties. Keep
failures and configuration-sensitive cases rather than filtering the search to
examples the solver already handles. Preserve the original 22-case regression
suite as a model-correctness check.

- [x] Reproduce the IEEE 118 device-3 S=0.82 case: the current flat-start
  homotopy reaches its iteration limit; a separately selected exact-sector
  solve yields a numerically feasible point. Default-like and exact-start
  settings give different outcomes, so this is a parameter/start-sensitive
  candidate, not a universal CCOpt failure.
- [x] Sweep S ratings around the capability/VW/availability intersection while
  holding availability, control profiles, network and costs fixed.
- [x] Compare flat, neighboring-case, seeded perturbed and verified-witness
  starts; save their actual vectors and source provenance.
- [x] Compare explicit default-like/current settings and individual changes
  to inner tolerance, relaxation ratio and relaxation floor.
- [x] Checkpoint raw requests before solving and preserve their results
  independently of witness/refinement work; retain exceptions, returned/current
  iterates and original physical checks.
- [x] Save full input snapshots, package/source fingerprints, effective solver
  options, budgets, timings, checksums and replayable request records.
- [x] Verify and preserve feasible witnesses separately from homotopy results.
- [x] Warm up before timed trials, retain warmups separately, support safe
  resume/replay, and summarize known-feasible failures versus accuracy gaps,
  unresolved feasibility and interface errors.
- [x] Run a first complete matrix, curate the 0.82 reproduction and add tests
  that verify the recorder without requiring a particular solver failure.

The BMOPFTools comparison at `faf3d455381e15b651808c489237c0dd921d7cf7`
([experiment notes](https://github.com/frederikgeth/BMOPFTools.jl/blob/faf3d455381e15b651808c489237c0dd921d7cf7/scripts/README.md))
informs this design: active controls, solver/formulation controls, original-curve
checks, sensitivity to inner tolerances, and timing after compilation. Product
residuals alone do not measure the physical error of a steep droop curve. API
exceptions and smooth-formulation overflow remain separate failure categories.

### First search results and next steps

The [harness instructions and results](HARD_SEARCH.md) describe the complete
160-trial run: 22 non-success terminations on known-feasible inputs, 52
solved-status accuracy gaps and 86 runs passing both status and original physical
checks. All eight capability variants have independently verified witnesses.
The [committed 0.82 receipt](hard-cases/README.md) preserves a witness plus
failed, accuracy-limited and recovered raw runs, with actual start/point vectors
and bit hashes. The complete search is retained locally under `search-results/`.

The five current-profile failures occur only from flat starts at factors
0.78–0.83; a matched change of relaxation ratio recovers all five. Seven of the
22 non-success trials report local infeasibility despite verified witnesses.
This is evidence of configuration/initialization sensitivity, not a claim of
universal algorithm failure. Small default-profile physical errors are recorded
separately from stalled, large-residual results.

- [ ] Refine the current-profile flat-start transition between 0.83 and 0.84.
- [ ] Repeat with several explicit perturbation seeds and fixed resource budgets.
- [ ] Minimize network/controller complexity while preserving a reproducible
  failure and an independently verified witness.
- [ ] Add simultaneous-knee/colocated and stressed-PV families to the same
  failure-retaining protocol; compare redundant and shared-knot encodings.
- [ ] Assess feasible-point objective/stationarity evidence separately from
  termination and feasibility, without treating a better point as proof against
  local optimality or a selected-sector solution as a full MPCC certificate.

### Ratio-one simultaneous-transition and generator-Q search

The next search fixes `ratio_one` (which passed the first capability matrix)
and combines three colocated controllers with simultaneous VV deadband/absorption
and VW onset transitions. Separate nearby VW offsets from exactly coincident
knees. Tighten one original conventional-generator Q upper bound without changing
its P bounds, costs or other network data. Preserve separate case snapshots and
all raw starts/results; never infer infeasibility from unsuccessful homotopy.

- [x] Select feasible in-band knees and a local generator-Q limit; document
      actual binding margins and knee distances at numerical witnesses.
- [x] Sweep Q upper limits and VW offsets with flat, neighboring, independently
      perturbed and witness starts under fixed `ratio_one` budgets.
- [x] Retain exact-sector witnesses separately and verify all original physical
      equations, curve laws, boxes and complementarity before registering them.
- [x] Curate reproducible difficult trials, matched recoveries and witnesses;
      report achieved activity separately from requested activity.
- [x] Test case invariants, activity reporting and persistence; document results
      and the next reduction/shared-hinge experiments.

Validation: **105 harness/curated-record assertions** pass on Julia 1.10.12 and
1.12.6. The existing **578 PGLib model assertions** pass on Julia 1.12.6, and
Documenter builds with external link checks disabled locally. The archived
0.82 flat/current request was replayed under the finalized recorder and again
stopped at 500 iterations with the same returned-point residuals. Full resume
left all 800 raw-attempt files unchanged. CI runs the short recorder/witness
tests; the 160-trial search remains an explicit research run.

The completed ratio-one matrix has **54 known-feasible iteration-limit exits**:
all three Q limits × all three VW offsets × six starts. None passes the original
physical gate. All nine separately verified witnesses bind generator 45's Q upper
limit; all three zero-offset witnesses put all three controllers at simultaneous
VV/VW knees. Maximum witness residual is below `2.5e-11`. Nearby Q perturbations
confirm local dispatch/cost influence. The relaxed-Q setup and both separated
knee neighbors also fail, so neither Q tightness nor exact VV/VW coincidence
alone explains the difficulty. See [protocol/results](HARD_SEARCH.md) and
[portable records](hard-cases/README.md#ratio-one-transitionq-limit-receipt).

Next reductions, keeping raw results and verified witnesses for every variant:

- [ ] Compare one, two and three active controllers while retaining the other
      devices as matched dispatchable injections; distinguish controller count
      from total injected power and device hardware.
- [ ] Compare separate hinges with shared `(bus,knot)` hinges on identical
      physics, starts and budgets; report dimensions and redundant constraints.
- [ ] Separate availability from the upper VW plateau and move its crossover
      into the ramp; distinguish coincident physical bounds from shared knots.
- [ ] Split same-bus devices across nearby buses while keeping profiles and
      aggregate ratings fixed; preserve the knee/Q activity evidence.
- [ ] Check selected-sector objective/stationarity diagnostics and report which
      failure persists before extending to IEEE 300 or larger fleets.

Validation: **419 recorder/archived-point assertions** pass on Julia 1.10.12
and 1.12.6, and the existing **578 transmission-model assertions** pass on
1.12.6. Documenter builds locally with external link checks disabled. A full
resume preserves all **270 raw-attempt files** byte for byte. Remote CI remains
pending. The complete local archive is
`search-results/ieee118-transitions-2026-10-24.tar.gz` (SHA-256
`56d834e6c5e6a12737aa7665a11f77fa662b2800d8eff7f7fcd5f334b35b7d41`).
