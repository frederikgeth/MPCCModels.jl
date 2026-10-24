using Test, TOML, NLPModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF

@testset "Operating policy definitions and matched hardware" begin
    @test length(T.application_policy_cases())==9
    for spec in T.application_policy_cases()
        card=T.application_policy_card(spec.policy)
        base=T.application_case(
            card.family;
            level = card.level,
            parameters = card.parameters,
        )
        data=T.application_policy_case(spec.policy)
        @test data.pm==base.pm
        @test data.buses==base.buses &&
              data.generators==base.generators &&
              data.branches==base.branches
        @test data.provenance.policy_variant==string(spec.policy)
        @test isempty(data.targets) && isempty(data.network_targets)
        for laws in (:both, :vv, :vw, :dispatchable)
            variant=T.application_policy_case(spec.policy; laws)
            @test variant.pm==data.pm
            for (c, b) in zip(variant.controllers, base.controllers)
                @test Base.structdiff(c, (vv = c.vv, vw = c.vw))==Base.structdiff(
                    b,
                    (vv = b.vv, vw = b.vw),
                )
                @test isnothing(c.vv)==!(laws in (:vv, :both))
                @test isnothing(c.vw)==!(laws in (:vw, :both))
                for curve in (c.vv, c.vw)
                    isnothing(curve) && continue
                    @test all(
                        k->variant.buses[c.bus].vmin<=k<=variant.buses[c.bus].vmax,
                        curve.knots,
                    )
                end
            end
        end
        mktempdir() do dir
            file=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            @test H._snapshot(load_case(file))==H._snapshot(data)
        end
    end
    @test_throws ArgumentError T.application_policy_case(:unknown)
    @test_throws ArgumentError T.application_policy_case(
        :absorption_service;
        laws = :unknown,
    )
end

@testset "Fixed-total heterogeneous populations and distinct-site geography" begin
    base=T.application_case(:reactive_support; level = :elevated)
    source=TOML.parsefile(H.EXPANSION_SOURCE)
    row=only(
        filter(
            r->r["family"]=="reactive_support" && r["level"]=="elevated",
            source["cases"],
        ),
    )
    x=row["witness"]["x"]
    base_layout=T.transmission_layout(base)
    for placement in (:same_sites, :clustered, :dispersed), count in (6, 12, 24)
        data=T.application_fleet_case(; count, placement)
        @test length(data.controllers)==count
        @test data.pm==base.pm
        @test data.buses==base.buses &&
              data.generators==base.generators &&
              data.branches==base.branches
        @test sum(c.smax for c in data.controllers)≈sum(c.smax for c in base.controllers)
        @test sum(c.p_available for c in data.controllers)≈sum(
            c.p_available for c in base.controllers
        )
        @test data.provenance.fleet_copies==count÷6
        for i in 1:6
            selected=findall(==(i), data.provenance.fleet_templates)
            c=base.controllers[i]
            @test sum(data.controllers[j].smax for j in selected)≈c.smax
            @test sum(data.controllers[j].p_available for j in selected)≈c.p_available
            @test sum(data.controllers[j].qmin for j in selected)≈c.qmin
            @test sum(data.controllers[j].qmax for j in selected)≈c.qmax
            for j in selected
                d=data.controllers[j]
                @test d.vv.knots==c.vv.knots && d.vw.knots==c.vw.knots
                @test d.vv.values/d.smax≈c.vv.values/c.smax
                @test d.vw.values/d.smax≈c.vw.values/c.smax
            end
        end
        y=T.application_fleet_start(data, base, x)
        l=T.transmission_layout(data)
        @test length(y)==l.nvar
        @test y[l.v]==x[base_layout.v] && y[l.pg]==x[base_layout.pg]
        @test sum(y[l.p])≈sum(x[base_layout.p])
        @test sum(y[l.q])≈sum(x[base_layout.q])
        model=T.TransmissionOPFModel(data)
        @test obj(model, y)≈obj(T.TransmissionOPFModel(base), x) atol=1e-8
        if placement==:same_sites
            @test length(unique(c.bus for c in data.controllers))==6
            @test maximum(values(T.transmission_residuals(model, data, y)))<=1e-7
        else
            @test allunique(c.bus for c in data.controllers)
            @test !(data.reference_bus in [c.bus for c in data.controllers])
        end
        dispatchable=T.application_fleet_case(; count, placement, laws = :dispatchable)
        @test dispatchable.pm==data.pm
        @test all(c->isnothing(c.vv) && isnothing(c.vw), dispatchable.controllers)
    end
    for placement in (:clustered, :dispersed)
        sites6=T.application_fleet_case(; count = 6, placement).provenance.fleet_sites
        sites12=T.application_fleet_case(; count = 12, placement).provenance.fleet_sites
        sites24=T.application_fleet_case(; count = 24, placement).provenance.fleet_sites
        @test sites6==sites12[1:6]==sites24[1:6]
        @test sites12==sites24[1:12]
    end
    @test length(T.application_expansion_specs(:fleet))==9
    @test length(T.application_expansion_specs())==18
    @test_throws ArgumentError T.application_fleet_case(; count = 7)
    @test_throws ArgumentError T.application_fleet_case(;
        count = 120,
        placement = :dispersed,
    )
    @test_throws ArgumentError T.application_fleet_case(; placement = :unknown)
