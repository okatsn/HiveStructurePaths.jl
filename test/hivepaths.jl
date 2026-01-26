@testset "HivePaths Tests" begin

    # --- Setup: Define a standard Schema for Seismology ---
    TEST_SCHEMA = HiveSchema(
        Dict{String,Function}(
            "criterion" => identity,           # String -> String
            "partition" => x -> parse(Int, x), # String -> Int
            "k" => x -> parse(Int, x)  # String -> Int
        ),
        ["criterion", "partition", "k"], # Enforced order
        "data.arrow"
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
        @test_throws ErrorException parse_hive_path(TEST_SCHEMA, path; required_keys=[:partition])
    end

    @testset "Building Logic" begin
        base = "results"
        TEST_SCHEMA2 = HiveSchema(
            Dict{String,Function}(
                "criterion" => identity,           # String -> String
                "partition" => x -> parse(Int, x), # String -> Int
                "k" => x -> parse(Int, x)  # String -> Int
            ),
            ["criterion", "partition", "k"], # Enforced order
            "params.json"
        )

        # 1. Happy Path
        # Note: input order of kwargs shouldn't matter
        path = build_hive_path(TEST_SCHEMA2, base; partition=1, k=5, criterion="depth")

        # Check standard path separators just in case (Windows/Unix)
        normalized = replace(path, "\\" => "/")
        @test normalized == "results/criterion=depth/partition=1/k=5/params.json"

        # 2. Skip Missing/Nothing Values
        path_missing = build_hive_path(TEST_SCHEMA2, base; criterion="depth", partition=1, k=nothing)
        normalized_missing = replace(path_missing, "\\" => "/")
        @test normalized_missing == "results/criterion=depth/partition=1/params.json"

        # 3. Ignore Extra Kwargs (keys not in Schema)
        path_extra = build_hive_path(TEST_SCHEMA2, base; criterion="depth", weird_param=999)
        @test !occursin("weird_param", path_extra)
        @test occursin("criterion=depth", path_extra)
    end

    @testset "Round Trip (Build -> Parse)" begin
        # Generate a path
        generated_path = build_hive_path(TEST_SCHEMA, "tmp";
            criterion="manual", partition=99, k=3)

        # Immediately parse it back
        parsed = parse_hive_path(TEST_SCHEMA, generated_path)

        @test parsed.criterion == "manual"
        @test parsed.partition == 99
        @test parsed.k == 3
    end
end
