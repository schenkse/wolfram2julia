struct TranslationError <: Exception
    message::String
    line::Int
    col::Int
    TranslationError(message::String, line::Int=0, col::Int=0) =
        new(message, line, col)
end

function Base.showerror(io::IO, e::TranslationError)
    if e.line > 0
        print(io, "TranslationError at $(e.line):$(e.col): $(e.message)")
    else
        print(io, "TranslationError: $(e.message)")
    end
end

# Precedence levels used for parenthesization decisions
const PREC_ATOM     = 1000
const PREC_CALL     = 900
const PREC_POWER    = 80
const PREC_UNARY    = 70
const PREC_MUL      = 60
const PREC_ADD      = 50
const PREC_LOW      = 0

# Symbol remapping table
const SYMBOL_MAP = Dict(
    "Pi"       => "pi",
    "E"        => "MathConstants.e",
    "I"        => "im",
    "Infinity" => "Inf",
    "True"     => "true",
    "False"    => "false",
    "Null"     => "nothing",
)

# 1-argument math function mapping: Wolfram head → Julia function name
const MATH_FUNC1_MAP = Dict(
    "Sin"     => "sin",
    "Cos"     => "cos",
    "Tan"     => "tan",
    "ArcSin"  => "asin",
    "ArcCos"  => "acos",
    "ArcTan"  => "atan",
    "Exp"     => "exp",
    "Abs"     => "abs",
    "Sign"    => "sign",
    "Floor"   => "floor",
    "Ceiling" => "ceil",
    "Round"   => "round",
    "Re"        => "real",
    "Im"        => "imag",
    "Conjugate" => "conj",
    "Log2"      => "log2",
    "Log10"     => "log10",
    "Total"     => "sum",
)

# N-ary math function mapping: Wolfram head → Julia function name (1+ args, all passed through)
const MATH_FUNC_NARY_MAP = Dict(
    "Mod"  => "mod",
    "Max"  => "max",
    "Min"  => "min",
    "GCD"  => "gcd",
    "LCM"  => "lcm",
    "Mean" => "Statistics.mean",
)

# Heads that are explicitly unsupported — throw rather than emit broken Julia
const UNSUPPORTED_HEADS = ("If", "Which", "Switch", "Do", "While", "For",
                           "Dot", "Transpose", "Inverse")

# Pattern type annotation mapping: Mathematica head → Julia type
const PATTERN_TYPE_MAP = Dict(
    "Integer" => "Integer",
    "Real"    => "AbstractFloat",
    "String"  => "String",
    "Symbol"  => "Symbol",
    "Complex" => "Complex",
)

# Return the natural precedence of an expression (for parenthesization)
function _natural_prec(e::MExpr)::Int
    e isa MInteger  && return e.value < 0 ? PREC_UNARY : PREC_ATOM
    e isa MReal     && return signbit(e.value) ? PREC_UNARY : PREC_ATOM
    e isa MString   && return PREC_ATOM
    e isa MSymbol   && return PREC_ATOM
    e isa MExprNode || return PREC_ATOM
    n = head_name(e)
    n === nothing        && return PREC_CALL
    n in ("Plus",)       && return PREC_ADD
    n in ("Times",)      && return PREC_MUL
    n in ("Power",)      && return PREC_POWER
    n in ("SetDelayed", "Set", "CompoundExpression", "Rule", "RuleDelayed", "Function") && return PREC_LOW
    return PREC_CALL
end

function _wrap(s::String, e::MExpr, parent_prec::Int)::String
    _natural_prec(e) < parent_prec ? "($s)" : s
end

# Lexical bindings and generated requirements belong to one translation.
struct TranslationContext
    sequences::Set{String}
    slots::Union{Nothing,String}
    requirements::Set{String}
end
TranslationContext() = TranslationContext(Set{String}(), nothing, Set{String}())

_is_sequence(e::MExpr, ctx::TranslationContext) =
    (e isa MSymbol && e.name in ctx.sequences) || is_head(e, "SlotSequence")

