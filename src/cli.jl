const VERSION_STR = "wolfram2julia 0.1.0"

const USAGE = """
Usage: wolfram2julia [options] [file]

Translate Wolfram Mathematica expressions to Julia code.

Arguments:
  file          Path to a .wl / .m file (optional; reads stdin if omitted)

Options:
  -h, --help    Show this help message
  -v, --version Show version

Examples:
  wolfram2julia input.wl
  echo "Sin[Pi] + x^2" | wolfram2julia
"""

function main(args::Vector{String} = ARGS)::Int
    if "--help" in args || "-h" in args
        print(USAGE)
        return 0
    end

    if "--version" in args || "-v" in args
        println(VERSION_STR)
        return 0
    end

    # Filter out any unknown flags
    positional = filter(a -> !startswith(a, "-"), args)

    source = if isempty(positional)
        if isa(stdin, Base.TTY)
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
            println(stderr, "Translation error: $(e.message)")
            return 1
        else
            rethrow(e)
        end
    end
end
