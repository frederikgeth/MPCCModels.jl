# Balanced AC OPF with inverter controls

The example in `examples/opf/balanced-ac-opf.jl` constructs a small balanced AC
optimal power flow problem with exact volt-var and volt-watt controls. It returns
the existing [`MPCCModel`](@ref), using `ADNLPModels` for the underlying NLP.
The example is separate from the package's runtime API.

## Network and control assumptions

A fixed-voltage source at bus 0 connects to a constant PQ load and one inverter
at bus 1. The series impedance is ``z=0.02+\mathrm{j}0.08`` per unit, without
shunts, taps, or phase shifts. With ``V_0=E`` and ``V_1=v e^{\mathrm{j}\theta}``,
the directed branch powers satisfy

```math
S_{01}=V_0\overline{(V_0-V_1)/z},\qquad
S_{10}=V_1\overline{(V_1-V_0)/z}.
```

The balances are ``p_g+\mathrm{j}q_g=S_{01}`` and
``(p-p_L)+\mathrm{j}(q-q_L)=S_{10}``, where ``p_L=0.4`` and ``q_L=0.1``.
The objective minimizes ``p_g``; the source can absorb exported active power.
Both branch ends have a 1.5 per-unit apparent-power rating, and the inverter
has a 1.0 per-unit capability rating:

```math
|S_{01}|^2\le1.5^2,\quad |S_{10}|^2\le1.5^2,\quad p^2+q^2\le1.
```

All powers share a three-phase system base; voltage uses the corresponding
positive-sequence per-unit base. The bounds are ``0.88\le v\le1.18``,
``|\theta|\le0.3`` radians, ``|p_g|,|q_g|\le2``, ``0\le p\le0.8``, and
``-0.3\le q\le0.3``. The voltage band is deliberately wide enough to exercise
every control regime. These synthetic data do not specify a grid-code setting.

Volt-var fixes reactive injection. Its four voltage breakpoints and output
values are `(0.94, 0.3)`, `(0.98, 0)`, `(1.02, 0)`, and `(1.06, -0.3)`.
Volt-watt is an upper bound on active injection, with points `(1.07, 1.0)` and
`(1.12, 0.2)`. Both curves interpolate linearly and extrapolate constantly.
Availability remains a separate active-power bound. For these data the
volt-watt cap becomes tighter than availability above ``v=1.0825``.

The capability circle and fixed reactive-power law apply simultaneously.
There is no additional clipping, priority switching, or controller dynamics.

## Exact hinge formulation

The formulation is ported from
[BMOPFTools.jl PR #383](https://github.com/frederikgeth/BMOPFTools.jl/pull/383),
at source commit `faf3d455381e15b651808c489237c0dd921d7cf7`.
For every curve breakpoint ``\kappa_k``, introduce

```math
r_k-s_k-v=-\kappa_k,\qquad 0\le r_k\perp s_k\ge0.
```

These equations imply ``r_k=\max(v-\kappa_k,0)``. Let
``a=-0.3/(0.98-0.94)``, ``b=-0.3/(1.06-1.02)``, and
``c=(0.2-1)/(1.12-1.07)``. The first four pairs represent volt-var:

```math
q=0.3+a r_1-a r_2+b r_3-b r_4.
```

The last two pairs represent the volt-watt cap:

```math
p\le1+c r_5-c r_6,\qquad p\le0.8.
```

The NLP contains eight linear constraints: six hinge definitions, the
volt-var equality, and the volt-watt inequality. Four AC balance equations and
three equipment limits are nonlinear. Complementarity is supplied separately
to `MPCCModel(nlp, collect(7:12), collect(13:18))`.
This keeps the model in vertical form and keeps `max` and product equalities
out of the underlying NLP. Above the final volt-watt breakpoint, the lower
plateau is retained; extending the descending affine cap would change the model.

## Construct and inspect a case

The example environment can be prepared from the repository root:

```sh
julia --project=examples/opf -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
```

The documentation runs the same constructor and verifies its reference point:

```@example balanced_opf
using MPCCModels, NLPModels
include(joinpath(dirname(pathof(MPCCModels)), "..", "examples", "opf", "balanced-ac-opf.jl"))
using .BalancedACOPF

data = balanced_ac_opf_case(:curtailment)
mpcc = BalancedACOPFModel(; case = data.name)
x = balanced_ac_opf_reference(data)
(get_nvar(mpcc), get_ncon(mpcc), get_ncc(mpcc))
```

The variable order is `[v, theta, pg, qg, p, q, r[1:6]..., s[1:6]...]`.
Thus the reference voltage and inverter dispatch are:

```@example balanced_opf
round.(x[[1, 5, 6]]; digits = 3)
```

```@example balanced_opf
maximum(values(opf_residuals(mpcc, x, data))) < 1e-10
```

The constructor defaults to a flat voltage start, distinct from the feasible
reference. Use `BalancedACOPFModel(; case = data.name, x0 = x)` to supply a
custom start. Float32 construction is also supported.

## Operating regimes

Both controls are present in all cases. The source voltage is constructed for
each case so that the following feasible reference points exist; the inverter
voltage remains a decision variable during optimization.

| Case | Reference ``v`` | Reference ``p`` | Reference ``q`` |
| --- | ---: | ---: | ---: |
| `low_voltage_saturation` | 0.92 | 0.8 | 0.3 |
| `reactive_injection` | 0.96 | 0.8 | 0.15 |
| `deadband` | 1.00 | 0.8 | 0 |
| `reactive_absorption` | 1.04 | 0.8 | -0.15 |
| `curtailment` | 1.09 | 0.68 | -0.3 |
| `high_voltage_saturation` | 1.14 | 0.2 | -0.3 |

Six additional cases sit on every breakpoint: `vv_lower_knee`,
`vv_deadband_lower`, `vv_deadband_upper`, `vv_upper_knee`, `vw_upper_knee`, and
`vw_lower_knee`. The volt-watt names refer to the upper and lower power
plateaus. A pair is biactive at its breakpoint: ``r_k=s_k=0``.

```@example balanced_opf
all(balanced_ac_opf_cases()) do name
    d = balanced_ac_opf_case(name)
    model = BalancedACOPFModel(; case = name)
    maximum(values(opf_residuals(model, balanced_ac_opf_reference(d), d))) < 1e-10
end
```

These are feasible witnesses, not optimality certificates. The package tests
also construct a feasible dispatch strictly below the volt-watt cap, confirming
that the cap does not force an output equality.

## Solve and validate

The example environment includes CCOpt; it is not required by the package tests.
From the repository root, run one case or all twelve:

```sh
julia --project=examples/opf examples/opf/solve.jl curtailment
julia --project=examples/opf examples/opf/solve.jl all
```

The script requires successful or acceptable-level termination and checks
`opf_residuals` against `1e-5` per unit. The reported status preserves this
distinction. These residuals measure the original linear/nonlinear
constraints, variable bounds, complementarity, direct volt-var error, and
direct volt-watt violation. They establish numerical feasibility, not global
optimality. Solver timings are not benchmarked here.

The solver uses `bound_relax_factor = 0.0` to preserve nonnegative hinge bounds,
and tight solver/relaxation tolerances to control curve errors near breakpoints.
At a biactive pair, a product residual of order ``\epsilon`` can allow an
individual hinge error of order ``\sqrt{\epsilon}``. Direct physical curve
checks therefore remain necessary even when complementarity products are small.

Run `Pkg.test()` for the solver-independent tests, including independent
complex-phasor checks and finite differences of the gradient, Jacobian, and
Lagrangian Hessian. Contribution progress is tracked in `examples/opf/ROADMAP.md`.
