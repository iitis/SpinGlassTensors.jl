export
    zipper,
    corner_matrix,
    CornerTensor

 struct CornerTensor{T <: Real}
    C::Tensor{T, 3}
    M::MpoTensor{T, 4}
    B::Tensor{T, 3}

    function CornerTensor(C, M, B)
        T = promote_type(eltype.((C, M, B))...)
        new{T}(C, M, B)
    end
end

struct Adjoint{T, S <: CornerTensor}
    parent::S

    function Adjoint{T}(ten::CornerTensor{S}) where {T, S}
        F = promote_type(T, S)
        new{F, CornerTensor{F}}(ten)
    end
end

"""
input ϕ (results) should be canonized :left (:right)
# """
function zipper(ψ::QMpo{R}, ϕ::QMps{R}; method::Symbol=:svd, Dcut::Int=typemax(Int), tol=eps(), kwargs...) where R <: Real
    onGPU = ψ.onGPU && ϕ.onGPU
    # @assert is_left_normalized(ϕ)
    D = TensorMap{R}()
    C = onGPU ? CUDA.ones(R, 1, 1, 1) : ones(R, 1, 1, 1)
    mpo_li = last(ψ.sites)

    for i ∈ reverse(ϕ.sites)
        while mpo_li > i
            C = contract_matrix_tensor3(ψ[mpo_li], C)
            mpo_li = left_nbrs_site(mpo_li, ψ.sites)
        end
        @assert mpo_li == i "Mismatch between QMpo and QMps sites."
        mpo_li = left_nbrs_site(mpo_li, ψ.sites)

        CM = CornerTensor(C, ψ[i], ϕ[i])
        U, Σ, V = svd_corner_matrix(CM, method, Dcut, tol; toGPU=onGPU, kwargs...)
        nΣ = sqrt(sum(Σ .^ 2))
        println("site = ", i, "  nΣ = ", nΣ)
        Σ ./= nΣ
        C = U * Diagonal(Σ)

        V = permutedims(V, (2, 1))
        if i == ϕ.sites[1] V = C * V end
        s1, s2 = size(ψ[i])
        @cast V[x, y, z] := V[x, (y, z)] (z ∈ 1:s2)
        @cast C[x, y, z] := C[(x, y), z] (y ∈ 1:s1)
        C = permutedims(C, (1, 3, 2))
        push!(D, i => V)
    end
    QMps(D; onGPU = onGPU)
end



# function zipper(ψ::QMpo{R}, ϕ::QMps{R}; method::Symbol=:svd, Dcut::Int=typemax(Int), tol=eps(), kwargs...) where R <: Real
#     onGPU = ψ.onGPU && ϕ.onGPU
#     # @assert is_left_normalized(ϕ)
#     D = TensorMap{R}()
#     C = onGPU ? CUDA.ones(R, 1, 1, 1) : ones(R, 1, 1, 1)
#     mpo_li = last(ψ.sites)

#     for i ∈ reverse(ϕ.sites)
#         while mpo_li > i
#             C = contract_matrix_tensor3(ψ[mpo_li], C)
#             mpo_li = left_nbrs_site(mpo_li, ψ.sites)
#         end
#         @assert mpo_li == i "Mismatch between QMpo and QMps sites."
#         mpo_li = left_nbrs_site(mpo_li, ψ.sites)

#         if i > ϕ.sites[1]
#             CM = CornerTensor(C, ψ[i], ϕ[i])
#             U, Σ, V = svd_corner_matrix(CM, method, Dcut, tol; toGPU=onGPU, kwargs...)
#             nΣ = sqrt(sum(Σ .^ 2))
#             println("site = ", i, "  nΣ = ", nΣ)
#             s1, s2 = size(ψ[i])
#             V = permutedims(V, (2, 1))
#             @cast V[x, y, z] := V[x, (y, z)] (z ∈ 1:s2)

#             for k = 1:2
#                 Cnew = update_env_right(C, ϕ[i], ψ[i], V)
#                 Cnew = permutedims(Cnew, (3, 1, 2))
#                 sσ = size(Cnew, 1)
#                 @cast Cnew[(σ, x), y] := Cnew[σ, x, y]
#                 Q, _ = qr_fact(Cnew, Dcut, 0.0; toGPU = ψ.onGPU, kwargs...)
#                 @cast Cnew[σ, x, y] := Q[(σ, x), y] (σ ∈ 1:sσ)
#                 Cnew = permutedims(Cnew, (2, 3, 1))
#                 V = project_ket_on_bra(Cnew, ϕ[i], ψ[i], C)
#                 sσ = size(V, 3)
#                 @cast V[x, (y, σ)] := V[x, y, σ]
#                 _, Q = rq_fact(V, Dcut, 0.0; toGPU = ψ.onGPU, kwargs...)
#                 @cast V[x, y, σ] := V[x, (y, σ)] (σ ∈ 1:sσ)
#             end
#             Cnew = update_env_right(C, ϕ[i], ψ[i], V)
#             C = Cnew ./ norm(Cnew)
#             push!(D, i => V)
#         #     Σ ./= nΣ
#         #     C = U * Diagonal(Σ)
#         #     @cast C[x, y, z] := C[(x, y), z] (y ∈ 1:s1)
#         #     C = permutedims(C, (1, 3, 2))
#         else
#             L = onGPU ? CUDA.ones(R, 1, 1, 1) : ones(R, 1, 1, 1)
#             V = project_ket_on_bra(L, ϕ[i], ψ[i], C)
#             V ./= norm(V)
#             push!(D, i => V)
#         end
#     end
#     QMps(D; onGPU = onGPU)
# end


