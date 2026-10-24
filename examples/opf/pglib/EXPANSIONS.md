# Application operating coverage and fixed-total fleets

This extension follows the [application catalog](APPLICATIONS.md). It retains
balanced IEEE 118 AC physics and makes operating policies and plant geography
explicit. All profiles are synthetic study settings, not prescribed grid-code
values or calibrated feeder controls. Intended regimes are descriptive; no
constructor fixes voltages, chooses sectors from targets, or assumes coverage.

## Nine operating-policy inputs

`application_policy_case(policy; laws=:both, hinge_encoding=:separate)` uses the
same data-to-ADNLPModel/MPCCModel design as other examples. Its card records the
base application, operating parameters, relative profile knots/ordinates and
rationale. Original plant-specific voltage shifts are retained; all knots stay
inside original bus bounds. Profiles change policy service limits/export caps,
while hardware circles and Q boxes remain independent and unchanged from the
specified base operating point. The four policy enablement variants have
identical physical inputs.

| Policy | Base application | Physical change | Intended coverage |
| --- | --- | --- | --- |
| `absorption_service` | Renewable surplus, elevated; availability .85S | ±.25S VV service at [.95,.985,1,1.02], delayed VW [1.04,1.053] | Absorption saturation with hardware headroom |
| `injection_service` | Reactive support, severe; Q factor .3, availability .85S | VV [.12,0,0,−.25]S at [1.025,1.04,1.047,1.053] | Limited reactive participation reaches injection saturation |
| `early_export_backstop` | Export corridor, elevated; rating factor .8 | Wide VV deadband [.99,1.035], ±.25S service; VW [1,1.02] with [1,.65]S | Lower VW plateau with strict curtailment |
| `early_absorption_backstop` | Renewable surplus, elevated | VW [1.0165,1.0285], [1,.2]S; original VV | Earlier active intervention along absorption ramp |
| `middle_absorption_backstop` | Same | VW [1.0285,1.0405], [1,.2]S | Intermediate absorption position |
| `late_absorption_backstop` | Same | VW [1.0405,1.0525], [1,.2]S | Later absorption position |
| `gentle_watt_cap` | Renewable surplus, elevated | VW [1,1.04], [.82,.815]S; original VV | Export ceiling and gentle voltage backstop |
| `firm_watt_cap` | Same | VW [1,1.04], [.82,.80]S | Stronger backstop with strict availability slack |
| `steep_watt_cap` | Same | VW [1,1.04], [.82,.76]S | Strong backstop and different local equilibria |

The last three policies include an interconnection active-export ceiling below
available renewable power. Their total curtailment therefore includes that
ceiling; do not attribute all curtailed power to the voltage-dependent ramp.
The absorption-backstop policies share hardware/availability/VV and change only
the VW voltage window. All achieved fractions, plateaus and active constraints
are measured at verified points, separately from the intended descriptions.

```julia
include("examples/opf/pglib/transmission-opf.jl")
using .TransmissionOPF

data = application_policy_case(:early_export_backstop)
card = application_policy_card(:gentle_watt_cap)
```

## Population and geography

`application_fleet_case(:reactive_support; level=:elevated, count=12,
placement=:dispersed)` splits each of the six original heterogeneous profile
classes into proportional units. Counts 6/12/24 preserve each class's aggregate
S rating, P availability, hardware Q boxes and normalized VV/VW curves. Total
installed size stays **900 MVA**, availability **765 MW**. Classes are assigned
round-robin in original order, so rating-weighted profile mixture is unchanged.

- `:same_sites`: proportional units remain at their original six connection
  points. Aggregate physical feasibility is preserved; increasing unit count adds
  representation size and repeated hinges. This is the explicit count control.
- `:clustered`: distinct eligible sites are ordered by hop distance from original
  bus 44, breaking ties by original bus ID.
- `:dispersed`: starts at bus 44, then greedily maximizes minimum hop distance to
  selected sites, with original ID breaking ties.

Distinct-site sets are nested for increasing counts, exclude the reference bus,
and retain valid original voltage bands for all profiles. They may include
conventional-generator and zero-load buses. These are topology-based study
placements, not voltage-sensitivity rankings or calibrated development plans.
More distinct sites intentionally changes geography; it is not a pure count
experiment. Compare placements at fixed count and use same-site replicas as the
aggregate-physics control.

| Units | Separate hinge pairs | Variables | Ordinary constraints |
| --- | --- | --- | --- |
| 6 | 36 | 428 | 848 |
| 12 | 72 | 512 | 902 |
| 24 | 144 | 680 | 1010 |

`application_fleet_start(target, source, x)` copies network variables and splits
plant P/Q by profile class, then constructs exact target hinges. At the same
sites the original physical reference remains feasible up to numerical tolerance.
For relocated plants the transfer is only a start and generally violates balance
or laws; it is never called a witness without rechecking the full original model.

## Recorded protocol

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-expansions.jl
julia --project=examples/opf/pglib examples/opf/pglib/search-expansions.jl \
  --kind=coverage --out=examples/opf/pglib/search-results/ieee118-coverage-2026-10-25
julia --project=examples/opf/pglib examples/opf/pglib/search-expansions.jl \
  --kind=fleet --profiles=ratio_one \
  --out=examples/opf/pglib/search-results/ieee118-fleets-2026-10-25
```

The coverage batch records **36 raw trials**: nine inputs × current/ratio_one ×
flat/reference starts. The fleet batch records **18 raw trials**: nine inputs ×
ratio_one × flat/reference starts. Each batch also retains nine matched
ordinary-NLP dispatchable counterfactuals, warmups and reference attempts.
Raw budgets are 500 iterations/60 seconds, inner tolerance `1e-9`, and original
physical acceptance `1e-5`; references must verify at `1e-7`. Identical arguments
with `--resume` preserve completed attempts; `--summarize=DIR` rebuilds reports.
The long matrices remain manual research runs; CI checks constructors,
equivalence/invariants, derivatives and archived numerical evidence.

Every input receives a transferred start from the committed original application
reference. Its source, complete target input and actual vector are recorded.
The transfer is explicitly a non-solver record. When it independently satisfies
the target model it can establish feasibility; otherwise it remains only a start.
Separate operating-reference NLPs select sectors by the transferred voltage's
hinge signs. Returned-iterate reference NLPs use signs from actual raw iterates.
No intended-region label chooses a sector. All attempts, failures and verified
reference coverages are reported; no raw result is polished or replaced.

A verified physical transfer is retained even if a subsequent NLP solve fails.
Otherwise a verified operating/returned reference or raw point supplies the
reference start. Records distinguish constructed points from solver results.
Selected-sector/local references establish numerical feasibility and measured
activity, not full MPCC stationarity or a global optimum. Raw optimizers may
reach different regions from the operating reference; retain both rather than
claiming one canonical activity pattern.
