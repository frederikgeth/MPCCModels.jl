using Test, TOML, NLPModels, MPCCModels, Random
include("hard-search.jl")
using .HardCaseSearch
const H=HardCaseSearch
const T=H.TransmissionOPF

@testset "IEEE 300 policy cards, source anchors and matched laws" begin
    specs=T.application_expansion_specs(:policy_matrix; network = :ieee300)
    @test length(specs)==9
    @test length(T.application_policy_cases(; network = :ieee300))==6
    @test length(T.application_expansion_specs(:reserve; network = :ieee300))==3
    @test length(T.application_expansion_specs())==18
    @test length(T.application_policy_cases())==9
    for spec in specs
        data=T.application_expansion_case(spec)
        @test data.network==:ieee300
        @test isempty(data.targets) && isempty(data.network_targets)
        source=H._expansion_source(data, spec)
        @test length(source.point)==T.transmission_layout(data).nvar
        @test source.source_sha256==H._sha(H._expansion_source_file(:ieee300))
        @test source.level in (:nominal, :elevated)
        for laws in (:dispatchable, :vv, :vw, :both)
            d=T.application_expansion_case(spec; laws)
            @test d.pm==data.pm
            @test d.buses==data.buses &&
                  d.generators==data.generators &&
                  d.branches==data.branches
            @test [merge(c, (vv = nothing, vw = nothing)) for c in d.controllers]==[merge(c, (vv = nothing, vw = nothing)) for c in data.controllers]
            @test all(c->isnothing(c.vv)==!(laws in (:vv, :both)), d.controllers)
            @test all(c->isnothing(c.vw)==!(laws in (:vw, :both)), d.controllers)
            @test (T.TransmissionOPFModel(d) isa AbstractMPCCModel)==(laws!=:dispatchable)
        end
        if spec.kind==:coverage
            card=T.application_policy_card(spec.policy; network = :ieee300)
            base=T.application_case(
                card.family;
                network = :ieee300,
                level = card.level,
                parameters = card.parameters,
            )
            @test data.pm==base.pm
            @test [merge(c, (vv = nothing, vw = nothing)) for c in data.controllers]==[merge(c, (vv = nothing, vw = nothing)) for c in base.controllers]
            @test all(
                all(
                    k->data.buses[c.bus].vmin<=k<=data.buses[c.bus].vmax,
                    [c.vv.knots; c.vw.knots],
                ) for c in data.controllers
            )
        end
        mktempdir() do dir
            file=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
            @test H._snapshot(load_case(file))==H._snapshot(data)
        end
    end
    @test_throws ArgumentError T.application_expansion_specs(:fleet; network = :ieee300)
    @test_throws ArgumentError T.application_policy_card(
        :early_absorption_backstop;
        network = :ieee300,
    )
    @test_throws ArgumentError T.application_expansion_case((
        kind = :reserve,
        reserve = :mild,
        network = :ieee118,
    ))
end

@testset "One-sided upper reserve preserves lower bounds, physics and hardware" begin
    base=T.application_case(:reactive_support; network = :ieee300, level = :nominal)
    saved=deepcopy(base.pm)
    previous=base
    for reserve in (:mild, :moderate, :strong)
        card=T.application_reserve_card(reserve)
        data=T.application_reserve_case(reserve)
        @test data.buses==base.buses && data.branches==base.branches
        @test data.controllers==base.controllers
        for (g, b, p) in zip(data.generators, base.generators, previous.generators)
            @test g.qmin==b.qmin
            @test g.qmin<=g.qmax<=p.qmax<=b.qmax
            @test g.qmax-g.qmin≈card.factor*(b.qmax-b.qmin)
            @test merge(g, (qmax = b.qmax,))==b
        end
        @test [g.id for g in data.generators if g.qmin>0]==[5, 44, 45]
        previous=data
    end
    restored=T.application_reserve_case(:mild; factor = 1)
    @test restored.generators==base.generators && restored.pm==base.pm
    @test base.pm==saved
    for factor in (0, -1, 1.1, NaN, Inf)
        @test_throws ArgumentError T.application_reserve_case(:mild; factor)
    end
end