function _translate_arg(e::MExpr, ctx::TranslationContext)::String
    value = _translate(e, PREC_LOW + 1, ctx)
    _is_sequence(e, ctx) ? value * "..." : value
end

# ─── Public entry points ────────────────────────────────────────────────────

"""
    translate(e::MExpr) -> String

Translate a single Mathematica AST node to a Julia code string.
"""
translate(e::MExpr) = _translate(e, PREC_LOW, TranslationContext())

"""
    translate_string(source::String) -> String

Parse and translate a Wolfram Mathematica source string to Julia code.
Multiple statements (separated by `;`) are joined with newlines.
"""
function translate_string(source::String)::String
    ctx = TranslationContext()
    stmts = parse_string(source)
    join((_translate_program(s, ctx) for s in stmts), "\n")
end

"""
    translate_file(path::String) -> String

Read a file and translate its contents.
"""
function translate_file(path::String)::String
    translate_string(read(path, String))
end

# Compound statements at program level do not need an expression block.
function _translate_program(e::MExpr, ctx::TranslationContext)::String
    is_head(e, "CompoundExpression") && return join((_translate_program(a, ctx) for a in e.args), "\n")
    _translate(e, PREC_LOW, ctx)
end

# ─── Core translator ────────────────────────────────────────────────────────

