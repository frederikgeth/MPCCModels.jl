module BalancedACOPF

using ADNLPModels, MPCCModels, NLPModels

export BalancedACOPFModel, balanced_ac_opf_cases, balanced_ac_opf_case
export balanced_ac_opf_reference, opf_volt_var, opf_volt_watt, opf_residuals

"""
    balanced_ac_opf_cases()

Names of the synthetic operating cases, including all six control breakpoints.
Both controls are enabled in every case. See `balanced_ac_opf_case` for the data.
"""
function balanced_ac_opf_cases()
    return (
        :low_voltage_saturation,
        :reactive_injection,
        :deadband,
        :reactive_absorption,
        :curtailment,
        :high_voltage_saturation,
        :vv_lower_knee,
        :vv_deadband_lower,
        :vv_deadband_upper,
        :vv_upper_knee,
        :vw_upper_knee,
        :vw_lower_knee,
    )
end

"""
    opf_volt_var(v, data)

Direct piecewise evaluation of reactive injection in per unit: positive at low
voltage, zero in the deadband, and negative at high voltage. This evaluator is
for reference points and diagnostics; the NLP uses smooth hinge equations.
"""
function opf_volt_var(v, data)
    v1, v2, v3, v4 = data.vv_breakpoints
    qmax, qmin = data.qmax, data.qmin
    return qmax * clamp((v2 - v) / (v2 - v1), zero(v), one(v)) +
           qmin * clamp((v - v3) / (v4 - v3), zero(v), one(v))
end

"""
    opf_volt_watt(v, data)

Direct piecewise evaluation of the active-power cap in per unit. The cap is
constant outside its two breakpoints; available power is a separate bound.
"""
function opf_volt_watt(v, data)
    v1, v2 = data.vw_breakpoints
    return data.pcap_max +
           (data.pcap_min - data.pcap_max) * clamp((v - v1) / (v2 - v1), zero(v), one(v))
end

# Directed power injection into a series branch; b is the negative susceptance
# of 1 / (r + im * x). The reference bus has angle zero.
function _opf_branch_power(vf, vt, delta, g, b)
    p = g * vf^2 - vf * vt * (g * cos(delta) + b * sin(delta))
    q = -b * vf^2 - vf * vt * (g * sin(delta) - b * cos(delta))
    return p, q
end

"""
    balanced_ac_opf_case(name::Symbol, T::Type = Float64)

Return the per-unit data for a balanced two-bus AC network. A fixed-voltage
source feeds a PQ load and one inverter through a series impedance. Every case
has both volt-var and volt-watt controls. The source voltage is constructed so
that `balanced_ac_opf_reference(data)` is feasible at `reference_voltage`.
The reference is a feasibility witness, not an optimality certificate.

Power uses a common three-phase system base, and voltage uses the corresponding
positive-sequence per-unit base. There are no shunts, taps, or phase shifts.
The data are synthetic; the curves do not claim compliance with a grid code.
"""
function balanced_ac_opf_case(name::Symbol, ::Type{T} = Float64) where {T<:AbstractFloat}
    names = balanced_ac_opf_cases()
    voltages = T[0.92, 0.96, 1.00, 1.04, 1.09, 1.14, 0.94, 0.98, 1.02, 1.06, 1.07, 1.12]
    index = findfirst(==(name), names)
    isnothing(index) && throw(ArgumentError("unknown balanced AC OPF case: $name"))
    data = (
        name = name,
        reference_voltage = voltages[index],
        resistance = T(0.02),
        reactance = T(0.08),
        pload = T(0.4),
        qload = T(0.1),
        p_available = T(0.8),
        smax = T(1),
        branch_rating = T(1.5),
        vmin = T(0.88),
        vmax = T(1.18),
        angle_max = T(0.3),
        source_limit = T(2),
        vv_breakpoints = T[0.94, 0.98, 1.02, 1.06],
        vw_breakpoints = T[1.07, 1.12],
        qmax = T(0.3),
        qmin = T(-0.3),
        pcap_max = T(1),
        pcap_min = T(0.2),
    )

    # In a frame where the inverter voltage is real, V0 = v - z * conj(S1) / v.
    # Rotating by -angle(V0) then puts the source on the real axis.
    v = data.reference_voltage
    pnet = min(data.p_available, opf_volt_watt(v, data)) - data.pload
    qnet = opf_volt_var(v, data) - data.qload
    vr0 = v - (data.resistance * pnet + data.reactance * qnet) / v
    vi0 = -(data.reactance * pnet - data.resistance * qnet) / v
    return merge(
        data,
        (source_voltage = hypot(vr0, vi0), reference_angle = -atan(vi0, vr0)),
    )
