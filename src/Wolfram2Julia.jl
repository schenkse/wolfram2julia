module Wolfram2Julia

include("token.jl")
include("ast.jl")
include("lexer.jl")
include("parser.jl")
include("translator.jl")
include("cli.jl")

# Public API
export translate_string, translate_file, main

# AST types
export MExpr, MInteger, MReal, MSymbol, MString, MExprNode
export is_head, head_name

# Lexer
export Token, TokenKind, tokenize
export TK_INTEGER, TK_REAL, TK_SYMBOL, TK_STRING
export TK_LBRACKET, TK_RBRACKET, TK_LPAREN, TK_RPAREN, TK_LBRACE, TK_RBRACE, TK_COMMA
export TK_SEMICOLON, TK_SETDELAYED, TK_SET, TK_RULEDELAYED, TK_RULE
export TK_PLUS, TK_MINUS, TK_TIMES, TK_DIVIDE, TK_POWER, TK_BANG
export TK_AT, TK_ATAT, TK_SLASHDOT
export TK_BLANK, TK_BLANKSEQ, TK_BLANKSEQSEQ
export TK_SLOT, TK_SLOTSEQ, TK_AMPERSAND
export TK_EOF

# Parser
export parse_string, ParseError

# Translator
export translate, TranslationError

end
