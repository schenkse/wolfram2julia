struct LexError <: Exception
    message::String
    line::Int
    col::Int
end

function Base.showerror(io::IO, e::LexError)
    print(io, "LexError at $(e.line):$(e.col): $(e.message)")
end

mutable struct Lexer
    source::String
    pos::Int    # current byte position (1-based)
    line::Int
    col::Int
end

Lexer(source::String) = Lexer(source, 1, 1, 1)

# Peek current character without advancing
function _cur(lx::Lexer)
    lx.pos > ncodeunits(lx.source) ? '\0' : lx.source[lx.pos]
end

# Peek one ahead
function _peek(lx::Lexer, offset::Int = 1)
    p = nextind(lx.source, lx.pos, offset)
    p > ncodeunits(lx.source) ? '\0' : lx.source[p]
end

# Advance one character
function _advance!(lx::Lexer)
    c = _cur(lx)
    lx.pos = nextind(lx.source, lx.pos)
    if c == '\n'
        lx.line += 1
        lx.col = 1
    else
        lx.col += 1
    end
    c
end

# Skip whitespace (but NOT between a symbol and a blank — callers handle that)
function _skip_whitespace!(lx::Lexer)
    while lx.pos <= ncodeunits(lx.source) && isspace(_cur(lx))
        _advance!(lx)
    end
end

# Skip nested Mathematica comments (* ... *)
function _skip_comment!(lx::Lexer)
    # Assumes we just saw '(' and '*'
    _advance!(lx)  # consume '('
    _advance!(lx)  # consume '*'
    depth = 1
    while lx.pos <= ncodeunits(lx.source) && depth > 0
        c = _cur(lx)
        n = _peek(lx)
        if c == '(' && n == '*'
            _advance!(lx); _advance!(lx)
            depth += 1
        elseif c == '*' && n == ')'
            _advance!(lx); _advance!(lx)
            depth -= 1
        else
            _advance!(lx)
        end
    end
end

function _make_token(lx::Lexer, kind::TokenKind, lexeme::String, line::Int, col::Int)
    Token(kind, lexeme, line, col)
end

function next_token!(lx::Lexer)::Token
    # Skip whitespace and comments
    while true
        _skip_whitespace!(lx)
        if lx.pos <= ncodeunits(lx.source) && _cur(lx) == '(' && _peek(lx) == '*'
            _skip_comment!(lx)
        else
            break
        end
    end

    if lx.pos > ncodeunits(lx.source)
        return Token(TK_EOF, "", lx.line, lx.col)
    end

    line, col = lx.line, lx.col
    c = _cur(lx)

    # String literal
    if c == '"'
        _advance!(lx)
        buf = IOBuffer()
        while lx.pos <= ncodeunits(lx.source)
            ch = _cur(lx)
            if ch == '"'
                _advance!(lx)
                break
            elseif ch == '\\'
                _advance!(lx)
                esc = _cur(lx)
                _advance!(lx)
                write(buf, esc == 'n' ? '\n' :
                           esc == 't' ? '\t' :
                           esc == '"' ? '"'  :
                           esc == '\\' ? '\\' : esc)
            else
                write(buf, _advance!(lx))
            end
        end
        return Token(TK_STRING, String(take!(buf)), line, col)
    end

    # Numbers
    if isdigit(c)
        return _read_number!(lx, line, col)
    end

    # Symbols (including pattern head like Sin, x)
    if isletter(c) || c == '$'
        return _read_symbol!(lx, line, col)
    end

    # Slot: ## or #n or #
    if c == '#'
        _advance!(lx)
        if _cur(lx) == '#'
            _advance!(lx)
            # ##n
            buf = IOBuffer()
            write(buf, "##")
            while isdigit(_cur(lx))
                write(buf, _advance!(lx))
            end
            return Token(TK_SLOTSEQ, String(take!(buf)), line, col)
        else
            # #n
            buf = IOBuffer()
            write(buf, '#')
            while isdigit(_cur(lx))
                write(buf, _advance!(lx))
            end
            return Token(TK_SLOT, String(take!(buf)), line, col)
        end
    end

    # Blank tokens (standalone _ not preceded by symbol — symbol+_ is handled in _read_symbol!)
    if c == '_'
        return _read_blank!(lx, line, col)
    end

    # Operators and delimiters
    _advance!(lx)  # consume c

    if c == '['  return Token(TK_LBRACKET,  "[",  line, col) end
    if c == ']'  return Token(TK_RBRACKET,  "]",  line, col) end
    if c == '('  return Token(TK_LPAREN,    "(",  line, col) end
    if c == ')'  return Token(TK_RPAREN,    ")",  line, col) end
    if c == '{'  return Token(TK_LBRACE,    "{",  line, col) end
    if c == '}'  return Token(TK_RBRACE,    "}",  line, col) end
    if c == ','  return Token(TK_COMMA,     ",",  line, col) end
    if c == ';'  return Token(TK_SEMICOLON, ";",  line, col) end
    if c == '+'  return Token(TK_PLUS,      "+",  line, col) end
    if c == '^'  return Token(TK_POWER,     "^",  line, col) end
    if c == '!'  return Token(TK_BANG,      "!",  line, col) end
    if c == '&'  return Token(TK_AMPERSAND, "&",  line, col) end

    if c == '-'
        if _cur(lx) == '>'
            _advance!(lx)
            return Token(TK_RULE, "->", line, col)
        end
        return Token(TK_MINUS, "-", line, col)
    end

    if c == '*'
        # Check for *^ (Mathematica scientific notation — handled in _read_number!)
        # Here we just emit TK_TIMES
        return Token(TK_TIMES, "*", line, col)
    end

    if c == '/'
        if _cur(lx) == '.'
            _advance!(lx)
            return Token(TK_SLASHDOT, "/.", line, col)
        end
        return Token(TK_DIVIDE, "/", line, col)
    end

    if c == '@'
        if _cur(lx) == '@'
            _advance!(lx)
            return Token(TK_ATAT, "@@", line, col)
        end
        return Token(TK_AT, "@", line, col)
    end

    if c == ':'
        if _cur(lx) == '='
            _advance!(lx)
            return Token(TK_SETDELAYED, ":=", line, col)
        elseif _cur(lx) == '>'
            _advance!(lx)
            return Token(TK_RULEDELAYED, ":>", line, col)
        end
        # Lone ':' — not in v1 scope, emit as a symbol to avoid crash
        return Token(TK_SYMBOL, ":", line, col)
    end

    if c == '='
        return Token(TK_SET, "=", line, col)
    end

    # Unknown character — error with location
    throw(LexError("Unexpected character '$(c)'", line, col))
