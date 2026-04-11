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
    "Re"      => "real",
    "Im"      => "imag",
)

# Heads that are explicitly unsupported — throw rather than emit broken Julia
const UNSUPPORTED_HEADS = ("If", "Which", "Switch", "Do", "While", "For",
                           "Dot", "Transpose", "Inverse")

# Pattern type annotation mapping: Mathematica head → Julia type
const PATTERN_TYPE_MAP = Dict(
    "Integer" => "Int",
    "Real"    => "Float64",
    "String"  => "String",
    "Symbol"  => "Symbol",
    "Complex" => "Complex",
)

# Return the natural precedence of an expression (for parenthesization)
function _natural_prec(e::MExpr)::Int
    e isa MInteger  && return PREC_ATOM
    e isa MReal     && return PREC_ATOM
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

# ─── Public entry points ────────────────────────────────────────────────────

"""
    translate(e::MExpr) -> String

Translate a single Mathematica AST node to a Julia code string.
"""
translate(e::MExpr) = _translate(e, PREC_LOW)

"""
    translate_string(source::String) -> String

Parse and translate a Wolfram Mathematica source string to Julia code.
Multiple statements (separated by `;`) are joined with newlines.
"""
function translate_string(source::String)::String
    stmts = parse_string(source)
    join((_translate(s, PREC_LOW) for s in stmts), "\n")
end

"""
    translate_file(path::String) -> String

Read a file and translate its contents.
"""
function translate_file(path::String)::String
    translate_string(read(path, String))
end

# ─── Core translator ────────────────────────────────────────────────────────

function _translate(e::MExpr, parent_prec::Int)::String
    if e isa MInteger
        return string(e.value)
    end

    if e isa MReal
        return string(e.value)
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

    if n == "Plus"
        parts = [_translate_plus_arg(a) for a in e.args]
        result = _join_plus(parts, e.args)
        return _wrap(result, e, parent_prec)
    end

    if n == "Times"
        return _wrap(_translate_times(e.args, parent_prec), e, parent_prec)
    end

    if n == "Power"
        length(e.args) == 2 || throw(TranslationError("Power requires 2 args"))
        b, ex = e.args
        bs = _translate(b, PREC_POWER)
        es = _translate(ex, PREC_POWER)
        result = "$(bs)^$(es)"
        return _wrap(result, e, parent_prec)
    end

    # ── Math functions ───────────────────────────────────────────────────────

    if n == "Sqrt"
        length(e.args) == 1 || throw(TranslationError("Sqrt requires 1 arg"))
        return "sqrt($(_translate(e.args[1], PREC_LOW)))"
    end

    if haskey(MATH_FUNC1_MAP, n)
        jname = MATH_FUNC1_MAP[n]
        length(e.args) == 1 || throw(TranslationError("$n requires 1 arg"))
        return "$(jname)($(_translate(e.args[1], PREC_LOW)))"
    end

    if n == "Log"
        length(e.args) in (1, 2) || throw(TranslationError("Log requires 1 or 2 args, got $(length(e.args))"))
        if length(e.args) == 1
            return "log($(_translate(e.args[1], PREC_LOW)))"
        elseif length(e.args) == 2
            # Log[base, x]
            return "log($(_translate(e.args[1], PREC_LOW)), $(_translate(e.args[2], PREC_LOW)))"
        end
    end

    if n == "Factorial"
        length(e.args) == 1 || throw(TranslationError("Factorial requires 1 arg"))
        return "factorial($(_translate(e.args[1], PREC_LOW)))"
    end

    # ── Definitions ─────────────────────────────────────────────────────────

    if n == "SetDelayed"
        length(e.args) == 2 || throw(TranslationError("SetDelayed requires 2 args"))
        lhs, rhs = e.args
        return _translate_setdelayed(lhs, rhs)
    end

    if n == "Set"
        length(e.args) == 2 || throw(TranslationError("Set requires 2 args"))
        lhs, rhs = e.args
        return "$(_translate(lhs, PREC_LOW)) = $(_translate(rhs, PREC_LOW))"
    end

    # ── Functions ────────────────────────────────────────────────────────────

    if n == "Function"
        return _translate_function(e.args)
    end

    if n == "Pattern"
        # Strip pattern wrapper: Pattern[x, _] → x
        length(e.args) >= 1 || throw(TranslationError("Pattern requires args"))
        return _translate(e.args[1], parent_prec)
    end

    if n == "Slot"
        n_slot = isempty(e.args) ? 1 : (e.args[1] isa MInteger ? e.args[1].value : 1)
        return "_s$(n_slot)"
    end

    if n == "SlotSequence"
        return "args..."
    end

    # ── Collections ──────────────────────────────────────────────────────────

    if n == "List"
        parts = [_translate(a, PREC_LOW) for a in e.args]
        return "[$(join(parts, ", "))]"
    end

    # ── Control expressions ──────────────────────────────────────────────────

    if n == "CompoundExpression"
        parts = MExpr[]
        for a in e.args
            a == MSymbol("Null") && continue
            push!(parts, a)
        end
        return join([_translate(a, PREC_LOW) for a in parts], "\n")
    end

    if n == "Rule"
        length(e.args) == 2 || throw(TranslationError("Rule requires 2 args"))
        return "$(_translate(e.args[1], PREC_LOW)) => $(_translate(e.args[2], PREC_LOW))"
    end

    if n == "RuleDelayed"
        length(e.args) == 2 || throw(TranslationError("RuleDelayed requires 2 args"))
        # :> delays evaluation of the RHS; represent as a thunk to preserve the distinction
        return "$(_translate(e.args[1], PREC_LOW)) => (() -> $(_translate(e.args[2], PREC_LOW)))"
    end

    # ── Explicitly unsupported constructs ────────────────────────────────────

    if n !== nothing && n in UNSUPPORTED_HEADS
        throw(TranslationError("$n is not yet supported"))
    end

    # ── Generic function call fallback ───────────────────────────────────────

    head_str = _translate(e.head, PREC_LOW)
    arg_strs = [_translate(a, PREC_LOW) for a in e.args]
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
function _translate_plus_arg(a::MExpr)::String
    if is_head(a, "Times") && !isempty(a.args) && _is_neg_one(a.args[1])
        # This is a subtraction term: represent as "-x" for joining
        # We'll handle sign during join
        inner = length(a.args) == 2 ? a.args[2] :
                MExprNode("Times", a.args[2:end])
        return "- $(_translate(inner, PREC_MUL))"
    end
    _translate(a, PREC_ADD)
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
function _translate_times(args::Vector{MExpr}, parent_prec::Int)::String
    isempty(args) && return "1"

    # Detect unary negation: Times[-1, x]
    if length(args) == 2 && _is_neg_one(args[1])
        inner = _translate(args[2], PREC_UNARY)
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
        # _translate(a, PREC_MUL) already inserts parens when needed via _wrap
        parts = [_translate(a, PREC_MUL) for a in nums]
        result = isempty(parts) ? "1" : join(parts, " * ")
        return neg_prefix * result
    else
        num_str = if isempty(nums)
            "1"
        else
            join([_translate(a, PREC_MUL) for a in nums], " * ")
        end
        den_str = if length(dens) == 1
            _translate(dens[1], PREC_MUL)
        else
            join([_translate(a, PREC_MUL) for a in dens], " * ")
        end
        return "$(neg_prefix)$(num_str) / $(den_str)"
    end
