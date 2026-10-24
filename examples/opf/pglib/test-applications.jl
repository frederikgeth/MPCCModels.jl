using Test, TOML, NLPModels, MPCCModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF

@testset "Application cards, physical grades and matched policies" begin
    @test length(T.application_cases())==9
    canonical=T.transmission_case(:ieee118; targets = [], network_targets = [])
    for spec in T.application_cases()
        family, level=spec.family, spec.level
        card=T.application_card(family)
        data=T.application_case(family; level)
        p=T.application_parameters(family, level)
        @test length(data.controllers)==length(card.sites)
        @test [data.buses[c.bus].id for c in data.controllers]==collect(card.sites)
        @test allunique(c.bus for c in data.controllers)
        @test sum(c.smax for c in data.controllers) ≈ p.penetration*sum(card.ratings)
        @test all(c->c.p_available≈p.availability*c.smax, data.controllers)
        @test data.buses==[
            merge(b, (pd = p.load_scale*b.pd, qd = p.load_scale*b.qd)) for
            b in canonical.buses
        ]
        @test data.generators==[
            merge(g, (qmin = p.q_support*g.qmin, qmax = p.q_support*g.qmax)) for
            g in canonical.generators
        ]
        boundary=Set(data.provenance.export_boundary)
        @test boundary==(family==:export_corridor ? Set([25, 29]) : Set{Int}())
        @test data.branches==[
            b.id in boundary ? merge(b, (rate = p.export_rating*b.rate,)) : b for
            b in canonical.branches
        ]
        @test isempty(data.targets) && isempty(data.network_targets)
        @test data.provenance.application_family==string(family)
        @test data.provenance.parameters==p
        for c in data.controllers, curve in (c.vv, c.vw)
            @test all(k->data.buses[c.bus].vmin<=k<=data.buses[c.bus].vmax, curve.knots)
        end
        for laws in (:dispatchable, :vv, :vw, :both)
            d=T.application_case(family; level, laws)
            @test d.pm==data.pm
            @test d.buses==data.buses &&
                  d.generators==data.generators &&
                  d.branches==data.branches
            for (a, b) in zip(d.controllers, data.controllers)
                @test Base.structdiff(a, (vv = a.vv, vw = a.vw))==Base.structdiff(
                    b,
                    (vv = b.vv, vw = b.vw),
                )
                @test isnothing(a.vv)==!(laws in (:vv, :both))
                @test isnothing(a.vw)==!(laws in (:vw, :both))
            end
            model=T.TransmissionOPFModel(d)
            @test (model isa AbstractMPCCModel)==(laws!=:dispatchable)
        end
        mktempdir() do dir
            file=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            loaded=load_case(file)
            @test H._snapshot(loaded)==H._snapshot(data)
            @test loaded.controllers==data.controllers
        end
    end
    @test_throws ArgumentError T.application_card(:missing)
    @test_throws ArgumentError T.application_case(:export_corridor; level = :missing)
    @test_throws ArgumentError T.application_case(:reactive_support; laws = :missing)
    @test_throws ArgumentError T.application_case(
        :renewable_surplus;
        parameters = (q_support = 0.5,),
    )
    @test_throws ArgumentError T.application_case(
        :reactive_support;
        parameters = (q_support = 0.0,),
    )
    @test_throws ArgumentError T.application_case(
        :renewable_surplus;
        parameters = (availability = 1.1,),
    )
    @test_throws ArgumentError T.application_case(
        :renewable_surplus;
        parameters = (profile_shift = 0.1,),
    )
    @test_throws ArgumentError T.application_case(
        :renewable_surplus;
        parameters = (penetration = NaN,),
    )
end

@testset "Application sparse derivatives and independent coverage" begin
    rng=MersenneTwister(718)
    for family in T.APPLICATION_FAMILIES
        data=T.application_case(family; level = :severe)
        model=T.TransmissionOPFModel(data)
        nlp=model.nlp
        x=copy(get_x0(model))
        l=T.transmission_layout(data)
        d=randn(rng, length(x))
        lambda=randn(rng, get_ncon(model))
        h=1e-6
        @test jprod(nlp, x, d)≈(cons(model, x+h*d)-cons(model, x-h*d))/(2*h) rtol=1e-6 atol=1e-6
        laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
        @test hprod(nlp, x, lambda, d)≈(laggrad(x+h*d)-laggrad(x-h*d))/(2*h) rtol=1e-6 atol=1e-5
        cv=T.application_coverage(data, x)
        @test sum(values(cv["vv_regions"]))==length(data.controllers)
        @test sum(values(cv["vw_regions"]))==length(data.controllers)
        @test cv["curtailed_mw"]≈data.base_mva*sum(
            c.p_available-x[l.p[i]] for (i, c) in enumerate(data.controllers)
        )
        @test cv["load_mw"]≈data.base_mva*sum(b.pd for b in data.buses)
        @test cv["available_mw"]≈data.base_mva*sum(c.p_available for c in data.controllers)
        @test all(
            g->!g.fixed_q || !(g.id in cv["network_tight"]["generator_q_lower"]),
            T.transmission_coverage(data, x).network.generators,
        )
        @test_throws ArgumentError T.application_coverage(data, x; tolerance = 0)
    end
end

@testset "Ordinary matched NLPs and failure-retaining application matrix" begin
    mktempdir() do dir
        data=T.application_case(:renewable_surplus; laws = :dispatchable)
        path=joinpath(dir, "nlp")
        result=run_trial(data, nothing, solver_profile(:ratio_one; max_iter = 1), path)
        @test result["classification"]!="exception"
        @test read_trial(path).request["ncc"]==0
        @test !haskey(result, "resolved_relaxation")
        out=joinpath(dir, "search")
        kw=(
            families = [:export_corridor],
            levels = [:nominal],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows=run_application_search(out; kw...)
        @test length(rows)==2
        @test all(r->r["family"]=="export_corridor", rows)
        @test any(r->r["classification"]=="unavailable_start", rows)
        before=Dict(
            r["trial"]=>read(joinpath(out, r["trial"], "result.toml")) for r in rows
        )
        again=run_application_search(out; kw..., resume = true)
        @test length(again)==2
        @test all(
            r->read(joinpath(out, r["trial"], "result.toml"))==before[r["trial"]],
            again,
        )
        @test_throws ErrorException run_application_search(
            out;
            kw...,
            resume = true,
            seeds = [1],
        )
        summary=TOML.parsefile(joinpath(out, "summary.toml"))
        @test length(summary["cases"])==1
        @test haskey(first(values(summary["cases"])), "counterfactual_result")
    end
end
