# From the repository root:
# julia --project=examples/opf examples/opf/solve.jl [case_name | all]
using CCOpt, NLPModels

include("balanced-ac-opf.jl")
using .BalancedACOPF

function solve_opf_case(name::Symbol)
    data = balanced_ac_opf_case(name)
    mpcc = BalancedACOPFModel(; case = name)
    # At a breakpoint both hinge members can be small, so a small product
    # alone need not give an equally small error in the physical curve.
    options = CCOpt.RelaxationOptions(;
        sigma_min = 1e-14,
        relaxation_update = CCOpt.ProportionalRelaxationUpdate{Float64}(sigma_min = 1e-14),
        print_level = CCOpt.MadNLP.ERROR,
    )
    solver = CCOpt.RelaxationSolver(
        mpcc;
        solver_opts = options,
        bound_relax_factor = 0.0,
        tol = 1e-12,
        max_iter = 300,
        print_level = CCOpt.MadNLP.ERROR,
    )
    stats = CCOpt.solve_homotopy!(solver)
    x = stats.solution
    residuals = opf_residuals(mpcc, x, data)
    println((
        case = name,
        status = stats.status,
        objective = obj(mpcc, x),
        voltage = x[1],
        p = x[5],
        q = x[6],
        residuals = residuals,
    ))
    # Independently check the original equations and curves. Passing these
    # checks establishes numerical feasibility, not global optimality.
    stats.status in
    (CCOpt.MadNLP.SOLVE_SUCCEEDED, CCOpt.MadNLP.SOLVED_TO_ACCEPTABLE_LEVEL) ||
        error("OPF solve failed for $name")
    maximum(values(residuals)) <= 1e-5 || error("OPF residual check failed for $name")
    return stats
end

function main(args)
    length(args) <= 1 || throw(ArgumentError("expected a case name or all"))
    names =
        isempty(args) ? (:curtailment,) :
        only(args) == "all" ? balanced_ac_opf_cases() : (Symbol(only(args)),)
    for name in names
        solve_opf_case(name)
    end
    return nothing
end

main(ARGS)