end

function _read_number!(lx::Lexer, line::Int, col::Int)::Token
    buf = IOBuffer()
    is_real = false

    while isdigit(_cur(lx))
        write(buf, _advance!(lx))
    end

    if _cur(lx) == '.' && isdigit(_peek(lx))
        is_real = true
        write(buf, _advance!(lx))  # '.'
        while isdigit(_cur(lx))
            write(buf, _advance!(lx))
        end
    end

    # Mathematica scientific notation: 1.5*^3  →  1500.0
    if _cur(lx) == '*' && _peek(lx) == '^'
        is_real = true
        _advance!(lx)  # '*'
        _advance!(lx)  # '^'
        exp_buf = IOBuffer()
        if _cur(lx) == '-' || _cur(lx) == '+'
            write(exp_buf, _advance!(lx))
        end
        while isdigit(_cur(lx))
            write(exp_buf, _advance!(lx))
        end
        base_str = String(take!(buf))
        exp_str  = String(take!(exp_buf))
        val = parse(Float64, base_str) * 10.0^parse(Int, exp_str)
        return Token(TK_REAL, string(val), line, col)
    end

    s = String(take!(buf))
    is_real ? Token(TK_REAL, s, line, col) : Token(TK_INTEGER, s, line, col)
end

function _read_symbol!(lx::Lexer, line::Int, col::Int)::Token
    buf = IOBuffer()
    while lx.pos <= ncodeunits(lx.source) && (isletter(_cur(lx)) || isdigit(_cur(lx)) || _cur(lx) == '$')
        write(buf, _advance!(lx))
    end
    name = String(take!(buf))

    # Immediately check for blank without skipping whitespace
    if _cur(lx) == '_'
        return _read_symbol_blank!(lx, name, line, col)
    end

    Token(TK_SYMBOL, name, line, col)
end

function _read_symbol_blank!(lx::Lexer, sym_name::String, line::Int, col::Int)::Token
    # We are positioned at the first '_'
    # Count consecutive underscores
    count = 0
    while _cur(lx) == '_'
        _advance!(lx)
        count += 1
        count == 3 && break
    end

    kind = count == 1 ? TK_BLANK :
           count == 2 ? TK_BLANKSEQ : TK_BLANKSEQSEQ

    # Optional head after blank: x_Integer (no whitespace allowed)
    head_name = ""
    if kind == TK_BLANK && (isletter(_cur(lx)) || _cur(lx) == '$')
        head_buf = IOBuffer()
        while lx.pos <= ncodeunits(lx.source) && (isletter(_cur(lx)) || isdigit(_cur(lx)) || _cur(lx) == '$')
            write(head_buf, _advance!(lx))
        end
        head_name = String(take!(head_buf))
    end

    lexeme = head_name == "" ? "$(sym_name)$("_"^count)" :
                               "$(sym_name)$("_"^count)$(head_name)"
    Token(kind, lexeme, line, col)
end

function _read_blank!(lx::Lexer, line::Int, col::Int)::Token
    count = 0
    while _cur(lx) == '_'
        _advance!(lx)
        count += 1
        count == 3 && break
    end
    kind = count == 1 ? TK_BLANK :
           count == 2 ? TK_BLANKSEQ : TK_BLANKSEQSEQ
    Token(kind, "_"^count, line, col)
end

function tokenize(source::String)::Vector{Token}
    lx = Lexer(source)
    tokens = Token[]
    while true
        t = next_token!(lx)
        push!(tokens, t)
        t.kind == TK_EOF && break
    end
    tokens
end
