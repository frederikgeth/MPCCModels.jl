# Balanced AC OPF contribution roadmap

Development branch: `codex/opf-volt-var-watt`.

## Scope

Add a self-contained, two-bus, balanced AC optimal power flow example with
fixed volt-var and volt-watt curves. Port the exact nonnegative hinge pairs
from [BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383)
(source commit `faf3d455381e15b651808c489237c0dd921d7cf7`).
Use `ADNLPModels` and the existing `MPCCModel(nlp, ind_vcc1, ind_vcc2)`
constructor, following the package's small model constructors. Keep power-system
dependencies and solver dependencies out of the package runtime.

The network is synthetic and uses positive-sequence AC equations in per unit.
Volt-var fixes reactive injection; volt-watt is an active-power upper bound,
alongside availability and the inverter apparent-power limit. Fixed curves do
not implement controller tuning, dynamics, hysteresis, or additional priority
logic. Each operating case must identify a feasible physical reference point;
these reference points are not optimality certificates.

## Milestones

- [x] Review the package API, test style, and source hinge formulation.
- [x] Create a dedicated development branch and record the implementation scope.
- [x] Add the AC OPF constructor, hinge equations, and documented variable ordering.
- [x] Add cases for reactive injection/absorption, deadband, saturation,
      volt-watt curtailment, and every curve breakpoint.
- [x] Verify physical feasibility, exact control values, complementarity pairs,
      active bounds, and derivatives in the package test suite.
- [x] Add runnable example instructions and a documentation tutorial.
- [x] Run the complete tests, documentation checks, and optional CCOpt solves;
      record results and commit the finished contribution.

## Validation and review

The tests must evaluate AC balance independently from the model equations,
compare the hinge curves with direct piecewise evaluations, check both sides
of every breakpoint, and check nonnegativity as well as complementarity.
Finite differences must cover the objective, constraint Jacobian, and
Lagrangian Hessian at a point away from the reference start. Tests also need
to distinguish a volt-watt cap from a forced output equality and reject points
with violated network or inverter limits even when the hinge pairs are exact.

Keep solver experiments separate from model correctness tests. Report original
AC constraint violations, variable-bound violations, complementarity residuals,
and direct control-curve errors. Do not inherit solver-performance claims or
historical numerical results from the draft PR.

## Follow-up scope

- Add a small meshed transmission case using the same control encoding.
- Explore cases with binding inverter capability and explicit priority policies.
- Port selected unbalanced BMOPF cases in a separate contribution.

## Validation record

- The mixed linear/nonlinear OPF exposed an existing complementarity-Jacobian
  structure bug. A separate prerequisite commit switches both sides to the full
  underlying Jacobian and adds a regression in Float32 and Float64.
- Complete `Pkg.test()` passes on Julia 1.10.12 and 1.12.6: 802 assertions
  (48 lifted-model, 118 MPCC API, and 636 OPF). The model uses coordinate arrays
  for its linear constraints, so the example needs no extra standard-library
  imports in the isolated test environment.
- All 12 Float64 reference points have maximum residual below `4e-15`.
  These are feasibility checks, not solve-performance results.
- The Documenter build passes, including all executable OPF examples and cross
  references. External link checking was disabled for the offline build;
  the normal documentation configuration still enables it. The build script
  now sets its root explicitly so it works from the repository root.
- The documented example environment resolves from a fresh manifest. With
  Julia 1.12.6, CCOpt 0.1.0, and MadNLP 0.10.1, `solve.jl all` returns
  `SOLVE_SUCCEEDED` for all 12 cases from the default flat starts. Maximum
  residuals across these runs are:

  | Check | Maximum residual (per unit) |
  | --- | ---: |
  | Original NLP constraints | `2.28e-15` |
  | Variable bounds | `0` |
  | Complementarity minimum residual | `3.11e-7` |
  | Direct volt-var error | `2.12e-6` |
  | Direct volt-watt cap violation | `4.97e-6` |

  The runner checks all five against `1e-5` and preserves the solver status.
  Relaxation-update options are supplied through `CCOpt.RelaxationOptions`;
  MadNLP tolerances and bound settings are supplied to `RelaxationSolver`.
  These experiments establish numerical feasibility, not global optimality
  or a performance comparison with other solvers.
- New Julia example and test files are formatted with the repository's
  JuliaFormatter configuration. `git diff --check` passes.