@testset "Independent policy-limit and strict plateau classification" begin
    data=T.application_policy_case(:gentle_watt_cap; network = :ieee300)
    model=T.TransmissionOPFModel(data)
    l=T.transmission_layout(data)
    x=copy(get_x0(model))
    c=first(data.controllers)
    v=sum(c.vw.knots)/2
    x[l.v[c.bus]]=v
    x[l.p[1]]=T.BalancedACOPF.opf_volt_watt(v, c)
    x[l.q[1]]=T.BalancedACOPF.opf_volt_var(v, c)
    cv=T.application_policy_coverage(data, x)
    @test "plant1" in cv["strict_vw_binding"]
    @test !("plant1" in cv["availability_vw_joint"])
    joint=T.transmission_overlay(
        data;
        controllers = [merge(c, (p_available = x[l.p[1]],)); data.controllers[2:end]],
    )
    cj=T.application_policy_coverage(joint, x)
    @test !("plant1" in cj["strict_vw_binding"])
    @test "plant1" in cj["availability_vw_joint"]
    @test !haskey(T.application_coverage(data, x), "strict_vw_binding")
    # This diagnostic point deliberately need not satisfy network balance.
    @test maximum(values(T.transmission_residuals(model, data, x)))>1e-5
    injection=T.application_policy_case(:injection_service; network = :ieee300)
    li=T.transmission_layout(injection)
    xi=copy(get_x0(T.TransmissionOPFModel(injection)))
    xi[li.v[injection.controllers[1].bus]]=injection.controllers[1].vv.knots[1]-1e-4
    @test "plant1" in T.application_policy_coverage(injection, xi)["vv_injection_plateau"]
    for tol in (0, NaN, Inf)
        @test_throws ArgumentError T.application_policy_coverage(
            data,
            x;
            voltage_tolerance = tol,
        )
    end
end

@testset "Policy matrix nonflat physics and sparse derivatives" begin
    rng=MersenneTwister(30025)
    for spec in T.application_expansion_specs(:policy_matrix; network = :ieee300)
        data=T.application_expansion_case(spec)
        model=T.TransmissionOPFModel(data)
        nlp=model.nlp
        l=T.transmission_layout(data)
        x=copy(get_x0(model))
        x[l.v].+=0.01*randn(rng, length(l.v))
        x[l.theta].+=0.01*randn(rng, length(l.theta))
        balance, _=T._physical_balance(data, x, l)
        @test cons(model, x)[l.balance_p]≈real.(balance) atol=1e-9
        @test cons(model, x)[l.balance_q]≈imag.(balance) atol=1e-9
        direction=randn(rng, length(x))
        lambda=randn(rng, get_ncon(model))
        h=1e-6
        @test jprod(nlp, x, direction)≈(
            cons(model, x+h*direction)-cons(model, x-h*direction)
        )/(2*h) rtol=1e-6 atol=1e-5
        laggrad(z) = grad(nlp, z)+jtprod(nlp, z, lambda)
        @test hprod(nlp, x, lambda, direction)≈(
            laggrad(x+h*direction)-laggrad(x-h*direction)
        )/(2*h) rtol=1e-6 atol=1e-4
    end
end

@testset "Prepared references reject mismatches and original infeasibility" begin
    mktempdir() do dir
        data=T.application_case(:reactive_support; network = :ieee300, level = :nominal)
        source=TOML.parsefile(H._expansion_source_file(:ieee300))
        row=only(
            filter(
                r->r["family"]=="reactive_support" && r["level"]=="nominal",
                source["cases"],
            ),
        )
        x=row["witness"]["x"]
        input=H._write(joinpath(dir, "input.toml"), H._snapshot(data))
        case=(data = data, key = "anchor", path = input)
        entry=Dict(
            "case_key"=>case.key,
            "case_sha256"=>H._sha(input),
            "x"=>x,
            "point_sha256"=>H._digest(Dict("x"=>x)),
            "reference_kind"=>"archived_solver_point",
        )
        receipt=H._write(joinpath(dir, "receipt.toml"), Dict("cases"=>[entry]))
        file=H._prepared_point(dir, case, receipt; tolerance = 1e-7)
        @test isfile(file)
        witness=H._expansion_witness(dir, case; tolerance = 1e-7)
        @test witness.point==x && witness.kind=="prevalidated_solver_point"
        @test H._prepared_point(dir, case, receipt; tolerance = 1e-7)==file
        bad=copy(entry)
        bad["case_sha256"]="bad"
        path=H._write(joinpath(dir, "bad.toml"), Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
        bad=copy(entry)
        bad["x"]=zeros(length(x))
        bad["point_sha256"]=H._digest(Dict("x"=>bad["x"]))
        H._write(path, Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
        bad["point_sha256"]="bad"
        H._write(path, Dict("cases"=>[bad]))
        @test_throws ErrorException H._prepared_point(dir, case, path; tolerance = 1e-7)
    end
end
