export dot, contract_left, contract_up, contract_down


function LinearAlgebra.dot(ψ::Mps, ϕ::Mps)
    T = promote_type(eltype(ψ.tensors[1]), eltype(ϕ.tensors[1]))
    C = ones(T, 1, 1)

    for (i,j) ∈ zip(ψ.sites, ϕ.sites)
        A = ψ.tensors[i]
        B = ϕ.tensors[j]
        @tensor C[x, y] := conj(B)[β, σ, x] * C[β, α] * A[α, σ, y] order = (α, β, σ)
    end
    tr(C)
end


LinearAlgebra.norm(ψ::Mps) = sqrt(abs(dot(ψ, ψ)))


function LinearAlgebra.dot(ψ::Mpo, ϕ::Mps)
    D = Dict()
    for i ∈ reverse(ϕ.sites)
        T = sort(collect(ψ.tensors[i]), by = x->x[1])
        TT = ϕ.tensors[i]
        for (t, v) ∈ reverse(T)
            TT = contract_up(TT, v)
        end
            mps_li = _left_nbrs_site(i, ϕ.sites)
            mpo_li = _left_nbrs_site(i, ψ.sites)
            while mpo_li > mps_li
                TT = contract_left(TT, ψ.tensors[mpo_li][0])
                mpo_li = _left_nbrs_site(mpo_li, ψ.sites)
            end
        push!(D, i => TT)
    end
    Mps(D)
end


function LinearAlgebra.dot(ψ, ϕ::Mps)
    T = promote_type(eltype(ψ[1]), eltype(ϕ.tensors[1]))
    D = Dict()
    for (i, A) in enumerate(ψ)
        B = ϕ.tensors[i]
        C = contract_up(B, A)
        push!(D, i=>C)
    end
    Mps(D)
end


Base.:(*)(W::Mpo, ψ::Mps) = dot(W, ψ)


function contract_left(A::AbstractArray{T,3}, B::AbstractMatrix{T}) where {T}
    @cast C[(x, y), u, r] := sum(σ) B[y, σ] * A[(x, σ), u, r] (σ ∈ 1:size(B, 2))
    C
end


function contract_up(A::AbstractArray{T,3}, B::AbstractArray{T,2}) where {T}
    @tensor C[l, u, r] := B[u, σ] * A[l, σ, r]
    C
end


function contract_up(A::AbstractArray{T,3}, B::AbstractArray{T,4}) where {T}
    @cast C[(x, y), z, (b, a)] := sum(σ) B[y, z, a, σ] * A[x, σ, b]
    C
end