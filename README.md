# HiveStructurePaths

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://okatsn.github.io/HiveStructurePaths.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://okatsn.github.io/HiveStructurePaths.jl/dev/)
[![Build Status](https://github.com/okatsn/HiveStructurePaths.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/okatsn/HiveStructurePaths.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/okatsn/HiveStructurePaths.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/okatsn/HiveStructurePaths.jl)

<!-- Don't have any of your custom contents above; they won't occur if there is no citation. -->

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://okatsn.github.io/HiveStructurePaths.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://okatsn.github.io/HiveStructurePaths.jl/dev)

HiveStructurePaths provides utilities for working with Hive-style partitioned file hierarchies, where data is organized using `key=value` directory structures.

## Purpose

When managing datasets partitioned across multiple dimensions (e.g., `criterion=depth/partition=1/k=10/data.arrow`), HiveStructurePaths helps you:
- **Parse** paths to extract partition metadata
- **Build** paths with consistent hierarchical ordering
- **Find** all files matching a specific schema

Each `HiveSchema` defines one target filename and the hierarchical structure of its enclosing directories.

## Example

```julia
using HiveStructurePaths

# Define the schema
schema = HiveSchema(
    parsers = Dict{String, Function}(
        "criterion" => identity,
        "partition" => x -> parse(Int, x),
        "k"         => x -> parse(Int, x)
    ),
    order = ["criterion", "partition", "k"],
    filename = "data.arrow"
)

# Build paths
path = build_hive_path(schema, "results"; criterion="depth", partition=2, k=5)
# → "results/criterion=depth/partition=2/k=5/data.arrow"

# Parse paths
parsed = parse_hive_path(schema, path; required_keys=["criterion", "partition"])
# → (criterion="depth", partition=2, k=5)

# Find all matching files
files = find_hive_files(schema, "results"; validate_keys=["criterion"])
# → ["results/criterion=depth/partition=1/k=3/data.arrow",
#    "results/criterion=depth/partition=2/k=5/data.arrow", ...]
```

See the docstrings for detailed API documentation.