end

# Constant extrapolation of a continuous piecewise-linear curve:
# baseline + sum(weights[k] * max(v - knots[k], 0)).
function _opf_hinges(data)
    knots = vcat(data.vv_breakpoints, data.vw_breakpoints)
    v1, v2, v3, v4 = data.vv_breakpoints
    w1, w2 = data.vw_breakpoints
    a = -data.qmax / (v2 - v1)
    b = data.qmin / (v4 - v3)
    c = (data.pcap_min - data.pcap_max) / (w2 - w1)
    return knots, [a, -a, b, -b], [c, -c]
end

"""
    balanced_ac_opf_reference(data)

A feasible reference vector in the model's order
`[v, theta, pg, qg, p, q, r[1:6]..., s[1:6]...]`.
The first four hinges encode volt-var; the last two encode volt-watt.
"""
function balanced_ac_opf_reference(data)
    v, theta = data.reference_voltage, data.reference_angle
    denominator = data.resistance^2 + data.reactance^2
    g, b = data.resistance / denominator, -data.reactance / denominator
    pg, qg = _opf_branch_power(data.source_voltage, v, -theta, g, b)
    p = min(data.p_available, opf_volt_watt(v, data))
    q = opf_volt_var(v, data)
    knots, _, _ = _opf_hinges(data)
    r = max.(v .- knots, zero(v))
    s = max.(knots .- v, zero(v))
    return vcat([v, theta, pg, qg, p, q], r, s)
end

