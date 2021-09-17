export truncate!, canonise!, compress

function compress(ψ::AbstractMPS, Dcut::Int, tol::Number=1E-8, max_sweeps::Int=4)

    # Initial guess - truncated ψ
    ϕ = copy(ψ)
    truncate!(ϕ, :right, Dcut)

    # Create environment
    env = left_env(ϕ, ψ)

    # Variational compression
    overlap = 0
    overlap_before = 1

    @info "Compressing down to" Dcut

    for sweep ∈ 1:max_sweeps
        _left_sweep_var!!(ϕ, env, ψ)
        overlap = _right_sweep_var!!(ϕ, env, ψ)

        diff = abs(overlap_before - abs(overlap))
        @info "Convergence" diff

        if diff < tol
            @info "Finished in $sweep sweeps of $(max_sweeps)."
            return ϕ
        else
            overlap_before = overlap
        end
    end
    ϕ
end

function canonise!(ψ::AbstractMPS)
    canonise!(ψ, :right)
    canonise!(ψ, :left)
end

canonise!(ψ::AbstractMPS, s::Symbol) = canonise!(ψ, Val(s))
canonise!(ψ::AbstractMPS, ::Val{:right}) = _left_sweep!(ψ)
canonise!(ψ::AbstractMPS, ::Val{:left}) = _right_sweep!(ψ)

truncate!(ψ::AbstractMPS, s::Symbol, Dcut::Int) = truncate!(ψ, Val(s), Dcut)
truncate!(ψ::AbstractMPS, ::Val{:right}, Dcut::Int) = _left_sweep!(ψ, Dcut)
truncate!(ψ::AbstractMPS, ::Val{:left}, Dcut::Int) = _right_sweep!(ψ, Dcut)

function _right_sweep!(ψ::AbstractMPS, Dcut::Int=typemax(Int))
    R = ones(eltype(ψ), 1, 1)

    for (i, A) ∈ enumerate(ψ)
        # attach
        @matmul M̃[(x, σ), y] := sum(α) R[x, α] * A[α, σ, y]

        # decompose
        Q, R = qr(M̃, Dcut)

        # create new
        @cast A[x, σ, y] |= Q[(x, σ), y] (σ ∈ 1:size(A, 2))
        ψ[i] = A
    end
    ψ[end] #*= tr(R)
end


function _left_sweep!(ψ::AbstractMPS, Dcut::Int=typemax(Int))
    R = ones(eltype(ψ), 1, 1)

    for i ∈ length(ψ):-1:1
        B = ψ[i]

        # attach    
        @matmul M̃[x, (σ, y)] := sum(α) B[x, σ, α] * R[α, y]

        # decompose
        R, Q = rq(M̃, Dcut)

        # create new
        d = physical_dim(ψ, i)
        @cast B[x, σ, y] |= Q[x, (σ, y)] (σ ∈ 1:size(B, 2))
        ψ[i] = B
    end
    ψ[1] #*= tr(R)
end


function _left_sweep_var!!(ϕ::AbstractMPS, env::Vector{<:AbstractMatrix}, ψ::AbstractMPS)
    S = eltype(ϕ)

    # overwrite the overlap
    env[end] = ones(S, 1, 1)

    for i ∈ length(ψ):-1:1
        L = env[i]
        R = env[i+1]

        # optimize site
        M = ψ[i]
        @tensor MM[x, σ, α] := L[x, β] * M[β, σ, α] 
        @matmul MM[x, (σ, y)] := sum(α) MM[x, σ, α] * R[α, y]

        _, Q = rq(MM, typemax(Int))

        @cast B[x, σ, y] |= Q[x, (σ, y)] (σ ∈ 1:size(M, 2))

        # update ϕ and right environment
        ϕ[i] = B
        A = ψ[i]

        @tensor RR[x, y] := A[x, σ, α] * R[α, β] * conj(B)[y, σ, β] order = (β, α, σ)
        env[i] = RR
    end
end


function _right_sweep_var!!(ϕ::AbstractMPS, env::Vector{<:AbstractMatrix}, ψ::AbstractMPS)
    S = eltype(ϕ)

    # overwrite the overlap
    env[1] = ones(S, 1, 1)

    for (i, M) ∈ enumerate(ψ)
        L = env[i]
        R = env[i+1]

        # optimize site
        @tensor M̃[x, σ, α] := L[x, β] * M[β, σ, α]
        @matmul B[(x, σ), y] := sum(α) M̃[x, σ, α] * R[α, y]

        Q, _ = qr(B, typemax(Int))

        @cast A[x, σ, y] |= Q[(x, σ), y] (σ ∈ 1:size(M, 2))

        # update ϕ and left environment
        ϕ[i] = A
        B = ψ[i]

        @tensor LL[x, y] := conj(A[β, σ, x]) * L[β, α] * B[α, σ, y] order = (α, β, σ)
        env[i+1] = LL
    end
    real(env[end][1])
end


function _right_sweep_SVD(::Type{T}, A::AbstractArray, Dcut::Int=typemax(Int), args...) where {T <: AbstractMPS}
    rank = ndims(A)
    ψ = T(eltype(A), rank)
    V = reshape(copy(conj(A)), (length(A), 1))

    for i ∈ 1:rank
        d = size(A, i)

        # reshape
        VV = conj.(transpose(V))
        @cast M[(x, σ), y] |= VV[x, (σ, y)] (σ ∈ 1:d)

        # decompose
        U, Σ, V = svd(M, Dcut, args...)
        V *= Diagonal(Σ)

        # create MPS
        @cast B[x, σ, y] |= U[(x, σ), y] (σ ∈ 1:d)
        ψ[i] = B
    end
    ψ
end


function _left_sweep_SVD(::Type{T}, A::AbstractArray, Dcut::Int=typemax(Int), args...) where {T <: AbstractMPS}
    rank = ndims(A)
    ψ = T(eltype(A), rank)

    U = reshape(copy(A), (length(A), 1))

    for i ∈ rank:-1:1
        d = size(A, i)

        # reshape
        @cast M[x, (σ, y)] |= U[(x, σ), y] (σ ∈ 1:d)

        # decompose
        U, Σ, V = svd(M, Dcut, args...)
        U *= Diagonal(Σ)

        # create MPS
        VV = conj.(transpose(V))
        @cast B[x, σ, y] |= VV[x, (σ, y)] (σ ∈ 1:d)
        ψ[i] = B
    end
    ψ
end
