const VERSION_STR = "wolfram2julia 0.1.0"

const USAGE = """
Usage: wolfram2julia [options] [file]

Translate Wolfram Mathematica expressions to Julia code.

Arguments:
  file          Path to a .wl / .m file (optional; reads stdin if omitted or -)

Options:
  -h, --help    Show this help message
  -v, --version Show version
  --            End options; the next argument is a literal filename

Examples:
  wolfram2julia input.wl
  echo "Sin[Pi] + x^2" | wolfram2julia
"""

# Validate the entire argument list before handling informational options.
function _cli_arguments(args::Vector{String})
    positional = String[]
    options, help, version = true, false, false
    for arg in args
        if options && arg == "--"
            options = false
        elseif options && arg in ("--help", "-h")
            help = true
        elseif options && arg in ("--version", "-v")
            version = true
        elseif options && startswith(arg, "-") && arg != "-"
            throw(ArgumentError("unknown option: $arg"))
        else
            push!(positional, arg)
        end
    end
    length(positional) <= 1 || throw(ArgumentError("too many arguments"))
    (positional=positional, help=help, version=version)
end

function main(args::Vector{String} = ARGS)::Int
    parsed = try
        _cli_arguments(args)
    catch e
        e isa ArgumentError || rethrow(e)
        println(stderr, "Error: $(e.msg)")
        return 1
    end
    if parsed.help
        print(USAGE)
        return 0
    elseif parsed.version
        println(VERSION_STR)
        return 0
    end
    positional = parsed.positional

    source = if isempty(positional) || positional == ["-"]
        if isempty(positional) && isa(stdin, Base.TTY)
            print(stderr, USAGE)
            return 1
        end
        read(stdin, String)
    elseif length(positional) == 1
        path = positional[1]
        if !isfile(path)
            println(stderr, "Error: file not found: $path")
            return 1
        end
        read(path, String)
    else
        println(stderr, "Error: too many arguments")
        print(stderr, USAGE)
        return 1
    end

    try
        result = translate_string(source)
        println(result)
        return 0
    catch e
        if e isa ParseError
            println(stderr, "Parse error at $(e.line):$(e.col): $(e.message)")
            return 1
        elseif e isa TranslationError
            println(stderr, sprint(showerror, e))
            return 1
        else
            rethrow(e)
        end
    end
end
