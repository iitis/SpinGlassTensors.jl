export contract_left,contract_down, contract_up, dot

LinearAlgebra.dot(ψ::QMps, ϕ::QMps) = dot(MPS(ψ), MPS(ϕ))
LinearAlgebra.norm(ψ::QMps) = sqrt(abs(dot(ψ, ψ)))

function LinearAlgebra.dot(ψ::QMpo, ϕ::QMps)
    D = Dict()
    for i ∈ reverse(ϕ.sites)
        T = sort(collect(ψ[i]), by = x -> x[1])
        TT = ϕ[i]
        for (t, v) ∈ reverse(T) TT = contract_up(TT, v) end

        mps_li = _left_nbrs_site(i, ϕ.sites)
        mpo_li = _left_nbrs_site(i, ψ.sites)
        while mpo_li > mps_li
            TT = contract_left(TT, ψ[mpo_li][0])
            mpo_li = _left_nbrs_site(mpo_li, ψ.sites)
        end
        push!(D, i => TT)
    end
    QMps(D)
end

function LinearAlgebra.dot(ϕ::QMps, ψ::QMpo)
    D = Dict()
    for i ∈ reverse(ϕ.sites)
        T = sort(collect(ψ[i]), by = x -> x[1])
        TT = ϕ[i]
        for (t, v) ∈ reverse(T) TT = contract_down(v, TT) end

        mps_li = _left_nbrs_site(i, ϕ.sites)
        mpo_li = _left_nbrs_site(i, ψ.sites)
        while mpo_li > mps_li
            TT = contract_left(TT, ψ[mpo_li][0])
            mpo_li = _left_nbrs_site(mpo_li, ψ.sites)
        end
        push!(D, i => TT)
    end
    QMps(D)
end

function LinearAlgebra.dot(W, ϕ::QMps)
    QMps(Dict(i => contract_up(ϕ[i], A) for (i, A) ∈ enumerate(W)))
end

function LinearAlgebra.dot(ϕ::QMps, W)
    QMps(Dict(i => contract_down(A, ϕ[i]) for (i, A) ∈ enumerate(W)))
end
Base.:(*)(W::QMpo, ψ::QMps) = dot(W, ψ)
Base.:(*)(ψ::QMps, W::QMpo) = dot(ψ, W)

function contract_left(A::AbstractArray{T, 3}, B::AbstractMatrix{T}) where T
    @cast C[(x, y), u, r] := sum(σ) B[y, σ] * A[(x, σ), u, r] (σ ∈ 1:size(B, 2))
    C
end

function contract_up(A::AbstractArray{T, 3}, B::AbstractArray{T, 2}) where T
    @tensor C[l, u, r] := B[u, σ] * A[l, σ, r]
    C
end

function contract_down(A::AbstractArray{T, 2}, B::AbstractArray{T, 3}) where T
    @tensor C[l, d, r] := A[σ, d] * B[l, σ, r]
    C
end

function contract_up(A::AbstractArray{T, 3}, B::AbstractArray{T, 4}) where T
    @matmul C[(x, y), z, (b, a)] := sum(σ) B[y, z, a, σ] * A[x, σ, b]
    C
end


function contract_down(A::AbstractArray{T, 4}, B::AbstractArray{T, 3}) where T
    @matmul C[(x, y), z, (b, a)] := sum(σ) A[y, σ, a, z] * B[x, σ, b]
    C
end

# This has to be improved
function contract_up(A::AbstractArray{T, 3}, B::SparseSiteTensor) where T
    sal, sac, sar = size(A)
    sbl, sbt, sbr = maximum.(B.projs[1:3])
    C = zeros(sal, sbl, sbt, sar, sbr)

    for (σ, lexp) ∈ enumerate(B.loc_exp)
        AA = @view A[:, B.projs[4][σ], :]
        C[:, B.projs[1][σ], B.projs[2][σ], :, B.projs[3][σ]] += lexp .* AA
    end
    @cast CC[(x, y), z, (b, a)] := C[x, y, z, b, a]
    CC
end
