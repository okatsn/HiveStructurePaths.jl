using Test

# ============================================================================
# 1. Implementation (Mocking the Package for the Test)
# ============================================================================
module HivePaths
export HiveSchema, parse_hive_path, build_hive_path

struct HiveSchema
    parsers::Dict{String,Function}
    order::Vector{String}
end

function parse_hive_path(schema::HiveSchema, path::AbstractString; required_keys=Symbol[])
    results = Dict{Symbol,Any}()
    components = split(path, '/')

    for component in components
        if occursin('=', component)
            key, value = split(component, '=', limit=2)
            if haskey(schema.parsers, key)
                try
                    results[Symbol(key)] = schema.parsers[key](value)
                catch
                    # In production, you might log a warning here
                end
            end
        end
    end

    for k in required_keys
        if !haskey(results, k)
            error("Invalid Hive path. Missing required key: :$k")
        end
    end

    return (; results...)
end

function build_hive_path(schema::HiveSchema, base_dir::AbstractString, file_name; kwargs...)
    path_parts = String[base_dir]
    params = Dict(String(k) => v for (k, v) in pairs(kwargs))

    for key in schema.order
        if haskey(params, key)
            val = params[key]
            if !isnothing(val)
                push!(path_parts, "$key=$val")
            end
        end
    end

    push!(path_parts, file_name)
    return joinpath(path_parts...)
end
end

using .HivePaths

# ============================================================================
# 2. Test Suite
# ============================================================================

@testset "HivePaths Tests" begin

    # --- Setup: Define a standard Schema for Seismology ---
    TEST_SCHEMA = HiveSchema(
        Dict{String,Function}(
            "criterion" => identity,           # String -> String
            "partition" => x -> parse(Int, x), # String -> Int
            "k" => x -> parse(Int, x)  # String -> Int
        ),
        ["criterion", "partition", "k"] # Enforced order
    )

    @testset "Parsing Logic" begin
        # 1. Happy Path
        path = "data/binned/criterion=depth/partition=10/k=5/data.arrow"
        res = parse_hive_path(TEST_SCHEMA, path)
        @test res.criterion == "depth"
        @test res.partition == 10
        @test res.k == 5

        # 2. Partial Path (Missing optional 'k')
        path_partial = "data/binned/criterion=mag/partition=2/data.arrow"
        res_partial = parse_hive_path(TEST_SCHEMA, path_partial)
        @test res_partial.criterion == "mag"
        @test res_partial.partition == 2
        @test !haskey(res_partial, :k) # k should not exist

        # 3. Robustness: Extra/Unknown Keys (should be ignored)
        # 'date' and 'v' are not in schema
        path_dirty = "data/date=2023/criterion=iso/partition=1/v=2.0/data.arrow"
        res_dirty = parse_hive_path(TEST_SCHEMA, path_dirty)
        @test res_dirty.criterion == "iso"
        @test res_dirty.partition == 1
        @test !haskey(res_dirty, :date)

        # 4. Robustness: Typos (should be ignored, not crash)
        path_typo = "data/criteron=depth/partition=1/data.arrow" # 'criteron' missing 'i'
        res_typo = parse_hive_path(TEST_SCHEMA, path_typo)
        @test !haskey(res_typo, :criterion) # Should be missing because of typo
        @test res_typo.partition == 1
    end

    @testset "Validation Logic" begin
        path = "data/criterion=depth/data.arrow"

        # 1. Validation Success
        @test_nowarn parse_hive_path(TEST_SCHEMA, path; required_keys=[:criterion])

        # 2. Validation Failure (Missing partition)
        @test_throws ErrorException parse_hive_path(TEST_SCHEMA, path; required_keys=[:criterion, :partition])

        # 3. Validation Failure check message
        try
            parse_hive_path(TEST_SCHEMA, path; required_keys=[:partition])
        catch e
            @test occursin("Missing required key: :partition", e.msg)
        end
    end

    @testset "Building Logic" begin
        base = "results"
        file = "params.json"

        # 1. Happy Path
        # Note: input order of kwargs shouldn't matter
        path = build_hive_path(TEST_SCHEMA, base, file; partition=1, k=5, criterion="depth")

        # Check standard path separators just in case (Windows/Unix)
        normalized = replace(path, "\\" => "/")
        @test normalized == "results/criterion=depth/partition=1/k=5/params.json"

        # 2. Skip Missing/Nothing Values
        path_missing = build_hive_path(TEST_SCHEMA, base, file; criterion="depth", partition=1, k=nothing)
        normalized_missing = replace(path_missing, "\\" => "/")
        @test normalized_missing == "results/criterion=depth/partition=1/params.json"

        # 3. Ignore Extra Kwargs (keys not in Schema)
        path_extra = build_hive_path(TEST_SCHEMA, base, file; criterion="depth", weird_param=999)
        @test !occursin("weird_param", path_extra)
        @test occursin("criterion=depth", path_extra)
    end

    @testset "Round Trip (Build -> Parse)" begin
        # Generate a path
        generated_path = build_hive_path(TEST_SCHEMA, "tmp", "data.arrow";
            criterion="manual", partition=99, k=3)

        # Immediately parse it back
        parsed = parse_hive_path(TEST_SCHEMA, generated_path)

        @test parsed.criterion == "manual"
        @test parsed.partition == 99
        @test parsed.k == 3
    end
end