function _translate(e::MExpr, parent_prec::Int, ctx::TranslationContext)::String
    if e isa MInteger
        return _wrap(string(e.value), e, parent_prec)
    end

    if e isa MReal
        return _wrap(e.literal, e, parent_prec)
    end

    if e isa MString
        return repr(e.value)
    end

    if e isa MSymbol
        return get(SYMBOL_MAP, e.name, e.name)
    end

    # MExprNode
    e isa MExprNode || return ""
    n = head_name(e)

    # ── Arithmetic ──────────────────────────────────────────────────────────

    if n in ("Plus", "Times", "Power") && any(a -> _is_sequence(a, ctx), e.args)
        op = n == "Plus" ? "+" : n == "Times" ? "*" : "^"
        return "$op($(join((_translate_arg(a, ctx) for a in e.args), ", ")))"
    end

    if n == "Plus"
        parts = [_translate_plus_arg(a, ctx) for a in e.args]
        result = _join_plus(parts, e.args)
        return _wrap(result, e, parent_prec)
    end

    if n == "Times"
        return _wrap(_translate_times(e.args, parent_prec, ctx), e, parent_prec)
    end

    if n == "Power"
        length(e.args) == 2 || throw(TranslationError("Power requires 2 args"))
        b, ex = e.args
        bs = _translate(b, PREC_POWER + 1, ctx)
        es = _translate(ex, PREC_POWER, ctx)
        result = "$(bs)^$(es)"
        return _wrap(result, e, parent_prec)
    end

    # ── Math functions ───────────────────────────────────────────────────────

    if n == "Sqrt"
        length(e.args) == 1 || throw(TranslationError("Sqrt requires 1 arg"))
        return "sqrt($(_translate_arg(e.args[1], ctx)))"
    end

    if haskey(MATH_FUNC1_MAP, n)
        jname = MATH_FUNC1_MAP[n]
        length(e.args) == 1 || throw(TranslationError("$n requires 1 arg"))
        return "$(jname)($(_translate_arg(e.args[1], ctx)))"
    end

    if haskey(MATH_FUNC_NARY_MAP, n)
        jname = MATH_FUNC_NARY_MAP[n]
        isempty(e.args) && throw(TranslationError("$n requires at least 1 arg"))
        args_str = join([_translate_arg(a, ctx) for a in e.args], ", ")
        return "$(jname)($(args_str))"
    end

    if n == "Log"
        length(e.args) in (1, 2) || throw(TranslationError("Log requires 1 or 2 args, got $(length(e.args))"))
        if length(e.args) == 1
            return "log($(_translate_arg(e.args[1], ctx)))"
        elseif length(e.args) == 2
            # Log[base, x]
            return "log($(_translate_arg(e.args[1], ctx)), $(_translate(e.args[2], PREC_LOW, ctx)))"
        end
    end

    if n == "Factorial"
        length(e.args) == 1 || throw(TranslationError("Factorial requires 1 arg"))
        return "factorial($(_translate_arg(e.args[1], ctx)))"
    end

    # ── Definitions ─────────────────────────────────────────────────────────

    if n in ("SetDelayed", "Set")
        length(e.args) == 2 || throw(TranslationError("$n requires 2 args"))
        lhs, rhs = e.args
        return _wrap(_translate_setdelayed(lhs, rhs, ctx), e, parent_prec)
    end

    # ── Functions ────────────────────────────────────────────────────────────

    if n == "Function"
        return _wrap(_translate_function(e.args, ctx), e, parent_prec)
    end

    if n == "Pattern"
        # Strip pattern wrapper: Pattern[x, _] → x
        length(e.args) >= 1 || throw(TranslationError("Pattern requires args"))
        return _translate(e.args[1], parent_prec, ctx)
    end

    if n in ("Slot", "SlotSequence")
        ctx.slots === nothing && throw(TranslationError("$n outside a slot-style pure function"))
        index = _slot_index(e)
        return n == "Slot" ? "$(ctx.slots)[$index]" : "$(ctx.slots)[$index:end]"
    end

    # ── Collections ──────────────────────────────────────────────────────────

    if n == "List"
        parts = [_translate_arg(a, ctx) for a in e.args]
        return "[$(join(parts, ", "))]"
    end

    # ── Control expressions ──────────────────────────────────────────────────

    if n == "CompoundExpression"
        return _wrap("begin\n" * join((_translate(a, PREC_LOW, ctx) for a in e.args), "\n") * "\nend", e, parent_prec)
    end

    if n == "Rule"
        length(e.args) == 2 || throw(TranslationError("Rule requires 2 args"))
        return _wrap("$(_translate(e.args[1], PREC_LOW + 1, ctx)) => $(_translate(e.args[2], PREC_LOW + 1, ctx))", e, parent_prec)
    end

    if n == "RuleDelayed"
        length(e.args) == 2 || throw(TranslationError("RuleDelayed requires 2 args"))
        # :> delays evaluation of the RHS; represent as a thunk to preserve the distinction
        return _wrap("$(_translate(e.args[1], PREC_LOW + 1, ctx)) => (() -> $(_translate(e.args[2], PREC_LOW, ctx)))", e, parent_prec)
    end

    # ── Explicitly unsupported constructs ────────────────────────────────────

    if n !== nothing && n in UNSUPPORTED_HEADS
        throw(TranslationError("$n is not yet supported"))
    end

    # ── Generic function call fallback ───────────────────────────────────────

    head_str = _translate(e.head, PREC_CALL, ctx)
    arg_strs = [_translate_arg(a, ctx) for a in e.args]
    return "$(head_str)($(join(arg_strs, ", ")))"
end

# ─── Helpers ────────────────────────────────────────────────────────────────

function _is_neg_one(e::MExpr)::Bool
    (e isa MInteger && e.value == -1) || (e isa MReal && e.value == -1.0)
end

function _is_neg_integer(e::MExpr)::Bool
    e isa MInteger && e.value < 0
end

# Translate a single arg of Plus, handling the Times[-1, x] → -x case
function _translate_plus_arg(a::MExpr, ctx::TranslationContext)::String
    if is_head(a, "Times") && !isempty(a.args) && _is_neg_one(a.args[1])
        # This is a subtraction term: represent as "-x" for joining
        # We'll handle sign during join
        inner = length(a.args) == 2 ? a.args[2] :
                MExprNode("Times", a.args[2:end])
        return "- $(_translate(inner, PREC_MUL, ctx))"
    end
    _translate(a, PREC_ADD, ctx)
