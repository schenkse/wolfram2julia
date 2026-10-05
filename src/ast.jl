abstract type MExpr end

struct MInteger <: MExpr
    value::Union{Int64,BigInt}
end

Base.:(==)(a::MInteger, b::MInteger) = a.value == b.value

struct MReal <: MExpr
    value::Float64
    literal::String
end

MReal(value::Real) = MReal(Float64(value), string(Float64(value)))
Base.:(==)(a::MReal, b::MReal) = a.value == b.value

struct MSymbol <: MExpr
    name::String
end

struct MString <: MExpr
    value::String
end

struct MExprNode <: MExpr
    head::MExpr
    args::Vector{MExpr}
    line::Int
    col::Int
end

MExprNode(head::MExpr, args::Vector{MExpr}) = MExprNode(head, args, 0, 0)
Base.:(==)(a::MExprNode, b::MExprNode) = a.head == b.head && a.args == b.args

# Convenience constructor: MExprNode("Plus", a, b)
MExprNode(head::String, args::MExpr...; line::Int=0, col::Int=0) = MExprNode(MSymbol(head), collect(MExpr, args), line, col)
MExprNode(head::String, args::Vector{MExpr}; line::Int=0, col::Int=0) = MExprNode(MSymbol(head), args, line, col)

# Helpers
function is_head(e::MExpr, name::String)
    e isa MExprNode && e.head isa MSymbol && e.head.name == name
end

function head_name(e::MExpr)
    e isa MExprNode && e.head isa MSymbol ? e.head.name : nothing
end

# Pretty-print as indented tree
function Base.show(io::IO, e::MExpr)
    _show_tree(io, e, 0)
end

function _show_tree(io::IO, e::MExpr, indent::Int)
    pad = "  "^indent
    if e isa MInteger
        print(io, pad, "MInteger($(e.value))")
    elseif e isa MReal
        print(io, pad, "MReal($(e.value))")
    elseif e isa MSymbol
        print(io, pad, "MSymbol($(e.name))")
    elseif e isa MString
        print(io, pad, "MString($(repr(e.value)))")
    elseif e isa MExprNode
        name = e.head isa MSymbol ? e.head.name : "?"
        println(io, pad, "$(name)[")
        for (i, arg) in enumerate(e.args)
            _show_tree(io, arg, indent + 1)
            i < length(e.args) && println(io, ",")
        end
        print(io, "\n$(pad)]")
    end
end
