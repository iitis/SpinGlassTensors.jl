export
    contract_left,
    contract_down,
    contract_up,
    overlap_density_matrix

LinearAlgebra.norm(ψ::QMps) = sqrt(abs(dot(ψ, ψ)))

Base.:(*)(ϕ::QMps, ψ::QMps) = dot(ϕ, ψ)
Base.:(*)(W::QMpo, ψ::QMps) = dot(W, ψ)
Base.:(*)(ψ::QMps, W::QMpo) = dot(ψ, W)

function LinearAlgebra.dot(ψ::QMps{T}, ϕ::QMps{T}) where T <: Real
    @assert ψ.sites == ϕ.sites
    C = ones(T, 1, 1)
    for i ∈ ϕ.sites
        A, B = ϕ[i], ψ[i]
        @tensor C[x, y] := conj(B)[β, σ, x] * C[β, α] * A[α, σ, y] order = (α, β, σ)
    end
    tr(C)
end

function LinearAlgebra.dot(ψ::QMpo{R}, ϕ::QMps{R}) where R <: Real
    D = Dict{Site, Tensor{R}}()
    for i ∈ reverse(ϕ.sites)
        T = sort(collect(ψ[i]), by = x -> x[begin])
        TT = ϕ[i]
        for (_, v) ∈ reverse(T) TT = contract_up(TT, v) end

        mps_li = left_nbrs_site(i, ϕ.sites)
        mpo_li = left_nbrs_site(i, ψ.sites)
        while mpo_li > mps_li
            TT = contract_left(TT, ψ[mpo_li][0])
            mpo_li = left_nbrs_site(mpo_li, ψ.sites)
        end
        push!(D, i => TT)
    end
    QMps(D)
end

function LinearAlgebra.dot(ϕ::QMps{R}, ψ::QMpo{R}) where R <: Real
    D = Dict{Site, Tensor{R}}()
    for i ∈ reverse(ϕ.sites)
        T = sort(collect(ψ[i]), by = x -> x[begin])
        TT = ϕ[i]
        for (_, v) ∈ T TT = contract_down(v, TT) end

        mps_li = left_nbrs_site(i, ϕ.sites)
        mpo_li = left_nbrs_site(i, ψ.sites)
        while mpo_li > mps_li
            TT = contract_left(TT, ψ[mpo_li][0])
            mpo_li = left_nbrs_site(mpo_li, ψ.sites)
        end
        push!(D, i => TT)
    end
    QMps(D)
end

function contract_left(A::Array{T, 3}, B::Matrix{T}) where T <: Real
    @matmul C[(x, y), u, r] := sum(σ) B[y, σ] * A[(x, σ), u, r] (σ ∈ 1:size(B, 2))
end

function contract_left(A::Array{T, 3}, M::CentralTensor{T}) where T <: Real
    B = Array(M)
    @matmul C[(x, y), u, r] := sum(σ) B[y, σ] * A[(x, σ), u, r] (σ ∈ 1:size(B, 2))
end

function contract_up(A::Array{T, 3}, B::Matrix{T}) where T <: Real
    @tensor C[l, u, r] := B[u, σ] * A[l, σ, r]
end

function contract_down(A::Matrix{T}, B::Array{T, 3}) where T <: Real
    @tensor C[l, d, r] := A[σ, d] * B[l, σ, r]
end

function contract_up(A::Array{T, 3}, B::Array{T, 4}) where T <: Real
    @matmul C[(x, y), z, (b, a)] := sum(σ) B[y, z, a, σ] * A[x, σ, b]
end

function contract_down(A::Array{T, 4}, B::Array{T, 3}) where T <: Real
    @matmul C[(x, y), z, (b, a)] := sum(σ) A[y, σ, a, z] * B[x, σ, b]
end

contract_down(M::CentralTensor{T}, A::Array{T, 3}) where T <: Real = attach_central_left(A, M)
contract_down(M::DiagonalTensor{T}, A::Array{T, 3}) where T <: Real = attach_central_left(A, M)

function contract_up(A::Array{T, 3}, B::SiteTensor{T}) where T <: Real
    #sal, _, sar = size(A)
    #sbl, sbt, sbr = maximum.(B.projs[1:3])
    #C = zeros(T, sal, sbl, sbt, sar, sbr)
    C = zeros(A, B)
    for (σ, lexp) ∈ enumerate(B.loc_exp)
        AA = @inbounds @view A[:, B.projs[4][σ], :]
        @inbounds C[:, B.projs[1][σ], B.projs[2][σ], :, B.projs[3][σ]] += lexp .* AA
    end
    @cast CC[(x, y), z, (b, a)] := C[x, y, z, b, a]