end

# Join Plus args, treating "- x" terms specially
function _join_plus(parts::Vector{String}, args::Vector{MExpr})::String
    if isempty(parts)
        return "0"
    end
    result = IOBuffer()
    for (i, part) in enumerate(parts)
        if i == 1
            print(result, part)
        elseif startswith(part, "- ")
            print(result, " ", part)
        else
            print(result, " + ", part)
        end
    end
    String(take!(result))
end

# Translate Times, handling special cases for negation and division
function _translate_times(args::Vector{MExpr}, parent_prec::Int, ctx::TranslationContext)::String
    isempty(args) && return "1"

    # Detect unary negation: Times[-1, x]
    if length(args) == 2 && _is_neg_one(args[1])
        inner = _translate(args[2], PREC_UNARY, ctx)
        return "-$(inner)"
    end

    # Detect Times[a, Power[b, -1]] → a / b
    # More generally split into numerator and denominator
    nums = MExpr[]
    dens = MExpr[]
    leading_neg = false
    for a in args
        if _is_neg_one(a)
            leading_neg = !leading_neg
        elseif is_head(a, "Power") && length(a.args) == 2 && _is_neg_one(a.args[2])
            push!(dens, a.args[1])
        elseif is_head(a, "Power") && length(a.args) == 2 &&
               a.args[2] isa MInteger && a.args[2].value < -1
            # Power[x, -n] → denominator x^n
            push!(dens, MExprNode("Power", MExpr[a.args[1], MInteger(-a.args[2].value)]))
        else
            push!(nums, a)
        end
    end

    neg_prefix = leading_neg ? "-" : ""

    if isempty(dens)
        # _translate(a, PREC_MUL, ctx) already inserts parens when needed via _wrap
        parts = [_translate(a, PREC_MUL, ctx) for a in nums]
        result = isempty(parts) ? "1" : join(parts, " * ")
        return neg_prefix * result
    else
        num_str = if isempty(nums)
            "1"
        else
            join([_translate(a, PREC_MUL, ctx) for a in nums], " * ")
        end
        den_str = if length(dens) == 1
            _translate(dens[1], PREC_MUL + 1, ctx)
        else
            join((_translate(a, PREC_MUL + 1, ctx) for a in dens), " / ")
        end
        return "$(neg_prefix)$(num_str) / $(den_str)"
    end
end

function _translate_setdelayed(lhs::MExpr, rhs::MExpr, ctx::TranslationContext)::String
    if lhs isa MExprNode && lhs.head isa MSymbol
        params = String[]
        setup = String[]
        sequences = copy(ctx.sequences)
        names = Set{String}()
        for (i, arg) in enumerate(lhs.args)
            named = is_head(arg, "Pattern") && length(arg.args) == 2 && arg.args[1] isa MSymbol
            name = named ? arg.args[1].name : "_p$i"
            name in names && throw(TranslationError("Duplicate function parameter: $name"))
            push!(names, name)
            delete!(sequences, name)
            blank = named ? arg.args[2] : arg
            sequence = head_name(blank) in ("BlankSequence", "BlankNullSequence")
            if sequence
                i == length(lhs.args) || throw(TranslationError("Sequence pattern must be the final parameter"))
                annotation = _pattern_type(blank)
                if is_head(blank, "BlankSequence")
                    first_name = "_w2j_first"
                    while first_name in names || _contains_symbol(rhs, first_name)
                        first_name *= "_"
                    end
                    push!(params, first_name * annotation)
                    push!(setup, "$name = ($first_name, $name...)")
                end
                push!(params, name * annotation * "...")
                push!(sequences, name)
            else
                push!(params, _strip_pattern(arg, i))
            end
        end
        bodyctx = TranslationContext(sequences, ctx.slots, ctx.requirements)
        body = _translate(rhs, PREC_LOW, bodyctx)
        isempty(setup) || (body = "begin\n" * join(setup, "\n") * "\n" * body * "\nend")
        return "$(_translate(lhs.head, PREC_CALL, ctx))($(join(params, ", "))) = $body"
    end
    "$(_translate(lhs, PREC_LOW + 1, ctx)) = $(_translate(rhs, PREC_LOW + 1, ctx))"
