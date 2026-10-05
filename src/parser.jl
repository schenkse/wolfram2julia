struct ParseError <: Exception
    message::String
    line::Int
    col::Int
end

function Base.showerror(io::IO, e::ParseError)
    print(io, "ParseError at $(e.line):$(e.col): $(e.message)")
end

mutable struct Parser
    tokens::Vector{Token}
    pos::Int
end

Parser(tokens::Vector{Token}) = Parser(tokens, 1)

function peek(p::Parser)::Token
    p.tokens[min(p.pos, length(p.tokens))]
end

function advance!(p::Parser)::Token
    t = peek(p)
    p.pos = min(p.pos + 1, length(p.tokens))
    t
end

function at(p::Parser, kind::TokenKind)::Bool
    peek(p).kind == kind
end

function at_any(p::Parser, kinds...)::Bool
    peek(p).kind in kinds
end

function expect!(p::Parser, kind::TokenKind)::Token
    t = peek(p)
    if t.kind != kind
        throw(ParseError("Expected $kind but got $(t.kind) (\"$(t.lexeme)\")", t.line, t.col))
    end
    advance!(p)
end

# ─── Top-level ──────────────────────────────────────────────────────────────

function parse_program!(p::Parser)::Vector{MExpr}
    stmts = MExpr[]
    while !at(p, TK_EOF)
        push!(stmts, parse_compound!(p))
        # Consume trailing semicolons between top-level statements
        while at(p, TK_SEMICOLON)
            advance!(p)
            # If more content follows, continue loop; otherwise break
        end
    end
    stmts
end

# CompoundExpression: a; b; c
function parse_compound!(p::Parser)::MExpr
    first = parse_set!(p)
    if !at(p, TK_SEMICOLON)
        return first
    end

    args = MExpr[first]
    while at(p, TK_SEMICOLON)
        advance!(p)  # consume ';'
        # If next is EOF, another ';', or end of context → add Null
        if at(p, TK_EOF) || at(p, TK_SEMICOLON)
            push!(args, MSymbol("Null"))
        else
            push!(args, parse_set!(p))
        end
    end

    # Drop trailing Null
    while !isempty(args) && args[end] == MSymbol("Null")
        pop!(args)
    end

    length(args) == 1 ? args[1] : MExprNode("CompoundExpression", args)
end

# Set / SetDelayed: right-associative
function parse_set!(p::Parser)::MExpr
    lhs = parse_function_body!(p)

    if at(p, TK_SETDELAYED)
        advance!(p)
        rhs = parse_set!(p)
        return MExprNode("SetDelayed", MExpr[lhs, rhs])
    elseif at(p, TK_SET)
        advance!(p)
        rhs = parse_set!(p)
        return MExprNode("Set", MExpr[lhs, rhs])
    elseif at(p, TK_RULE)
        advance!(p)
        rhs = parse_set!(p)
        return MExprNode("Rule", MExpr[lhs, rhs])
    elseif at(p, TK_RULEDELAYED)
        advance!(p)
        rhs = parse_set!(p)
        return MExprNode("RuleDelayed", MExpr[lhs, rhs])
    end

    lhs
end

# Function short-form: expr & wraps the whole lhs as Function body
function parse_function_body!(p::Parser)::MExpr
    expr = parse_add!(p)
    if at(p, TK_AMPERSAND)
        advance!(p)
        return MExprNode("Function", MExpr[expr])
    end
    expr
end

# Plus / Minus — n-ary accumulation
function parse_add!(p::Parser)::MExpr
    left = parse_mul!(p)
    args = MExpr[left]

    while at_any(p, TK_PLUS, TK_MINUS)
        op = advance!(p)
        right = parse_mul!(p)
        if op.kind == TK_MINUS
            # a - b  →  Plus[a, Times[-1, b]]
            push!(args, MExprNode("Times", MExpr[MInteger(-1), right]))
        else
            push!(args, right)
        end
    end

    length(args) == 1 ? args[1] : MExprNode("Plus", args)
end

# Times / Divide — n-ary accumulation
function parse_mul!(p::Parser)::MExpr
    left = parse_unary!(p)
    args = MExpr[left]

    while at_any(p, TK_TIMES, TK_DIVIDE)
        op = advance!(p)
        right = parse_unary!(p)
        if op.kind == TK_DIVIDE
            # a / b  →  Times[a, Power[b, -1]]
            push!(args, MExprNode("Power", MExpr[right, MInteger(-1)]))
        else
            push!(args, right)
        end
    end

    length(args) == 1 ? args[1] : MExprNode("Times", args)
end

# Unary minus
function parse_unary!(p::Parser)::MExpr
    if at(p, TK_MINUS)
        advance!(p)
        operand = parse_power!(p)
        return MExprNode("Times", MExpr[MInteger(-1), operand])
    end
    parse_power!(p)
end

# Power — right-associative
function parse_power!(p::Parser)::MExpr
    base = parse_postfix!(p)
    if at(p, TK_POWER)
        advance!(p)
        exp = parse_unary!(p)   # recurse for right-assoc
        return MExprNode("Power", MExpr[base, exp])
    end
    base