end

function _translate_setdelayed(lhs::MExpr, rhs::MExpr)::String
    if lhs isa MExprNode && lhs.head isa MSymbol
        fname = lhs.head.name
        var_strs = [_strip_pattern(a) for a in lhs.args]
        return "$(fname)($(join(var_strs, ", "))) = $(_translate(rhs, PREC_LOW))"
    end
    # Fallback: treat as simple assignment
    "$(_translate(lhs, PREC_LOW)) = $(_translate(rhs, PREC_LOW))"
end

function _strip_pattern(e::MExpr)::String
    if is_head(e, "Pattern")
        var_str = _translate(e.args[1], PREC_LOW)
        if length(e.args) >= 2
            blank = e.args[2]
            if is_head(blank, "Blank") && !isempty(blank.args) && blank.args[1] isa MSymbol
                julia_type = get(PATTERN_TYPE_MAP, blank.args[1].name, nothing)
                if julia_type !== nothing
                    return "$(var_str)::$(julia_type)"
                end
            end
        end
        return var_str
    end
    _translate(e, PREC_LOW)
end

function _translate_function(args::Vector{MExpr})::String
    if length(args) == 1
        # Short form: Function[body] from #expr &
        body = args[1]
        # Find max slot index
        max_slot = _max_slot(body)
        max_slot == 0 && (max_slot = 1)
        params = join(["_s$i" for i in 1:max_slot], ", ")
        body_str = _translate(body, PREC_LOW)
        return "($params) -> $body_str"
    elseif length(args) == 2
        vars_node, body = args
        if is_head(vars_node, "List")
            params = join([_translate(v, PREC_LOW) for v in vars_node.args], ", ")
            return "($params) -> $(_translate(body, PREC_LOW))"
        else
            # Single variable not wrapped in List
            return "$(_translate(vars_node, PREC_LOW)) -> $(_translate(body, PREC_LOW))"
        end
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
    isempty(e.args) && return 0
    maximum(_max_slot(a) for a in e.args)
end