end

function _contains_symbol(e::MExpr, name::String)::Bool
    e isa MSymbol && return e.name == name
    e isa MExprNode || return false
    _contains_symbol(e.head, name) || any(a -> _contains_symbol(a, name), e.args)
end

function _pattern_type(blank::MExpr)::String
    head_name(blank) in ("Blank", "BlankSequence", "BlankNullSequence") || throw(TranslationError("Invalid blank pattern"))
    length(blank.args) <= 1 || throw(TranslationError("Invalid blank constraint"))
    isempty(blank.args) && return ""
    constraint = blank.args[1]
    constraint isa MSymbol || throw(TranslationError("Pattern constraint must be a symbol"))
    julia_type = get(PATTERN_TYPE_MAP, constraint.name, nothing)
    julia_type === nothing && throw(TranslationError("Unsupported pattern constraint: $(constraint.name)"))
    "::$julia_type"
end

# Validate each parameter before emitting a Julia signature.
function _strip_pattern(e::MExpr, index::Int)::String
    if is_head(e, "Pattern")
        length(e.args) == 2 && e.args[1] isa MSymbol || throw(TranslationError("Invalid named pattern"))
        var_str = e.args[1].name
        blank = e.args[2]
    else
        var_str = "_p$index"
        blank = e
    end
    is_head(blank, "Blank") || throw(TranslationError("Function parameters require blank patterns"))
    var_str * _pattern_type(blank)
end

function _translate_function(args::Vector{MExpr}, ctx::TranslationContext)::String
    if length(args) == 1
        body = args[1]
        tuple_name = "_w2j_args"
        while _contains_symbol(body, tuple_name)
            tuple_name *= "_"
        end
        bodyctx = TranslationContext(ctx.sequences, tuple_name, ctx.requirements)
        return "($tuple_name...) -> $(_translate(body, PREC_LOW, bodyctx))"
    elseif length(args) == 2
        vars_node, body = args
        vars = is_head(vars_node, "List") ? vars_node.args : MExpr[vars_node]
        all(v -> v isa MSymbol, vars) || throw(TranslationError("Function parameters must be symbols"))
        sequences = setdiff(ctx.sequences, Set(v.name for v in vars))
        ctx = TranslationContext(sequences, nothing, ctx.requirements)
        extra_name = "_w2j_extra"
        while _contains_symbol(body, extra_name) || any(v -> v.name == extra_name, vars)
            extra_name *= "_"
        end
        params = join((v.name for v in vars), ", ")
        isempty(params) || (params *= ", ")
        return "($params$extra_name...) -> $(_translate(body, PREC_LOW, ctx))"
    end
    throw(TranslationError("Function requires 1 or 2 args, got $(length(args))"))
end

# Recursively find the maximum slot index in an expression
function _max_slot(e::MExpr)::Int
    if is_head(e, "Slot")
        isempty(e.args) && return 1
        e.args[1] isa MInteger && return e.args[1].value
        return 1
    end
    e isa MExprNode || return 0
    is_head(e, "Function") && return 0
    max(_max_slot(e.head), maximum((_max_slot(a) for a in e.args); init=0))
end

function _has_slot_sequence(e::MExpr)::Bool
    is_head(e, "SlotSequence") && return true
    e isa MExprNode || return false
    is_head(e, "Function") && return false
    _has_slot_sequence(e.head) || any(_has_slot_sequence, e.args)
end

function _slot_index(e::MExprNode)
    isempty(e.args) && return 1
    length(e.args) == 1 && e.args[1] isa MInteger && e.args[1].value > 0 ||
        throw(TranslationError("Slots require a positive integer index; #0 is unsupported"))
    e.args[1].value
end
