using Test, TOML
include("hard-search.jl")
using .HardCaseSearch

@testset "Hard-case inputs and controlled profiles" begin
    base = capability_case(1.0)
    changed = capability_case(0.82)
    @test changed.buses == base.buses
    @test changed.branches == base.branches
    @test changed.generators == base.generators
    for i in 1:3
        c, b = changed.controllers[i], base.controllers[i]
        @test c.p_available == b.p_available
        @test c.vv == b.vv && c.vw == b.vw
        @test c.qmin == b.qmin && c.qmax == b.qmax
        @test c.smax == (i == 3 ? 0.82*b.smax : b.smax)
    end
    current = solver_profile(:current)
    for (name, field, value) in (
        (:looser_inner, :tol, 1e-8),
        (:ratio_one, :sigma_mu_ratio, 1.0),
        (:higher_floor, :sigma_min, 1e-8),
    )
        profile = solver_profile(name)
        @test getproperty(profile, field) == value
        @test all(
            k -> getproperty(profile, k) == getproperty(current, k),
            setdiff(collect(keys(current)), [:name, field]),
        )
    end
    @test_throws ArgumentError capability_case(0)
    @test_throws ArgumentError solver_profile(:missing)
    @test_throws ArgumentError solver_profile(:current; max_iter = 0)
end

@testset "Recorder retains exceptions, failed points and unavailable verification" begin
    mktempdir() do dir
        data = capability_case(0.82)
        profile = solver_profile(:current; max_iter = 1)
        throwing(model, config; mask = nothing) = error("injected solver exception")
        failure(model, config; mask = nothing) = Dict(
            "status"=>"TEST_LIMIT",
            "solver_success"=>false,
            "iterations"=>1,
            "solution"=>copy(HardCaseSearch.get_x0(model)),
            "point_source"=>"returned_solution",
        )
        exception_dir = joinpath(dir, "exception")
        exception = run_trial(data, nothing, profile, exception_dir; executor = throwing)
        @test exception["classification"] == "exception"
        @test occursin("injected solver exception", exception["exception"])
        @test exception["state"] == "complete"
        @test !exception["has_solution"]
        @test isfile(joinpath(exception_dir, "solver.log"))
        @test isnothing(verified_point(exception_dir))
        failed_dir = joinpath(dir, "failure")
        failed = run_trial(data, nothing, profile, failed_dir; executor = failure)
        @test failed["classification"] == "solver_failure"
        @test failed["has_solution"]
        @test !failed["physically_feasible"]
        @test isnothing(verified_point(failed_dir))
        saved = read_trial(failed_dir)
        @test saved.result["status"] == "TEST_LIMIT"
        @test saved.request["start_label"] == "custom"
        @test saved.request["profile"]["max_iter"] == 1
        restored = load_case(
            joinpath(failed_dir, "input.toml");
            expected_sha = saved.request["case_sha256"],
        )
        @test restored.buses == data.buses
        @test restored.branches == data.branches
        @test restored.controllers == data.controllers
        @test_throws ArgumentError run_trial(
            data,
            nothing,
            profile,
            failed_dir;
            executor = failure,
        )
        # Unknown witness status is not promoted to an infeasibility claim.
        @test !haskey(failed, "infeasible_problem")
        # Interrupted markers survive; resume creates a new attempt.
        marker = copy(saved.result)
        marker["state"] = "running"
        HardCaseSearch._write(joinpath(failed_dir, "result.toml"), marker)
        @test read_trial(failed_dir).result["state"] == "running"
        parent = joinpath(dir, "attempts")
        mkpath(joinpath(parent, "case-attempt-001"))
        next, done = HardCaseSearch._attempt(parent, "case"; resume = true)
        @test endswith(next, "case-attempt-002") && !done
        # Hashes are checked before replay or witness reuse.
        open(joinpath(failed_dir, "solution.toml"), "a") do io
            println(io, "# changed bytes")
        end
        @test_throws ErrorException read_trial(failed_dir)
    end
end

@testset "Small real search continues and safely resumes" begin
    mktempdir() do directory
        output = joinpath(directory, "search")
        kwargs = (
            capabilities = [0.82],
            starts = [:flat, :witness],
            profiles = [:current],
            max_iter = 1,
            max_wall_time = 10.0,
            warmup = false,
            progress = false,
        )
        rows = run_search(output; kwargs...)
        @test length(rows) == 2
        @test all(
            r -> r["classification"] in (
                "success",
                "solver_failure",
                "physical_violation",
                "exception",
                "unavailable_start",
            ),
            rows,
        )
        @test isfile(joinpath(output, "cases.tsv"))
        @test isfile(joinpath(output, "environment", "Manifest.toml"))
        @test isfile(
            joinpath(output, "source", "examples", "opf", "pglib", "hard-search.jl"),
        )
        @test_throws ArgumentError run_search(output; kwargs...)
        files = Dict(
            r["trial"]=>read(joinpath(output, r["trial"], "result.toml"), String) for
            r in rows
        )
        again = run_search(output; kwargs..., resume = true)
        @test length(again) == 2
        @test all(
            r ->
                read(joinpath(output, r["trial"], "result.toml"), String) ==
                files[r["trial"]],
            again,
        )
        @test_throws ErrorException run_search(output; kwargs..., resume = true, seed = 1)
        raw = only(filter(r -> r["start"] == "flat", rows))
        replay = replay_trial(joinpath(output, raw["trial"]), joinpath(directory, "replay"))
        @test replay["state"] == "complete"
        @test read_trial(joinpath(directory, "replay")).request["profile"]["max_iter"] == 1
        missing_start = only(filter(r -> r["start"] == "witness", rows))
        if missing_start["classification"] == "unavailable_start"
            @test_throws ErrorException replay_trial(
                joinpath(output, missing_start["trial"]),
                joinpath(directory, "no-start"),
            )
        end
    end
end
