# @memoize Dict

@memoize Dict function aux_cusparse(::Type{R}, n::Int64) where R <: Real
    CuArray(1:n+1), CUDA.ones(R, n)
end

function CUDA.CUSPARSE.CuSparseMatrixCSC(::Type{R}, p::CuArray{Int64, 1}) where R <: Real
    n = length(p)
    mp = maximum(p)
    cn, co = aux_cusparse(R, n)
    CuSparseMatrixCSC(cn, p, co, (mp, n))
end

function CUDA.CUSPARSE.CuSparseMatrixCSC(::Type{T}, p1::R, p2::R, p3::R) where {T <: Real, R <: CuArray{Int64, 1}}
    @assert length(p1) == length(p2) == length(p3)
    s1, s2 = maximum(p1), maximum(p2)
    p = p1 .+ s1 * (p2 .- 1) .+ s1 * s2 * (p3 .- 1)
    CuSparseMatrixCSC(T, p)
end

