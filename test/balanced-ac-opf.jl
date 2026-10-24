using LinearAlgebra

include(joinpath(@__DIR__, "..", "examples", "opf", "balanced-ac-opf.jl"))
using .BalancedACOPF

# Independent complex-voltage evaluation, rather than the polar equations used
# by the example. Power is positive from each bus into the line.
function opf_test_powers(data, x)
    v0 = complex(data.source_voltage)
    v1 = x[1] * cis(x[2])
    current = (v0 - v1) / complex(data.resistance, data.reactance)
    return v0 * conj(current), -v1 * conj(current), current
end

function opf_test_jacobian(f, x; step = 1e-5)
    columns = map(eachindex(x)) do i
        xp, xm = copy(x), copy(x)
        xp[i] += step
        xm[i] -= step
        return (f(xp) - f(xm)) / (2 * step)
    end
    return hcat(columns...)
end

@testset "Balanced AC OPF" begin
    @testset "Case reference points ($T)" for T in (Float64, Float32)
        tol = T == Float64 ? 1e-11 : 2e-5
        @test length(unique(balanced_ac_opf_cases())) == 12
        for name in balanced_ac_opf_cases()
            data = balanced_ac_opf_case(name, T)
            mpcc = BalancedACOPFModel(T; case = name)
            x = balanced_ac_opf_reference(data)
            @test eltype(x) == T
            @test get_nvar(mpcc) == 18
            @test get_ncon(mpcc) == 15
            @test get_nlin(mpcc) == 8
            @test get_nnln(mpcc) == 7
            @test get_ncc(mpcc) == 6
            @test is_vertical(mpcc)
            @test get_ind_cc1(mpcc) == collect(7:12)
            @test get_ind_cc2(mpcc) == collect(13:18)
            @test all(get_lvar(mpcc)[7:18] .== 0)
            @test maximum(values(opf_residuals(mpcc, x, data))) < tol
            @test comp_residual_product(mpcc, x) == 0
            @test obj(mpcc, x) == x[3]
            @test get_x0(mpcc) != x
            @test all(get_lvar(mpcc) .<= get_x0(mpcc) .<= get_uvar(mpcc))

            s0, s1, current = opf_test_powers(data, x)
            @test complex(x[3], x[4]) ≈ s0 atol = tol
            @test complex(x[5] - data.pload, x[6] - data.qload) ≈ s1 atol = tol
            @test real(s0 + s1) ≈ data.resistance * abs2(current) atol = tol
            @test imag(s0 + s1) ≈ data.reactance * abs2(current) atol = tol
            @test x[5] ≈ min(data.p_available, opf_volt_watt(x[1], data)) atol = tol

            # Numerical equality of the target voltage and its knot makes the
            # corresponding pair biactive, including at the two saturation ends.
            knots = vcat(data.vv_breakpoints, data.vw_breakpoints)
            for k in findall(==(data.reference_voltage), knots)
                @test x[6+k] == x[12+k] == 0
            end
        end
    end

    @testset "Physical control regimes" begin
        regimes = (
            (:low_voltage_saturation, 0.3, 0.8),
            (:reactive_injection, 0.15, 0.8),
            (:deadband, 0.0, 0.8),
            (:reactive_absorption, -0.15, 0.8),
            (:curtailment, -0.3, 0.68),
            (:high_voltage_saturation, -0.3, 0.2),
        )
        for (name, q, p) in regimes
            data = balanced_ac_opf_case(name)
            x = balanced_ac_opf_reference(data)
            @test x[5] ≈ p
            @test x[6] ≈ q atol = 1e-14
        end
        @test_throws ArgumentError balanced_ac_opf_case(:unknown)
        @test_throws ArgumentError BalancedACOPFModel(; case = :unknown)
        @test_throws DimensionMismatch BalancedACOPFModel(; x0 = zeros(17))
        @test_throws ArgumentError BalancedACOPFModel(; x0 = fill(NaN, 18))
        data = balanced_ac_opf_case(:curtailment)
        x = balanced_ac_opf_reference(data)
        mpcc = BalancedACOPFModel(; x0 = x)
        @test get_x0(mpcc) == x
        @test get_x0(mpcc) !== x
        @test_throws DimensionMismatch opf_residuals(mpcc, zeros(17), data)
    end

    @testset "Hinges at and on both sides of every breakpoint" begin
        data = balanced_ac_opf_case(:curtailment)
        mpcc = BalancedACOPFModel()
        knots = vcat(data.vv_breakpoints, data.vw_breakpoints)
        voltages = vcat(
            [data.vmin, data.vmax],
            [k + delta for k in knots for delta in (-1e-5, 0.0, 1e-5)],
        )
        for v in voltages
            # These isolate the controller equations; AC balance is not required.
            x = balanced_ac_opf_reference(data)
            x[1] = v
            x[5] = opf_volt_watt(v, data)
            x[6] = opf_volt_var(v, data)
            x[7:12] .= max.(v .- knots, 0)
            x[13:18] .= max.(knots .- v, 0)
            c = cons(mpcc, x)
            @test c[1:6] ≈ -knots
            @test c[7] ≈ data.qmax atol = 1e-13
            @test c[8] ≈ data.pcap_max atol = 1e-13
            @test comp_residual(mpcc, x) == 0
            @test all(x[7:18] .>= 0)
        end
    end

    @testset "Volt-watt is a cap, not an equality" begin
        data = balanced_ac_opf_case(:curtailment)
        mpcc = BalancedACOPFModel()
        # Construct another high-voltage power-flow solution with less active
        # output. Volt-var is on its lower plateau here. The larger root of this
        # quadratic is the high-voltage solution for fixed receiving-end power.
        p, q = 0.3, data.qmin
        pnet, qnet = p - data.pload, q - data.qload
        a = data.source_voltage^2 + 2 * (data.resistance * pnet + data.reactance * qnet)
        b = (data.resistance^2 + data.reactance^2) * (pnet^2 + qnet^2)
        v = sqrt((a + sqrt(a^2 - 4 * b)) / 2)
        v0 = v - complex(data.resistance, data.reactance) * complex(pnet, -qnet) / v
        x = balanced_ac_opf_reference(data)
        x[1:2] .= [v, -angle(v0)]
        s0, _, _ = opf_test_powers(data, x)
        x[3:6] .= [real(s0), imag(s0), p, q]
        knots = vcat(data.vv_breakpoints, data.vw_breakpoints)
        x[7:12] .= max.(v .- knots, 0)
        x[13:18] .= max.(knots .- v, 0)
        @test data.vv_breakpoints[end] < v < data.vw_breakpoints[end]
        @test p < min(data.p_available, opf_volt_watt(v, data)) - 0.1
        @test cons(mpcc, x)[8] < get_ucon(mpcc)[8] - 0.1
        @test maximum(values(opf_residuals(mpcc, x, data))) < 1e-11
    end

    @testset "Diagnostics reject physical and complementarity violations" begin
        data = balanced_ac_opf_case(:curtailment)
        mpcc = BalancedACOPFModel()
        reference = balanced_ac_opf_reference(data)
        x = copy(reference)
        x[3] += 0.1
        @test opf_residuals(mpcc, x, data).constraints ≈ 0.1
        @test comp_residual(mpcc, x) == 0

        x = copy(reference)
        x[5] = 1.1
        @test cons(mpcc, x)[13] > get_ucon(mpcc)[13]
        @test opf_residuals(mpcc, x, data).bounds > 0
        @test opf_residuals(mpcc, x, data).volt_watt > 0
        x = copy(reference)
        x[1] = 0.9
        @test any(cons(mpcc, x)[14:15] .> get_ucon(mpcc)[14:15])

        # Increasing both members preserves r - s - v = -knot. Adjust q to
        # preserve its linear link too: only complementarity gives an exact curve.
        x = copy(reference)
        x[7] += 0.002
        x[13] += 0.002
        x[6] -= data.qmax / (data.vv_breakpoints[2] - data.vv_breakpoints[1]) * 0.002
        @test cons(mpcc, x)[1:7] ≈ get_ucon(mpcc)[1:7]
        @test opf_residuals(mpcc, x, data).complementarity ≈ 0.002
        @test opf_residuals(mpcc, x, data).volt_var ≈ 0.015

        x = copy(reference)
        x[12] = -1e-4
        @test opf_residuals(mpcc, x, data).bounds ≈ 1e-4
        for value in (NaN, Inf)
            x = copy(reference)
            x[1] = value
            @test all(isinf, values(opf_residuals(mpcc, x, data)))
        end
    end

    @testset "AC equations and derivatives away from the start" begin
        data = balanced_ac_opf_case(:curtailment)
        mpcc = BalancedACOPFModel()
        x = [
            1.035,
            0.08,
            -0.2,
            0.3,
            0.45,
            -0.08,
            0.01,
            0.02,
            0.03,
            0.04,
            0.05,
            0.06,
            0.06,
            0.05,
            0.04,
            0.03,
            0.02,
            0.01,
        ]
        c = cons(mpcc, x)
        s0, s1, _ = opf_test_powers(data, x)
        @test c[9:12] ≈ [
            x[3] - real(s0),
            x[4] - imag(s0),
            x[5] - data.pload - real(s1),
            x[6] - data.qload - imag(s1),
        ]
        @test c[13:15] ≈ [x[5]^2 + x[6]^2, abs2(s0), abs2(s1)]

        gradient_fd = vec(opf_test_jacobian(z -> [obj(mpcc, z)], x))
        jacobian_fd = opf_test_jacobian(z -> cons(mpcc, z), x)
        @test grad(mpcc, x) ≈ gradient_fd atol = 1e-9
        @test Matrix(jac(mpcc, x)) ≈ jacobian_fd rtol = 1e-7 atol = 1e-7
        weights = cos.(collect(1:get_ncon(mpcc)))
        lag_grad(z) = 0.7 * grad(mpcc, z) + jac(mpcc, z)' * weights
        hessian_fd = opf_test_jacobian(lag_grad, x)
        @test Matrix(hess(mpcc, x, weights; obj_weight = 0.7)) ≈ hessian_fd rtol = 1e-7 atol =
            1e-7
        @test Matrix(jac_comp_left(mpcc, x)) ≈ opf_test_jacobian(z -> comp_left(mpcc, z), x) atol =
            1e-9
        @test Matrix(jac_comp_right(mpcc, x)) ≈
              opf_test_jacobian(z -> comp_right(mpcc, z), x) atol = 1e-9
    end
end