end

# Postfix: Factorial, pattern blanks (already encoded in token lexeme)
function parse_postfix!(p::Parser)::MExpr
    expr = parse_call!(p)

    while true
        if at(p, TK_BANG)
            advance!(p)
            expr = MExprNode("Factorial", MExpr[expr])
        else
            break
        end
    end

    expr
end

# Function application: f[args] and f@x
function parse_call!(p::Parser)::MExpr
    expr = parse_atom!(p)

    while true
        if at(p, TK_LBRACKET)
            advance!(p)
            args = parse_arglist!(p)
            expect!(p, TK_RBRACKET)
            expr = MExprNode(expr, args)
        elseif at(p, TK_AT)
            advance!(p)
            arg = parse_call!(p)
            expr = MExprNode(expr, MExpr[arg])
        else
            break
        end
    end

    expr
end

function parse_arglist!(p::Parser)::Vector{MExpr}
    args = MExpr[]
    if at(p, TK_RBRACKET) || at(p, TK_RBRACE)
        return args
    end
    push!(args, parse_set!(p))
    while at(p, TK_COMMA)
        advance!(p)
        push!(args, parse_set!(p))
    end
    args
end

# Atom: number, symbol (with optional pattern), string, grouped expr, list, slot
function parse_atom!(p::Parser)::MExpr
    t = peek(p)

    if t.kind == TK_INTEGER
        advance!(p)
        value = tryparse(Int64, t.lexeme)
        return MInteger(value === nothing ? parse(BigInt, t.lexeme) : value)
    end

    if t.kind == TK_REAL
        advance!(p)
        return MReal(Meta.parse(t.lexeme), t.lexeme)
    end

    if t.kind == TK_STRING
        advance!(p)
        return MString(t.lexeme)
    end

    if t.kind == TK_SYMBOL
        advance!(p)
        sym = MSymbol(t.lexeme)
        return sym
    end

    # Pattern blanks that appear after a symbol are embedded in the token lexeme
    # e.g. token TK_BLANK with lexeme "x_" or "x_Integer"
    if t.kind in (TK_BLANK, TK_BLANKSEQ, TK_BLANKSEQSEQ)
        advance!(p)
        return _parse_blank_token(t)
    end

    # Slot: # or #2
    if t.kind == TK_SLOT
        advance!(p)
        n = length(t.lexeme) > 1 ? parse(Int, t.lexeme[2:end]) : 1
        return MExprNode("Slot", MExpr[MInteger(n)])
    end

    if t.kind == TK_SLOTSEQ
        advance!(p)
        n = length(t.lexeme) > 2 ? parse(Int, t.lexeme[3:end]) : 1
        return MExprNode("SlotSequence", MExpr[MInteger(n)])
    end

    # Parenthesized expression
    if t.kind == TK_LPAREN
        advance!(p)
        expr = parse_set!(p)
        expect!(p, TK_RPAREN)
        return expr
    end

    # List: {a, b, c}
    if t.kind == TK_LBRACE
        advance!(p)
        args = MExpr[]
        if !at(p, TK_RBRACE)
            push!(args, parse_set!(p))
            while at(p, TK_COMMA)
                advance!(p)
                push!(args, parse_set!(p))
            end
        end
        expect!(p, TK_RBRACE)
        return MExprNode("List", args)
    end

    throw(ParseError("Unexpected token $(t.kind) (\"$(t.lexeme)\")", t.line, t.col))
end

# Decode a blank token whose lexeme encodes "sym_" or "sym__" or "sym_Head"
function _parse_blank_token(t::Token)::MExpr
    lexeme = t.lexeme

    # Count leading underscores from the right part
    # Find the split: everything before the first '_' is the symbol name
    # Everything from the first '_' is the blank part
    blank_start = findfirst('_', lexeme)

    if blank_start === nothing
        # Just a symbol somehow — shouldn't happen
        return MSymbol(lexeme)
    end

    sym_part   = lexeme[1:prevind(lexeme, blank_start)]
    blank_part = lexeme[blank_start:end]

    # Count underscores
    ucount = 0
    i = 1
    while i <= ncodeunits(blank_part) && blank_part[i] == '_'
        ucount += 1
        i = nextind(blank_part, i)
    end
    head_part = blank_part[i:end]  # e.g. "Integer" or ""

    blank_kind = ucount == 1 ? "Blank" :
                 ucount == 2 ? "BlankSequence" : "BlankNullSequence"

    blank_node = isempty(head_part) ?
        MExprNode(blank_kind, MExpr[]) :
        MExprNode(blank_kind, MExpr[MSymbol(head_part)])

    if isempty(sym_part)
        # Standalone blank with no symbol: _, __, ___
        return blank_node
    else
        return MExprNode("Pattern", MExpr[MSymbol(sym_part), blank_node])
    end
end

# ─── Public API ─────────────────────────────────────────────────────────────

function parse_string(source::String)::Vector{MExpr}
    tokens = tokenize(source)
    p = Parser(tokens)
    parse_program!(p)
end