"""
    BalancedACOPFModel(T::Type = Float64; case = :curtailment, x0 = nothing)

Construct a vertical-form `MPCCModel` for a balanced two-bus AC OPF:

    min pg
    s.t. AC power balance at both buses
         q = volt_var(v)
         0 <= p <= p_available, p <= volt_watt(v)
         p^2 + q^2 <= smax^2
         apparent-power limits at both ends of the line
         vmin <= v <= vmax, -angle_max <= theta <= angle_max

Each `max(v - knot, 0)` is replaced by `r - s - v = -knot` and
`0 <= r ⟂ s >= 0`, ported from BMOPFTools.jl PR #383. No product equalities
or nonsmooth functions are included in the underlying NLP. The inverter
capability circle applies together with the fixed reactive-power law; there is
no extra clipping or priority policy. The source may import or export power.

There are 18 variables in the order documented by `balanced_ac_opf_reference`,
six complementarity pairs, eight linear constraints, and seven nonlinear
constraints. The default start is a flat voltage profile, distinct from the
feasible reference. Supply `x0` to override it.
"""
function BalancedACOPFModel(
    ::Type{T} = Float64;
    case::Symbol = :curtailment,
    x0::Union{Nothing,AbstractVector} = nothing,
) where {T<:AbstractFloat}
    data = balanced_ac_opf_case(case, T)
    knots, vv_weights, vw_weights = _opf_hinges(data)
    ncc = length(knots)
    ind_vcc1 = collect(7:12)
    ind_vcc2 = collect(13:18)
    if isnothing(x0)
        v = data.source_voltage
        p = min(data.p_available, opf_volt_watt(v, data)) / 2
        x0 = vcat(
            T[v, 0, 0, 0, p, opf_volt_var(v, data)],
            max.(v .- knots, zero(T)),
            max.(knots .- v, zero(T)),
        )
    else
        length(x0) == 18 || throw(DimensionMismatch("expected 18 starting values"))
        x0 = T.(x0)
        all(isfinite, x0) ||
            throw(ArgumentError("converted starting values must be finite"))
    end
    lvar = vcat(
        T[data.vmin, -data.angle_max, -data.source_limit, -data.source_limit, 0, data.qmin],
        zeros(T, 2 * ncc),
    )
    uvar = vcat(
        T[
            data.vmax,
            data.angle_max,
            data.source_limit,
            data.source_limit,
            data.p_available,
            data.qmax,
        ],
        fill(T(Inf), 2 * ncc),
    )

    # The first six rows are r - s - v = -knot. Rows 7 and 8 are the
    # volt-var equality and volt-watt upper bound, respectively.
    rows = vcat(collect(1:ncc), collect(1:ncc), collect(1:ncc), fill(7, 5), fill(8, 3))
    cols = vcat(fill(1, ncc), ind_vcc1, ind_vcc2, [6; ind_vcc1[1:4]], [5; ind_vcc1[5:6]])
    vals = vcat(
        -ones(T, ncc),
        ones(T, ncc),
        -ones(T, ncc),
        [one(T); -vv_weights],
        [one(T); -vw_weights],
    )

    denominator = data.resistance^2 + data.reactance^2
    g, b = data.resistance / denominator, -data.reactance / denominator
    f(x) = x[3]
    function c(x)
        v, theta, pg, qg, p, q = x[1:6]
        p01, q01 = _opf_branch_power(data.source_voltage, v, -theta, g, b)
        p10, q10 = _opf_branch_power(v, data.source_voltage, theta, g, b)
        return [
            pg - p01,
            qg - q01,
            p - data.pload - p10,
            q - data.qload - q10,
            p^2 + q^2,
            p01^2 + q01^2,
            p10^2 + q10^2,
        ]
    end
    lcon = vcat(-knots, T[data.qmax, -Inf], zeros(T, 4), fill(T(-Inf), 3))
    ucon = vcat(
        -knots,
        T[data.qmax, data.pcap_max],
        zeros(T, 4),
        T[data.smax^2, data.branch_rating^2, data.branch_rating^2],
    )
    nlp = ADNLPModel(
        f,
        x0,
        lvar,
        uvar,
        rows,
        cols,
        vals,
        c,
        lcon,
        ucon;
        name = "Balanced AC OPF ($case)",
    )
    return MPCCModel(nlp, ind_vcc1, ind_vcc2)
end

"""
    opf_residuals(mpcc, x, data)

Report maximum NLP constraint, variable-bound, and complementarity violations,
plus direct volt-var error and volt-watt cap violation, all in per unit.
The data must describe the same case as `mpcc`. A point is feasible only when
all five entries are small. A nonfinite point returns infinite residuals.
"""
function opf_residuals(mpcc, x::AbstractVector, data)
    length(x) == get_nvar(mpcc) || throw(DimensionMismatch("incorrect OPF point length"))
    if !all(isfinite, x)
        return (
            constraints = Inf,
            bounds = Inf,
            complementarity = Inf,
            volt_var = Inf,
            volt_watt = Inf,
        )
    end
    cx = cons(mpcc, x)
    constraints =
        max(zero(eltype(x)), maximum(get_lcon(mpcc) .- cx), maximum(cx .- get_ucon(mpcc)))
    bounds =
        max(zero(eltype(x)), maximum(get_lvar(mpcc) .- x), maximum(x .- get_uvar(mpcc)))
    return (
        constraints = constraints,
        bounds = bounds,
        complementarity = comp_residual(mpcc, x),
        volt_var = abs(x[6] - opf_volt_var(x[1], data)),
        volt_watt = max(zero(eltype(x)), x[5] - opf_volt_watt(x[1], data)),
    )
end

end
