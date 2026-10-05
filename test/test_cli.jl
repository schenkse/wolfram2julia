const CLI_PROJECT = dirname(@__DIR__)

# Exercise process exit codes and both output streams, without Julia startup files.
function run_cli(args=String[]; input="", launcher=nothing)
    cmd = if launcher === nothing
        `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no --project=$CLI_PROJECT -e 'using Wolfram2Julia; exit(main(ARGS))' -- $args`
    else
        `$(Base.julia_cmd()) --startup-file=no --compiled-modules=no $launcher $args`
    end
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
