include("hard-search.jl")
using .HardCaseSearch

function main_search(args)
    if "--help" in args
        println(
            "search-hard-cases.jl --out=DIR [--caps=.80,.82,.84] [--starts=flat,neighbor,perturbed_neighbor,witness] [--profiles=defaults,current,looser_inner,ratio_one,higher_floor] [--seed=20261024] [--repetitions=1] [--max-iter=500] [--max-wall=60] [--resume] [--no-warmup]",
        )
        println("search-hard-cases.jl --replay=TRIAL_DIR --out=NEW_DIR")
        println("search-hard-cases.jl --summarize=SEARCH_DIR")
        return nothing
    end
    values = Dict{String,String}()
    flags = Set{String}()
    for arg in args
        if arg in ("--resume", "--no-warmup")
            push!(flags, arg)
        elseif startswith(arg, "--") && occursin('=', arg)
            k, v = split(arg[3:end], '='; limit = 2)
            haskey(values, k) && throw(ArgumentError("duplicate option $k"))
            values[k] = v
        else
            throw(ArgumentError("invalid argument $arg"))
        end
    end
    allowed = (
        "out",
        "caps",
        "starts",
        "profiles",
        "seed",
        "repetitions",
        "max-iter",
        "max-wall",
        "replay",
        "summarize",
    )
    all(k -> k in allowed, keys(values)) || throw(ArgumentError("unknown option"))
    if haskey(values, "summarize")
        length(values) == 1 && isempty(flags) ||
            throw(ArgumentError("summarize accepts no other options"))
        return summarize_search(values["summarize"])
    end
    haskey(values, "out") || throw(ArgumentError("--out is required"))
    if haskey(values, "replay")
        length(values) == 2 && isempty(flags) ||
            throw(ArgumentError("replay accepts only --out"))
        return replay_trial(values["replay"], values["out"])
    end
    kwargs = Dict{Symbol,Any}()
    for (key, dest) in
        (("caps", :capabilities), ("starts", :starts), ("profiles", :profiles))
        if haskey(values, key)
            kwargs[dest] =
                key == "caps" ? parse.(Float64, split(values[key], ',')) :
                Symbol.(split(values[key], ','))
        end
    end
    for (key, dest) in
        (("seed", :seed), ("repetitions", :repetitions), ("max-iter", :max_iter))
        haskey(values, key) && (kwargs[dest] = parse(Int, values[key]))
    end
    haskey(values, "max-wall") &&
        (kwargs[:max_wall_time] = parse(Float64, values["max-wall"]))
    return run_search(
        values["out"];
        kwargs...,
        resume = "--resume" in flags,
        warmup = !("--no-warmup" in flags),
    )
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main_search(ARGS)
end
