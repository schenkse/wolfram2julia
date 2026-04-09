@enum TokenKind begin
    # Literals
    TK_INTEGER
    TK_REAL
    TK_SYMBOL
    TK_STRING

    # Delimiters
    TK_LBRACKET    # [
    TK_RBRACKET    # ]
    TK_LPAREN      # (
    TK_RPAREN      # )
    TK_LBRACE      # {
    TK_RBRACE      # }
    TK_COMMA       # ,

    # Operators
    TK_SEMICOLON   # ;
    TK_SETDELAYED  # :=
    TK_SET         # =
    TK_RULEDELAYED # :>
    TK_RULE        # ->
    TK_PLUS        # +
    TK_MINUS       # -
    TK_TIMES       # *
    TK_DIVIDE      # /
    TK_POWER       # ^
    TK_BANG        # !
    TK_AT          # @
    TK_ATAT        # @@
    TK_SLASHDOT    # /.

    # Pattern
    TK_BLANK        # _
    TK_BLANKSEQ     # __
    TK_BLANKSEQSEQ  # ___

    # Slots / anonymous functions
    TK_SLOT        # #
    TK_SLOTSEQ     # ##
    TK_AMPERSAND   # &

    TK_EOF
end

struct Token
    kind::TokenKind
    lexeme::String
    line::Int
    col::Int
end

function Base.show(io::IO, t::Token)
    print(io, "Token($(t.kind), $(repr(t.lexeme)), $(t.line):$(t.col))")
end
