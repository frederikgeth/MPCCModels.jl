# PGLib transmission OPF roadmap

## Aim and acceptance rules

Keep the 37 small synthetic cases as precise unit/regime regressions. Add a
separate, optional transmission benchmark family using PGLib-OPF v23.07, pinned
to commit `dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3`. Preserve original files,
licenses and attribution; express modifications in named, reproducible overlays.
No power-system or solver dependency is added to the MPCCModels runtime.

A benchmark is accepted only after a successful solve, independent physical
feasibility checks, and achieved coverage checks. A feasible constructed witness
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
- [ ] Import original 14/118 and congested variants with license and hashes.
- [ ] Implement and test canonical transmission NLP and hinged MPCC overlay.
- [ ] Cross-check the baseline against PowerModels.
- [ ] Freeze first solved multi-controller overlays and independent targets.
- [ ] Add optional solver/coverage tests and runnable documentation.
- [ ] Add sensitivity-backed isolated equipment-limit studies.
- [ ] Expand coverage strata, placement patterns and system sizes.

## Sources

- [PGLib-OPF](https://github.com/power-grid-lib/pglib-opf/tree/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3)
- [Canonical formulation](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/MODEL.tex)
- [Baseline results](https://github.com/power-grid-lib/pglib-opf/blob/dc6be4b2f85ca0e776952ec22cbd4c22396ea5a3/BASELINE.md)
- [Original synthetic case matrix](../CASE_DESIGN.md)
