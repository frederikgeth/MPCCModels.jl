using Test, TOML, NLPModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H = HardCaseSearch
const T = H.TransmissionOPF

@testset "Shared exact bus/knot hinges and physical equivalence" begin
    for count in 1:3, plateau in (:equal, :crossing)
        separate = reduction_case(; controlled = count, plateau)
        shared = reduction_case(; encoding = :shared, controlled = count, plateau)
        a, b = T.transmission_layout(separate), T.transmission_layout(shared)
        @test length(a.r) == 6*count
        @test length(b.r) == 5
        @test a.nvar-b.nvar == 2*(6*count-5)
        @test a.ncon-b.ncon == 6*count-5
        @test shared.pm == separate.pm
        @test shared.controllers == separate.controllers
        @test T.transmission_overlay(shared).hinge_encoding == :shared
        ma, mb = T.TransmissionOPFModel(separate), T.TransmissionOPFModel(shared)
        x = copy(get_x0(ma))
        la = T.transmission_layout(separate)
        x[la.v[95]] = 1.025
        x = T.transmission_start(separate, separate, x)
        y = T.transmission_start(shared, separate, x)
        @test obj(ma, x) == obj(mb, y)
        @test T.transmission_residuals(ma, separate, x) ==
              T.transmission_residuals(mb, shared, y)
        ca, cb = cons(ma, x), cons(mb, y)
        for key in (:angle, :balance_p, :balance_q, :capability, :branch_from, :branch_to)
            @test ca[getproperty(a, key)] ≈ cb[getproperty(b, key)] atol = 1e-12
        end
        for key in (:vv_rows, :vw_rows), i in 1:count
            @test ca[getproperty(a, key)[i]] ≈ cb[getproperty(b, key)[i]] atol = 1e-12
        end
        rng = MersenneTwister(123)
        direction = randn(rng, length(y))
        h = 1e-6
        @test jprod(mb.nlp, y, direction) ≈
              (cons(mb, y+h*direction)-cons(mb, y-h*direction))/(2*h) rtol = 1e-6 atol =
            1e-6
        lambda = randn(rng, get_ncon(mb))
        laggrad(z) = grad(mb.nlp, z)+jtprod(mb.nlp, z, lambda)
        @test hprod(mb.nlp, y, lambda, direction) ≈
              (laggrad(y+h*direction)-laggrad(y-h*direction))/(2*h) rtol = 1e-6 atol = 1e-5
    end
    # Exact bus/knot matching must not merge neighboring knots or separate buses.
    base = transition_case(; offset = 1e-4)
    shared = T.transmission_overlay(base; hinge_encoding = :shared)
    @test length(T.transmission_layout(shared).r) == 6
    cs = copy(base.controllers)
    cs[2] = merge(cs[2], (bus = 94,))
    split = T.transmission_overlay(base; controllers = cs, hinge_encoding = :shared)
    @test length(T.transmission_layout(split).r) == 12
    @test_throws ArgumentError T.transmission_start(
        split,
        shared,
        get_x0(T.TransmissionOPFModel(shared)),
    )
    @test_throws ArgumentError T.transmission_case(:ieee118; hinge_encoding = :unknown)
end

@testset "Reduction hardware, witness, activity and snapshot invariants" begin
    base = transition_case()
    for encoding in (:separate, :shared), controlled in 1:3, plateau in (:equal, :crossing)
        data = reduction_case(; encoding, controlled, plateau)
        @test data.pm == base.pm
        for (i, (c, b)) in enumerate(zip(data.controllers, base.controllers))
            @test Base.structdiff(c, NamedTuple{(:vv, :vw)}((c.vv, c.vw))) ==
                  Base.structdiff(b, NamedTuple{(:vv, :vw)}((b.vv, b.vw)))
            @test isnothing(c.vv) == (i>controlled)
            @test isnothing(c.vw) == (i>controlled)
            if i<=controlled && plateau==:crossing
                @test c.vw.knots == b.vw.knots
                @test c.vw.values ./ c.smax ≈ [0.9, 0.2]
            end
        end
        witness = reduction_witness(data)
        @test witness.metrics["physically_feasible"]
        activity = reduction_activity(data, witness.point)
        @test activity["simultaneous_controllers"] == controlled
        @test abs(activity["q45_upper_margin"]) < 1e-6
        mktempdir() do dir
            path = H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            loaded = load_case(path)
            @test loaded.hinge_encoding == encoding
            @test loaded.controllers == data.controllers
            @test T.transmission_layout(loaded) == T.transmission_layout(data)
        end
    end
    @test_throws ArgumentError reduction_case(; controlled = 0)
    @test_throws ArgumentError reduction_case(; plateau = :bad)
end

@testset "Trace preserves solver outcomes, checksums, replay and safe resume" begin
    mktempdir() do dir
        data = reduction_case(; encoding = :shared, controlled = 1)
        profile = solver_profile(:ratio_one; max_iter = 2, max_wall_time = 15.0)
        a = joinpath(dir, "plain")
        b = joinpath(dir, "traced")
        plain = run_trial(data, nothing, profile, a)
        traced = run_trial(data, nothing, profile, b; trace_every = 1)
        @test plain["status"] == traced["status"]
        @test H._point(a) == H._point(b)
        @test isempty(traced["trace_errors"])
        @test traced["trace_rows"] >= 3
        @test length(readlines(joinpath(b, "trace.tsv"))) == traced["trace_rows"]+1
        @test read_trial(b).request["trace_every"] == 1
        replay = replay_trial(b, joinpath(dir, "replay"))
        @test replay["status"] == traced["status"]
        @test H._point(joinpath(dir, "replay")) == H._point(b)
        open(joinpath(b, "trace.tsv"), "a") do io
            println(io, "corrupt")
        end
        @test_throws ErrorException read_trial(b)
        output = joinpath(dir, "search")
        kwargs = (
            encodings = [:shared],
            counts = [1],
            plateaus = [:crossing],
            seeds = [7],
            max_iter = 1,
            max_wall_time = 10.0,
            reference_iter = 1,
            reference_wall_time = 10.0,
            progress = false,
        )
        rows = run_reduction_search(output; kwargs...)
        @test length(rows) == 3
        @test all(r -> r["witness_available"], rows)
        @test all(r -> isempty(r["trace_errors"]), rows)
        before = Dict(
            r["trial"]=>read(joinpath(output, r["trial"], "result.toml")) for r in rows
        )
        again = run_reduction_search(output; kwargs..., resume = true)
        @test all(
            r -> read(joinpath(output, r["trial"], "result.toml")) == before[r["trial"]],
            again,
        )
        @test_throws ErrorException run_reduction_search(
            output;
            kwargs...,
            resume = true,
            trace_every = 2,
        )
        followup = joinpath(dir, "followup")
        rows = run_reduction_search(
            followup;
            encodings = [:shared],
            counts = [1],
            plateaus = [:equal],
            starts = [:perturbed_witness],
            seeds = [1, 2],
            reference = false,
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        @test length(rows)==2
        @test all(r -> r["start"]=="perturbed_witness", rows)
        @test !isdir(joinpath(followup, "references"))
    end
end
