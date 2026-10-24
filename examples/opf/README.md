# Balanced AC OPF with volt-var and volt-watt controls

This example provides a two-bus, balanced AC OPF as a vertical-form `MPCCModel`.
It uses `ADNLPModels`, as do the package's existing small test models. It adds
no dependencies to the package runtime. The example environment includes CCOpt
for the optional solve script.

The exact hinge formulation is ported from
[BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383),
specifically `_complementarity_curve_expr!` at commit
[`faf3d455381e15b651808c489237c0dd921d7cf7`](https://github.com/frederikgeth/BMOPFTools.jl/blob/faf3d455381e15b651808c489237c0dd921d7cf7/ext/BMOPFOpfExt/ibr.jl#L357).

## Run

From the repository root, prepare the example environment against this checkout:

```sh
julia --project=examples/opf -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=examples/opf examples/opf/solve.jl curtailment
julia --project=examples/opf examples/opf/solve.jl all
```

The script uses CCOpt's relaxation solver with nonnegative hinge bounds kept
unrelaxed. It reports the solver status, original objective, voltage, inverter
P/Q, and residuals of the original model and direct control curves. It accepts
successful or acceptable-level termination and fails on other statuses or if
any residual exceeds `1e-5` per unit. Acceptable-level status remains visible
in the report. The tight
solver and relaxation tolerances are example settings, not universal OPF
recommendations. A small hinge product can still permit a larger control error
at a breakpoint, which is why the script checks the physical curves directly.

To inspect a case without solving:

```julia
using MPCCModels, NLPModels
include("examples/opf/balanced-ac-opf.jl")
using .BalancedACOPF

data = balanced_ac_opf_case(:curtailment)
mpcc = BalancedACOPFModel(; case = data.name)
x = balanced_ac_opf_reference(data)
@show get_nvar(mpcc), get_ncon(mpcc), get_ncc(mpcc) # (18, 15, 6)
@show x[1], x[5], x[6]                           # approximately (1.09, 0.68, -0.3)
@show opf_residuals(mpcc, x, data)
```

`BalancedACOPFModel(Float32; case = :deadband)` is also supported.
`x0` accepts a custom starting vector; by default the constructor uses a flat
voltage profile rather than the feasible reference.

## Model and cases

The source voltage magnitude and angle are fixed. The other bus has a constant
PQ load and one inverter. Power balance uses the full AC equations through a
series impedance `0.02 + 0.08im` per unit. The objective minimizes source active
injection; negative injection represents export. Both ends of the branch have
apparent-power limits, and the inverter has a capability circle.

Volt-var **sets Q**. Volt-watt **caps P**, together with the separate available
power bound. There is no additional capability-dependent clipping, active-power
priority, or controller dynamics. All data are synthetic. The wide voltage band
is chosen to exercise the control regimes; it is not a grid-code prescription.

| Case | Reference voltage | Inverter P | Inverter Q | Regime |
| --- | ---: | ---: | ---: | --- |
| `low_voltage_saturation` | 0.92 | 0.8 | 0.3 | Saturated reactive injection |
| `reactive_injection` | 0.96 | 0.8 | 0.15 | Lower volt-var ramp |
| `deadband` | 1.00 | 0.8 | 0 | Reactive deadband |
| `reactive_absorption` | 1.04 | 0.8 | -0.15 | Upper volt-var ramp |
| `curtailment` | 1.09 | 0.68 | -0.3 | Binding volt-watt ramp |
| `high_voltage_saturation` | 1.14 | 0.2 | -0.3 | Both lower power plateaus |

Six more cases sit exactly on the curve breakpoints: `vv_lower_knee` (0.94),
`vv_deadband_lower` (0.98), `vv_deadband_upper` (1.02), `vv_upper_knee` (1.06),
`vw_upper_knee` (1.07), and `vw_lower_knee` (1.12). The volt-watt names refer to
the upper and lower **power** plateaus. At a breakpoint the corresponding hinge
is biactive: both its nonnegative members are zero.

The source voltage is constructed separately for each case to admit the listed
feasible reference. Voltage is still a decision variable in the OPF. These
references establish case coverage and feasibility, not global optimality.

## Variable and constraint ordering

The variables are `[v, theta, pg, qg, p, q, r[1:6]..., s[1:6]...]`.
Angles are in radians; the other quantities are in per unit on a common
three-phase power base and its corresponding voltage base.
The complementarity index vectors are `7:12` and `13:18`.

| Constraint rows | Meaning |
| --- | --- |
| 1–6 | Linear hinge definitions `r[k] - s[k] - v = -knot[k]` |
| 7 | Linear link from the first four hinges to reactive power |
| 8 | Linear active-power cap from the final two hinges |
| 9–12 | AC active/reactive balance at the source and inverter buses |
| 13 | Inverter apparent-power limit |
| 14–15 | Branch apparent-power limits at both ends |

The underlying NLP has no nonsmooth control evaluations or complementarity
product equalities. `MPCCModel` receives the six pairs separately.

## Validation

Run the package tests with `julia --project -e 'using Pkg; Pkg.test()'`.
The OPF tests cover Float32/Float64 reference feasibility, complex-phasor power
balance, losses, each control regime, both sides of every breakpoint,
nonnegativity, biactivity, direct curve errors, violated equipment limits, and
finite-difference checks of the gradient, Jacobian, and Lagrangian Hessian.
They also construct a feasible dispatch strictly below the volt-watt cap.
Core tests do not require CCOpt; `solve.jl all` is a separate integration check.

See [ROADMAP.md](ROADMAP.md) for contribution progress and follow-up scope.
The [case-design matrix](CASE_DESIGN.md) reviews current coverage and plans
additional active constraints, curve positions, and multiple-controller studies.
