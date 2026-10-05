const CLI_PROJECT = dirname(@__DIR__)

# Exercise process exit codes and both output streams, without Julia startup files.
function run_cli(args=String[]; input="", launcher=nothing)
    cmd = if launcher === nothing
        `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no --project=$CLI_PROJECT -e 'using Wolfram2Julia; exit(main(ARGS))' -- $args`
    else
        `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no $launcher $args`
    end
    # Pkg.test restricts its load path; subprocesses model a normal CLI launch.
    separator = Sys.iswindows() ? ";" : ":"
    cmd = addenv(cmd, "JULIA_LOAD_PATH" => "@$(separator)@stdlib")
    out, err = IOBuffer(), IOBuffer()
    process = run(pipeline(ignorestatus(cmd), stdin=IOBuffer(input), stdout=out, stderr=err))
    (status=process.exitcode, out=String(take!(out)), err=String(take!(err)))
end

@testset "launcher symlink" begin
    mktempdir() do dir
        launcher = joinpath(dir, "w2j")
        symlink(joinpath(CLI_PROJECT, "bin", "wolfram2julia"), launcher)
        cd(dir) do
            result = run_cli(; input="Sin[Pi]", launcher)
            @test result.status == 0
            @test result.out == "sin(pi)\n"
        end
    end
end

@testset "CLI arguments" begin
    for args in (["--unknown"], ["a", "b"], ["--help", "--unknown"])
        result = run_cli(args)
        @test result.status == 1
        @test isempty(result.out)
        @test occursin("Error:", result.err)
    end
    for args in (["--version", "--help"], ["--help", "--version"])
        result = run_cli(args)
        @test result.status == 0
        @test startswith(result.out, "Usage:")
        @test isempty(result.err)
    end
    @test run_cli(["-v"]).out == "wolfram2julia 0.1.0\n"
    @test run_cli(["-"]; input="2 x").out == "2 * x\n"
    mktempdir() do dir
        cd(dir) do
            write("--help", "1+2")
            result = run_cli(["--", "--help"])
            @test result.status == 0
            @test result.out == "1 + 2\n"
            write("<stdin>", "3+4")
            @test run_cli(["<stdin>"]).out == "3 + 4\n"
        end
    end
end

@testset "expected CLI failures" begin
    for input in ("?", "\"unfinished", "(* unfinished", "1*^", "f[", "If[x,1,2]")
        result = run_cli(; input)
        @test result.status == 1
        @test isempty(result.out)
        @test !isempty(result.err)
        @test !occursin("Stacktrace", result.err)
    end
    mktempdir() do dir
        for path in (dir, joinpath(dir, "missing.wl"))
            result = run_cli([path])
            @test result.status == 1
            @test isempty(result.out)
            @test occursin("Error:", result.err)
            @test !occursin("Stacktrace", result.err)
        end
    end
end

@testset "CLI source diagnostics" begin
    result = run_cli(; input="α = 1\n  Sin[If[x,1,2]]")
    @test result.status == 1
    @test isempty(result.out)
    @test occursin("<stdin>:2:7: TranslationError", result.err)
    @test occursin("  Sin[If[x,1,2]]\n      ^", result.err)
    result = run_cli(["-"]; input="α ?")
    @test occursin("<stdin>:1:3: LexError", result.err)
    @test occursin("α ?\n  ^", result.err)
    mktempdir() do dir
        path = joinpath(dir, "input.wl")
        write(path, "\n  f[")
        result = run_cli([path])
        @test occursin("$path:2:5: ParseError", result.err)
        @test occursin("  f[\n    ^", result.err)
    end
end
