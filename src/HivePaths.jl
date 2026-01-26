module HiveStructurePaths

export HiveSchema, parse_hive_path, build_hive_path, find_hive_files

"""
    HiveSchema(; parsers::Dict, order::Vector, filename::String)

Defines the structure and parsing rules for a Hive file hierarchy.

# Fields
- `parsers`: Dict mapping key names to parsing functions
- `order`: Vector defining the hierarchical order of keys in paths
- `filename`: The target filename that appears in all Hive paths (one per schema)
"""
struct HiveSchema
    parsers::Dict{String,Function}
    order::Vector{String}
    filename::String
end

# Default constructor helper for cleaner syntax
function HiveSchema(; parsers, order, filename)
    return HiveSchema(parsers, order, filename)
end

"""
    parse_hive_path(schema::HiveSchema, path::AbstractString; required_keys=[]) → NamedTuple

Extract key-value pairs from Hive-style paths according to the schema.

# Examples
```julia

const schema = HiveSchema(
    parsers = Dict{String, Function}(
        "criterion" => identity,
        "partition" => x -> parse(Int, x),
        "k"         => x -> parse(Int, x)
    ),
    order = ["criterion", "partition", "k"]
)

parse_hive_path(schema::HiveSchema,"data/binned/criterion=depth_iso/partition=1/data.arrow")
# → (criterion="depth_iso", partition=1, k=nothing)

parse_hive_path(schema::HiveSchema,"data/cluster_assignments/criterion=depth_iso/partition=2/k=10/data.arrow")
# → (criterion="depth_iso", partition=2, k=10)

# Validate required keys
parse_hive_path(schema::HiveSchema,"data/binned/criterion=depth_iso/partition=1/data.arrow"; required_keys=["criterion", "partition"])
# → (criterion="depth_iso", partition=1, k=nothing)
```

# Arguments
- `path`: Path string containing Hive-style key=value segments
- `required_keys`: Optional list of keys that must be present (default: [])

# Returns
NamedTuple with extracted values (nothing for missing fields)

# Throws
- `ErrorException` if any required_keys are missing from the path
"""
function parse_hive_path(schema::HiveSchema, path::AbstractString; required_keys=[])
    results = Dict{Symbol,Any}()

    # Split path into components
    components = split(path, '/')

    for component in components
        if occursin('=', component)
            key, value = split(component, '=', limit=2)
            if haskey(schema.parsers, key)
                # KEYNOTE: "Loose Parse, Strict Validate"
                # - (The Loose Parse part) It is intended to ignore unknown keys because someone might add irrelevant folder
                # - (The "Strict Validate part") Validate against `required_keys`
                parser_func = schema.parsers[key]
                results[Symbol(key)] = parser_func(value)
            end
        end
    end

    # Strict Validation: Ensure critical keys are not missing
    missing_keys = [k for k in required_keys if !haskey(results, Symbol(k))]

    if !isempty(missing_keys)
        # This catches typos like "criteron=depth" because :criterion will be missing
        error("Invalid Hive path. Missing required keys: $missing_keys. Path: $path")
    end

    return (; results...)
end

"""
    build_hive_path(schema::HiveSchema, base_dir::AbstractString; kwargs...) → String

Construct Hive-style output path with consistent ordering.

Path structure follows schema order: `base_dir/key1=<val1>/key2=<val2>/.../filename`
where `filename` comes from `schema.filename`.

# Examples
```julia
const schema = HiveSchema(
    parsers = Dict{String, Function}(
        "criterion" => identity,
        "partition" => x -> parse(Int, x),
        "k"         => x -> parse(Int, x)
    ),
    order = ["criterion", "partition", "k"],
    filename = "data.arrow"
)

build_hive_path(schema, "data/binned"; criterion="depth_iso", partition=1)
# → "data/binned/criterion=depth_iso/partition=1/data.arrow"

build_hive_path(schema, "data/cluster_assignments"; partition=2, criterion="depth_iso", k=10)
# → "data/cluster_assignments/criterion=depth_iso/partition=2/k=10/data.arrow"
# Note that the order is consistent with the previous one; the order of `kwargs` does not matter.
```

# Arguments
- `base_dir`: Base directory path
- `kwargs`: Key-value pairs matching schema keys


# Returns
Complete path string with Hive-style structure
"""
function build_hive_path(schema::HiveSchema, base_dir::AbstractString; kwargs...)
    # Start with base directory
    path_parts = String[base_dir]

    # Collect available parameters - convert Symbol keys to String
    params = Dict{String,Any}(String(k) => v for (k, v) in pairs(kwargs))

    # Iterate through the enforced hierarchy order
    for key in schema.order
        value = get(params, key, nothing)
        if !isnothing(value)
            push!(path_parts, "$key=$value")
        end
    end

    push!(path_parts, schema.filename)

    return joinpath(path_parts...)
end


# ============================================================================
# I/O Utilities
# ============================================================================

"""
    find_hive_files(schema::HiveSchema, root_dir::AbstractString;
                    validate_keys=[], error_if_empty=false) -> Vector{String}

Recursively find files that match the schema's filename AND structure.

# Arguments
- `validate_keys`: List of keys (e.g. `[:criterion]`) that MUST be present in the path
  for it to be considered valid.
- `error_if_empty`: If true, throws error if no matching files are found.

# Returns
Sorted list of absolute paths.
"""
function find_hive_files(schema::HiveSchema, root_dir::AbstractString;
    validate_keys=Symbol[], error_if_empty=false)

    # 1. Safety Check: Directory existence
    if !isdir(root_dir)
        error("Directory not found: $root_dir")
    end

    found_files = String[]
    target = schema.filename

    # 2. Walk and Filter
    for (root, dirs, files) in walkdir(root_dir)
        if target in files
            full_path = joinpath(root, target)

            # 3. schema-Awareness: Check if this file actually fits the schema
            # If validate_keys is empty, this just checks if parse crashes,
            # effectively acting as a loose structure check.
            try
                parsed = parse_hive_path(schema, full_path; required_keys=validate_keys)

                push!(found_files, full_path)
            catch
                # If parsing fails (e.g. missing required keys), skip this file.
                # It might be a backup or a loose file not part of the dataset.
                continue
            end
        end
    end

    # 4. Guardrail against silent failures
    if error_if_empty && isempty(found_files)
        error("No valid Hive files found in $root_dir matching schema $(schema.filename)")
    end

    return sort(found_files)
end

end
