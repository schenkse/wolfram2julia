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
    filename, source = "<stdin>", ""
    try
        parsed = _cli_arguments(args)
        if parsed.help
            print(USAGE)
            return 0
        elseif parsed.version
            println(VERSION_STR)
            return 0
        end
        positional = parsed.positional
        filename = isempty(positional) || positional == ["-"] ? "<stdin>" : only(positional)
        source = if isempty(positional) || positional == ["-"]
            if isempty(positional) && isa(stdin, Base.TTY)
                print(stderr, USAGE)
                return 1
            end
            read(stdin, String)
        else
            path = only(positional)
            isdir(path) && throw(ArgumentError("expected a file, got directory: $path"))
            read(path, String)
        end
        result = translate_string(source)
        println(result)
        return 0
    catch e
        if e isa Union{LexError,ParseError,TranslationError}
            _print_diagnostic(stderr, e, filename, source)
        elseif e isa ArgumentError
            println(stderr, "Error: $(e.msg)")
        elseif e isa Union{SystemError,Base.IOError}
            println(stderr, "Error: ", sprint(showerror, e))
        else
            rethrow(e)
        end
        return 1
    end
end

function _print_diagnostic(io::IO, error, filename::String, source::String)
    label = string(nameof(typeof(error)))
    if error.line == 0
        println(io, "$filename: $label: $(error.message)")
        return
    end
    println(io, "$filename:$(error.line):$(error.col): $label: $(error.message)")
    lines = split(source, '\n'; keepempty=true)
    if 1 <= error.line <= length(lines)
        line = lines[error.line]
        println(io, line)
        # Keep tabs in the prefix so the caret follows the displayed source.
        for (i, character) in enumerate(line)
            i >= error.col && break
            print(io, character == '\t' ? '\t' : ' ')
        end
        println(io, '^')
    end
end