end

contract_up(A::Array{T, 3}, M::CentralTensor{T}) where T <: Real = attach_central_right(A, M)
contract_up(A::Array{T, 3}, M::DiagonalTensor{T}) where T <: Real = attach_central_right(A, M)

function contract_down(A::SiteTensor{T}, B::Array{T, 3}) where T <: Real
    #sal, _, sar = size(B)
    #sbl, _, sbt, sbr = maximum.(A.projs[1:4])
    #C = zeros(T, sal, sbl, sbr, sar, sbt)

    C = zeros(A, B)
    for (σ, lexp) ∈ enumerate(A.loc_exp)
        AA = @inbounds @view B[:, A.projs[2][σ], :]
        @inbounds C[:, A.projs[1][σ], A.projs[4][σ], :, A.projs[3][σ]] += lexp .* AA
    end
    @cast CC[(x, y), z, (b, a)] := C[x, y, z, b, a]
end

#TODO: get rid of dense_central_tensor
function contract_up(A::Array{T, 3}, B::VirtualTensor{T}) where T <: Real
    h = B.con
    if typeof(h) <: CentralTensor h = Array(h) end

    sal, _, sar = size(A)
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = B.projs
    @cast A4[x, k, l, y] := A[x, (k, l), y] (k ∈ 1:maximum(p_lb))

    C = zeros(T, sal, length(p_l), maximum(p_lt), maximum(p_rt), sar, length(p_r))

    for l ∈ 1:length(p_l), r ∈ 1:length(p_r)
        AA = @inbounds @view A4[:, p_lb[l], p_rb[r], :]
        @inbounds C[:, l, p_lt[l], p_rt[r], :, r] += h[p_l[l], p_r[r]] .* AA
    end
    @cast CC[(x, y), (t1, t2), (b, a)] := C[x, y, t1, t2, b, a]
    CC
end

function contract_down(A::VirtualTensor{T}, B::Array{T, 3}) where T <: Real
    h = A.con

    if typeof(h) <: CentralTensor h = Array(h) end

    sal, _, sar = size(B)

    p_lb, p_l, p_lt, p_rb, p_r, p_rt = A.projs
    @cast B4[x, k, l, y] := B[x, (k, l), y] (k ∈ 1:maximum(p_lt))

    C = zeros(T, sal, length(p_l), maximum(p_lb), maximum(p_rb), sar, length(p_r))

    for l ∈ 1:length(p_l), r ∈ 1:length(p_r)
        BB = @inbounds @view B4[:, p_lt[l], p_rt[r], :]
        @inbounds C[:, l, p_lb[l], p_rb[r], :, r] += h[p_l[l], p_r[r]] .* BB
    end
    @cast CC[(x, y), (t1, t2), (b, a)] := C[x, y, t1, t2, b, a]
    CC
end

function overlap_density_matrix(ϕ::QMps{T}, ψ::QMps{T}, k::Site) where T <: Real
    @assert ψ.sites == ϕ.sites
    C = _overlap_forward(ϕ, ψ, k)
    D = _overlap_backwards(ϕ, ψ, k)
    A, B = ψ[k], ϕ[k]
    @tensor E[x, y] := C[b, a] * conj(B)[b, x, β] * A[a, y, α] * D[β, α]
end

function _overlap_forward(ϕ::QMps{T}, ψ::QMps{T}, k::Site) where T <: Real
    C = ones(T, 1, 1)
    for i ∈ ψ.sites
        if i < k
            A, B = ψ[i], ϕ[i]
            @tensor C[x, y] := conj(B)[β, σ, x] * C[β, α] * A[α, σ, y] order = (α, β, σ)
        end
    end
    C
end

function _overlap_backwards(ϕ::QMps{T}, ψ::QMps{T}, k::Site) where T <: Real
    D = ones(T, 1, 1)
    for i ∈ reverse(ψ.sites)
        if i > k
            A, B = ψ[i], ϕ[i]
            @tensor D[x, y] := conj(B)[x, σ, β] * D[β, α] * A[y, σ, α] order = (α, β, σ)
        end
    end
    D
end