function Base.Array(CM::CornerTensor)  # change name, or be happy with "psvd(Array(Array(CM))"
    B, M, C = CM.B, CM.M, CM.C
    for v ∈ reverse(M.bot) B = contract_matrix_tensor3(v, B) end
    Cnew = corner_matrix(C, M.ctr, B)
    @cast Cnew[(t1, t2), t3, t4] := Cnew[t1, t2, t3, t4]
    for v ∈ reverse(M.top) Cnew = contract_matrix_tensor3(v, Cnew) end
    @cast Cnew[t12, (t3, t4)] := Cnew[t12, t3, t4]
end

Base.Array(CM::Adjoint{T, CornerTensor{T}}) where T = adjoint(Array(CM.ten))

# TODO rethink this function
function svd_corner_matrix(CM, method::Symbol, Dcut::Int, tol::Real; toGPU::Bool=true, kwargs...)
    if method == :svd
        U, Σ, V = svd_fact(Array(Array(CM)), Dcut, tol; kwargs...)
    elseif method == :psvd
        U, Σ, V = psvd(Array(Array(CM)), rank=Dcut; kwargs...)
    elseif method == :psvd_sparse
        U, Σ, V = psvd(CM, rank=Dcut; kwargs...)
    elseif method == :tsvd
        U, Σ, V = tsvd(Array(CM), Dcut; kwargs...)
    elseif method == :tsvd_sparse
        v0 = 2 .* rand(eltype(CM), size(CM, 1)) .- 1
        U, Σ, V = tsvd(CM, Dcut, initvec=v0; kwargs...)
    else
        throw(ArgumentError("Wrong method $method"))
    end
    toGPU && return CuArray.((U, Σ, V))
    U, Σ, V
end

# this is for psvd to work
LinearAlgebra.ishermitian(ten::CornerTensor) = false
Base.size(ten::CornerTensor) = (size(ten.B, 1) * size(ten.M, 1), size(ten.C, 2) * size(ten.M, 2))
Base.size(ten::CornerTensor, n::Int) = size(ten)[n]
Base.eltype(ten::CornerTensor{T}) where T = T
Base.adjoint(ten::CornerTensor{T}) where T = Adjoint{T}(ten)

CuArrayifneeded(ten::CornerTensor, x) = typeof(ten.B) <: CuArray ? CuArray(x) : x
CuArrayifneeded(ten::Adjoint{T, CornerTensor{T}}, x) where T = CuArrayifneeded(ten.parent, x)


function LinearAlgebra.mul!(y, ten::CornerTensor, x)
    x = CuArrayifneeded(ten, x) # CuArray(x) # TODO this an ugly patch
    x = reshape(x, size(ten.C, 2), size(ten.M, 2), :)
    x = permutedims(x, (3, 1, 2))
    yp = update_env_right(ten.C, x, ten.M, ten.B)
    y[:, :] .= Array(reshape(permutedims(yp, (1, 3, 2)), size(ten.B, 1) * size(ten.M, 1), :))
end

function LinearAlgebra.mul!(y, ten::Adjoint{T, CornerTensor{T}}, x) where T <: Real
    x = CuArrayifneeded(ten, x)  # CuArray(x)  # TODO this an ugly patch
    x = reshape(x, size(ten.parent.B, 1), size(ten.parent.M, 1), :)
    x = permutedims(x, (1, 3, 2))
    yp = project_ket_on_bra(x, ten.parent.B, ten.parent.M, ten.parent.C)
    y[:, :] .= Array(reshape(permutedims(yp, (2, 3, 1)), size(ten.parent.C, 2) * size(ten.parent.M, 2), :))
end

function Base.:(*)(ten::CornerTensor{T}, x) where T
    x = CuArrayifneeded(ten, x)  # CuArray(x)  # TODO this an ugly patch
    x = reshape(x, 1, size(ten.C, 2), size(ten.M, 2))
    yp = update_env_right(ten.C, x, ten.M, ten.B)
    out = reshape(yp, size(ten.B, 1) * size(ten.M, 1))
    Array(out)  # TODO this an ugly patch
end

function Base.:(*)(ten::Adjoint{T, CornerTensor{T}}, x) where T <: Real
    x = CuArrayifneeded(ten, x)  # CuArray(x)  # TODO this an ugly patch
    x = reshape(x, size(ten.parent.B, 1), 1, size(ten.parent.M, 1))
    yp = project_ket_on_bra(x, ten.parent.B, ten.parent.M, ten.parent.C)
    out = reshape(yp, size(ten.parent.C, 2) * size(ten.parent.M, 2))
    Array(out)  # TODO this an ugly patch
end
