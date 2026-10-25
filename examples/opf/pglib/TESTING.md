# OPF test tiers and evidence

The MPCCModels public runtime API and dependencies are unchanged. OPF factories,
case cards, diagnostics and search tools live in the optional examples, whose
separate environments declare their solver and power-system dependencies.

| Tier | Trigger | Checks |
| --- | --- | --- |
| Package | Every PR/push to master | Existing `Pkg.test()` matrix on Julia 1.10, 1.12 and prerelease; all 37 small OPF definitions and core API regressions |
| Transmission PR | Every PR/push to master | `test-model.jl`: import/physics/sparse derivatives/input validation; `test-fast.jl`: 14 archived original-feasible points, all nine policy activities and reporting/provenance regressions; no optimizer invocation |
| OPF integration | Manual **OPF integration** workflow or weekly default-branch schedule | All 37 small solved regimes; independent PowerModels canonical solves; all ten original PGLib suites; complete receipt checks and compact-fixture derivation |
| Research search | Explicit local command | Multi-start, multi-setting CCOpt sweeps, raw traces and reference searches; complete attempts retained, never a required PR gate |

The PR job still installs the optional environment, including the solver packages
used by the research tools. Its test path invokes no optimizer. Exhaustive tests
include bounded recorder smoke solves and fresh canonical/regime solves, but do
not rerun the full 500-iteration difficulty matrices. Historical failure evidence
is checked numerically; future solver versions need not repeat old failures.
Weekly runs begin after the workflow reaches the repository default branch.
The existing **CI** workflow also has a manual `full_opf` boolean input that
requests this same integration tier on the selected ref. This permits branch
validation through the existing workflow entry point; the new standalone
workflow becomes directly dispatchable after it reaches the default branch.

From the repository root, after developing this checkout in the optional project:

```sh
julia --project=examples/opf/pglib examples/opf/pglib/test-model.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-fast.jl
julia --project=examples/opf/pglib examples/opf/pglib/test-evidence.jl
```

The [evidence guide](hard-cases/README.md#access-and-preservation) explains the
lossless receipt archive, compact derived witness fixture and complete raw-log
bundle. Nothing in these checks asserts global optimality or MPCC stationarity.
