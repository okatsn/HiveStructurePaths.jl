module HivePaths

export HiveSchema, parse_hive_path, build_hive_path

"""
    HiveSchema(parsers::Dict, order::Vector)

Defines the structure and parsing rules for a Hive file hierarchy.
"""
struct HiveSchema
    parsers::Dict{String,Function}
    order::Vector{String}
end

# Default constructor helper for cleaner syntax
function HiveSchema(; parsers, order)
    return HiveSchema(parsers, order)
end

"""
    parse_hive_path(schema::HiveSchema,path::AbstractString; required_keys=[]) → NamedTuple

Extract criterion, partition, and k from Hive-style paths.

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
    build_hive_path(schema::HiveSchema,base_dir::AbstractString, file_name; kwargs...) → String

Construct Hive-style output path with consistent ordering.

Path structure is always: `base_dir/criterion=<criterion>/partition=<partition>[/k=<k>]/file_name`

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

build_hive_path(schema::HiveSchema,"data/binned", "data.arrow"; criterion="depth_iso", partition=1)
# → "data/binned/criterion=depth_iso/partition=1/data.arrow"

build_hive_path(schema::HiveSchema,"data/cluster_assignments", "data.arrow"; partition=2, criterion="depth_iso", k=10)
# → "data/cluster_assignments/criterion=depth_iso/partition=2/k=10/data.arrow"
# Noted that the order is consistent with the previous one; the order of `kwargs` does not matter.

build_hive_path(schema::HiveSchema,"plots/voronoi_maps", "criterion=depth_iso.png"; criterion="depth_iso", partition=1, k=8)
# → "plots/voronoi_maps/criterion=depth_iso/partition=1/k=8/criterion=depth_iso.png"
```

# Arguments
- `base_dir`: Base directory path
- `file_name`: File name to append at the end of the path
- `kwargs`: labels in the path to the file as keyword arguments.


# Returns
Complete path string with Hive-style structure
"""
function build_hive_path(schema::HiveSchema, base_dir::AbstractString, file_name; kwargs...)
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

    push!(path_parts, file_name)

    return joinpath(path_parts...)
end


end