end

@testset "Expansion derivatives, record integrity and safe resume" begin
    rng=MersenneTwister(805)
    for data in (
        T.application_policy_case(:injection_service),
        T.application_fleet_case(; count = 24, placement = :dispersed),
    )
        model=T.TransmissionOPFModel(data)
        nlp=model.nlp
        x=copy(get_x0(model))
        d=randn(rng, length(x))
        lambda=randn(rng, get_ncon(model))
        h=1e-6
        @test jprod(nlp, x, d)≈(cons(model, x+h*d)-cons(model, x-h*d))/(2*h) rtol=1e-6 atol=1e-6
        laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
        @test hprod(nlp, x, lambda, d)≈(laggrad(x+h*d)-laggrad(x-h*d))/(2*h) rtol=1e-6 atol=1e-5
    end
    mktempdir() do dir
        out=joinpath(dir, "search")
        kw=(
            specs = [(kind = :coverage, policy = :absorption_service)],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        rows=run_expansion_search(out; kw...)
        @test length(rows)==2
        summary=TOML.parsefile(joinpath(out, "summary.toml"))
        @test length(summary["cases"])==1
        info=first(values(summary["cases"]))
        @test length(info["references"])>=1
        saved=Dict(r["trial"]=>read(joinpath(out, r["trial"], "result.toml")) for r in rows)
        again=run_expansion_search(out; kw..., resume = true)
        @test length(again)==2
        @test all(
            r->read(joinpath(out, r["trial"], "result.toml"))==saved[r["trial"]],
            again,
        )
        @test_throws ErrorException run_expansion_search(
            out;
            kw...,
            resume = true,
            max_iter = 2,
        )
        fleet_out=joinpath(dir, "fleet")
        fleet_spec=(
            kind = :fleet,
            family = :reactive_support,
            level = :elevated,
            count = 12,
            placement = :same_sites,
        )
        fleet_rows=run_expansion_search(
            fleet_out;
            specs = [fleet_spec],
            profiles = [:ratio_one],
            max_iter = 1,
            max_wall_time = 10.0,
            progress = false,
        )
        @test length(fleet_rows)==2
        @test all(r->r["witness_available"], fleet_rows)
        fleet_case=first(
            values(TOML.parsefile(joinpath(fleet_out, "summary.toml"))["cases"]),
        )
        @test fleet_case["reference_kind"]=="physical_transfer"
        @test !any(r->r["classification"]=="unavailable_start", fleet_rows)
    end
end
