function CUDA.CUSPARSE.CuSparseMatrixCSC(
    ::Type{T}, p_lb::R, p_l::R, p_lt::R
) where {T <: Real, R <: Array{Int, 1}}
    @assert length(p_lb) == length(p_l) == length(p_lt)
    p_l, p_lb, p_lt = CuArray.((p_l, p_lb, p_lt))
    ncol = length(p_lb)

    CuSparseMatrixCSC(
        CuArray(collect(1:ncol+1)),
        maximum(p_l) * maximum(p_lb) * (p_lt .- 1) .+ maximum(p_lb) * (p_l .- 1) .+ p_lb,
        CUDA.ones(T, ncol),
        (maximum(p_l) * maximum(p_lb) * maximum(p_lt), ncol)
    )
end

function CUDA.CUSPARSE.CuSparseMatrixCSR(
    ::Type{T}, p_lb::R, p_l::R, p_lt::R
) where {T <: Real, R <: Array{Int, 1}}
    transpose(CuSparseMatrixCSC(T, p_lb, p_l, p_lt))
end

r2_over_r1(matrix) = size(matrix, 2) / size(matrix, 1)
r1_over_r2(matrix) = size(matrix, 1) / size(matrix, 2)

"""
Select optimal order of attaching matrices to L
"""
function attach_3_matrices_left(L, B2, h, A2)
    if r2_over_r1(h) <= r2_over_r1(B2) <= r2_over_r1(A2)
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
    elseif r2_over_r1(h) <= r2_over_r1(A2) <= r2_over_r1(B2)
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
    elseif r2_over_r1(A2) <= r2_over_r1(h) <= r2_over_r1(B2)
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
    elseif r2_over_r1(A2) <= r2_over_r1(B2) <= r2_over_r1(h)
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
    elseif r2_over_r1(B2) <= r2_over_r1(h) <= r2_over_r1(A2)
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
    else # r2_over_r1(B2) <= r2_over_r1(A2) <= r2_over_r1(h)
        @tensor L[rfb, x, y] := L[lfb, x, y] * B2[lfb, rfb]
        @tensor L[x, y, rft] := L[x, y, lft] * A2[lft, rft]
        L = attach_central_left(L, h)  # [..., rc, ...] = [..., lc, ...] * [lc, rc]
    end
    L
end

"""
Select optimal order of attaching matrices to R
"""
function attach_3_matrices_right(R, B2, h, A2)
    if r1_over_r2(h) <= r1_over_r2(B2) <= r1_over_r2(A2)
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
    elseif r1_over_r2(h) <= r1_over_r2(A2) <= r1_over_r2(B2)
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
    elseif r1_over_r2(A2) <= r1_over_r2(h) <= r1_over_r2(B2)
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
    elseif r1_over_r2(A2) <= r1_over_r2(B2) <= r1_over_r2(h)
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
    elseif r1_over_r2(B2) <= r1_over_r2(h) <= r1_over_r2(A2)
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
    else # r1_over_r2(B2) <= r1_over_r2(A2) <= r1_over_r2(h)
        @tensor R[lfb, x, y] := R[rfb, x, y] * B2[lfb, rfb]
        @tensor R[x, y, lft] := R[x, y, rft] * A2[lft, rft]
        R = attach_central_right(R, h)  # [..., lc, ...] = [..., rc, ...] * [lc, rc]
    end
    R
end

function update_env_left(
    LE::S, A::S, M::SparseVirtualTensor, B::S, ::Val{:n}
) where S <: ArrayOrCuArray{3}
    A, B, L = CuArray.((A, B, LE))

    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    slb, srb = size(B, 1), size(B, 3)
    slcb, slc, slct = maximum(p_lb), maximum(p_l), maximum(p_lt)
    srcb, srct = maximum(p_rb), maximum(p_rt)

    @cast A2[(lt, lct), (rct, rt)] := A[lt, (lct, rct), rt] (lct ∈ 1:slct)
    @cast B2[(lb, lcb), (rcb, rb)] := B[lb, (lcb, rcb), rb] (lcb ∈ 1:slcb)

    L = permutedims(L, (2, 1, 3))#[lcp, lb, lt]
    @cast L[lcp, (lb, lt)] := L[lcp, lb, lt]

    ps = CuSparseMatrixCSC(eltype(LE), p_lb, p_l, p_lt)
    L = ps * L #[(lcb, lc, lct), (lb, lt)]

    @cast L[lcb, lc, lct, lb, lt] := L[(lcb, lc, lct), (lb, lt)] (lcb ∈ 1:slcb, lc ∈ 1:slc, lb ∈ 1:slb)
    L = permutedims(L, (4, 1, 2, 5, 3)) #[lb, lcb, lc, lt, lct]
    @cast L[(lb, lcb), lc, (lt, lct)] := L[lb, lcb, lc, lt, lct]

    L = attach_3_matrices_left(L, B2, h, A2)

    @cast L[rcb, rb, rc, rct, rt] := L[(rcb, rb), rc, (rct, rt)] (rcb ∈ 1:srcb, rct ∈ 1:srct)
    L = permutedims(L, (1, 3, 4, 2, 5)) #[rcb, rc, rct, rb, rt]
    @cast L[(rcb, rc, rct), (rb, rt)] := L[rcb, rc, rct, rb, rt]

    prs = CuSparseMatrixCSR(eltype(LE), p_rb, p_r, p_rt)
    L = prs * L #[rcp, (rb, rt)]
    @cast L[rcp, rb, rt] := L[rcp, (rb, rt)] (rb ∈ 1:srb)

    Array(permutedims(L, (2, 1, 3)) ./ maximum(abs.(L))) #[rb, rcp, rt]
end

function update_env_left(
    LE::S, A::S, M::SparseVirtualTensor, B::S, ::Val{:c}
) where S <: ArrayOrCuArray{3}
    A, B, L = CuArray.((A, B, LE))

    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    slb, srb = size(B, 1), size(B, 3)
    slcb, slc, slct = maximum(p_lb), maximum(p_l), maximum(p_lt)
    srcb, srct = maximum(p_rb), maximum(p_rt)

    @cast A2[(lt, lcb), (rcb, rt)] := A[lt, (lcb, rcb), rt] (lcb ∈ 1:slcb)
    @cast B2[(lb, lct), (rct, rb)] := B[lb, (lct, rct), rb] (lct ∈ 1:slct)

    L = permutedims(L, (2, 1, 3)) #[lcp, lb, lt]
    @cast L[lcp, (lb, lt)] := L[lcp, lb, lt]

    ps = CuSparseMatrixCSC(eltype(LE), p_lb, p_l, p_lt)
    L = ps * L  #[(lcb, lc, lct), (lb, lt)]

    @cast L[lcb, lc, lct, lb, lt] := L[(lcb, lc, lct), (lb, lt)] (lcb ∈ 1:slcb, lc ∈ 1:slc, lb ∈ 1:slb)
    L = permutedims(L, (4, 3, 2, 5, 1))  #[lb, lct, lc, lt, lcb]
    @cast L[(lb, lct), lc, (lt, lcb)] := L[lb, lct, lc, lt, lcb]

    L = attach_3_matrices_left(L, B2, h, A2)

    @cast L[rct, rb, rc, rcb, rt] := L[(rct, rb), rc, (rcb, rt)] (rct ∈ 1:srct, rcb ∈ 1:srcb)
    L = permutedims(L, (1, 3, 4, 2, 5)) #[rcb, rc, rct, rb, rt]
    @cast L[(rct, rc, rcb), (rb, rt)] := L[rct, rc, rcb, rb, rt]

    prs = CuSparseMatrixCSR(eltype(LE), p_rb, p_r, p_rt)
    L = prs * L  #[rcp, (rb, rt)]
    @cast L[rcp, rb, rt] := L[rcp, (rb, rt)] (rb ∈ 1:srb)
    Array(permutedims(L, (2, 1, 3)) ./ maximum(abs.(L)))  #[rb, rcp, rt]
end

function update_env_right(
    RE::S, A::S, M::SparseVirtualTensor, B::S, ::Val{:n}
) where S <: ArrayOrCuArray{3}
    A, B, R = CuArray.((A, B, RE))

    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    slt, srt = size(A, 1), size(A, 3)
    slb, srb = size(B, 1), size(B, 3)
    srcb, src, srct = maximum(p_rb), maximum(p_r), maximum(p_rt)
    slcb, slct = maximum(p_lb), maximum(p_lt)

    @cast A2[(lt, lct), (rct, rt)] := A[lt, (lct, rct), rt] (rct ∈ 1:srct)
    @cast B2[(lb, lcb), (rcb, rb)] := B[lb, (lcb, rcb), rb] (rcb ∈ 1:srcb)

    R = permutedims(R, (2, 3, 1))  #[rcp, rb, rt]
    @cast R[rcp, (rb, rt)] := R[rcp, rb, rt]

    ps = CuSparseMatrixCSC(eltype(RE), p_rb, p_r, p_rt)
    R = ps * R  #[(rcb, rc, rct), (rb, rt)]

    @cast R[rcb, rc, rct, rb, rt] := R[(rcb, rc, rct), (rb, rt)] (rcb ∈ 1:srcb, rc ∈ 1:src, rb ∈ 1:srb)
    R = permutedims(R, (1, 4, 2, 3, 5))  #[rcb, rb, rc, rct, rt]

    @cast R[(rcb, rb), rc, (rct, rt)] := R[rcb, rb, rc, rct, rt]

    R = attach_3_matrices_right(R, B2, h, A2)

    @cast R[lb, lcb, lc, lt, lct] := R[(lb, lcb), lc, (lt, lct)] (lb ∈ 1:slb, lt ∈ 1:slt)
    R = permutedims(R, (2, 3, 5, 4, 1)) #[lct, lc, lcb, lt, lb]
    @cast R[(lcb, lc, lct), (lt, lb)] := R[lcb, lc, lct, lt, lb]

    prs = CuSparseMatrixCSR(eltype(RE), p_lb, p_l, p_lt)
    R = prs * R  #[rcp, (rt, rb)]
    @cast R[lcp, lt, lb] := R[lcp, (lt, lb)] (lb ∈ 1:slb)
    Array(permutedims(R, (2, 1, 3)) ./ maximum(abs.(R)))  #[rt, rcp, rb]
end

function update_env_right(
    RE::S, A::S, M::SparseVirtualTensor, B::S, ::Val{:c}
) where S <: ArrayOrCuArray{3}
    A, B, R = CuArray.((A, B, RE))

    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    slt, srt = size(A, 1), size(A, 3)
    slb, srb = size(B, 1), size(B, 3)
    srcb, src, srct = maximum(p_rb), maximum(p_r), maximum(p_rt)
    slcb, slct = maximum(p_lb), maximum(p_lt)

    @cast A2[(lt, lcb), (rcb, rt)] := A[lt, (lcb, rcb), rt] (rcb ∈ 1:srcb)
    @cast B2[(lb, lct), (rct, rb)] := B[lb, (lct, rct), rb] (rct ∈ 1:srct)

    R = permutedims(R, (2, 3, 1))  # [rcp, rb, rt]
    @cast R[rcp, (rb, rt)] := R[rcp, rb, rt]

    ps = CuSparseMatrixCSC(eltype(RE), p_rb, p_r, p_rt)
    R = ps * R  # [(rcb, rc, rct), (rb, rt)]

    @cast R[rcb, rc, rct, rb, rt] := R[(rcb, rc, rct), (rb, rt)] (rcb ∈ 1:srcb, rc ∈ 1:src, rb ∈ 1:srb)
    R = permutedims(R, (3, 4, 2, 1, 5))  # [rct, rb, rc, rcb, rt]

    @cast R[(rct, rb), rc, (rcb, rt)] := R[rct, rb, rc, rcb, rt]

    R = attach_3_matrices_right(R, B2, h, A2)

    @cast R[lb, lct, lc, lt, lcb] := R[(lb, lct), lc, (lt, lcb)] (lb ∈ 1:slb, lt ∈ 1:slt)
    R = permutedims(R, (5, 3, 2, 4, 1)) #[lct, lc, lcb, lt, lb] #
    @cast R[(lcb, lc, lct), (lt, lb)] := R[lcb, lc, lct, lt, lb]

    prs = CuSparseMatrixCSR(eltype(RE), p_lb, p_l, p_lt)
    R = prs * R  # [rcp, (rt, rb)]
    @cast R[lcp, lt, lb] := R[lcp, (lt, lb)] (lb ∈ 1:slb)
    Array(permutedims(R, (2, 1, 3)) ./ maximum(abs.(R)))  # [rt, rcp, rb]
end

function project_ket_on_bra(
    LE::S, B::S, M::SparseVirtualTensor, RE::S, ::Val{:n}
) where S <: ArrayOrCuArray{3}
    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    B, L, R = CuArray.((B, LE, RE))

    slb, srb = size(B, 1), size(B, 3)
    srcb, src, srct = maximum(p_rb), maximum(p_r), maximum(p_rt)
    slcb, slc, slct = maximum(p_lb), maximum(p_l), maximum(p_lt)

    @cast B2[(lb, lcb), (rcb, rb)] := B[lb, (lcb, rcb), rb] (lcb ∈ 1:slcb)
    @cast B4[lb, lcb, rcb, rb] := B[lb, (lcb, rcb), rb] (lcb ∈ 1:slcb)

    L = permutedims(L, (2, 1, 3))
    @cast L[lc, (lb, lt)] := L[lc, lb, lt]
    ps = CuSparseMatrixCSC(eltype(LE), p_lb, p_l, p_lt)
    L = ps * L

    @cast L[lcb, lc, lct, lb, lt] := L[(lcb, lc, lct), (lb, lt)] (lcb ∈ 1:slcb, lc ∈ 1:slc, lb ∈ 1:slb)
    L = permutedims(L, (4, 1, 2, 5, 3))  # [lb, lcb, lc, lt, lct]
    @cast L[(lb, lcb), lc, (lt, lct)] := L[lb, lcb, lc, lt, lct]

    L = attach_central_left(L, h)
    @cast L[lb, lcb, lc, lt, lct] := L[(lb, lcb), lc, (lt, lct)] (lcb ∈ 1:slcb, lct ∈ 1:slct)

    R = permutedims(R, (2, 3, 1))
    @cast R[rc, (rb, rt)] := R[rc, rb, rt]
    ps = CuSparseMatrixCSC(eltype(LE), p_rb, p_r, p_rt)
    R = ps * R

    @cast R[rcb, rc, rct, rb, rt] := R[(rcb, rc, rct), (rb, rt)] (rcb ∈ 1:srcb, rc ∈ 1:src, rb ∈ 1:srb)

    R = permutedims(R, (5, 3, 2, 4, 1)) #[rt, rct, rc, rb, rcb]
    @tensor LR[lt, lct, rct, rt] := L[lb, lcb, c, lt, lct] * R[rt, rct, c, rb, rcb] *
                                    B4[lb, lcb, rcb, rb] order = (lb, lcb, rcb, rb, c)

    @cast LR[lt, (lct, rct), rt] := LR[lt, lct, rct, rt]
    Array(LR ./ maximum(abs.(LR)))
end

function project_ket_on_bra(
    LE::S, B::S, M::SparseVirtualTensor, RE::S, ::Val{:c}
) where S <: ArrayOrCuArray{3}
    h = M.con
    p_lb, p_l, p_lt, p_rb, p_r, p_rt = M.projs

    B, L, R = CuArray.((B, LE, RE))

    slb, srb = size(B, 1), size(B, 3)
    srcb, src, srct = maximum(p_rb), maximum(p_r), maximum(p_rt)
    slcb, slc, slct = maximum(p_lb), maximum(p_l), maximum(p_lt)

    @cast B2[(lb, lct), (rct, rb)] := B[lb, (lct, rct), rb] (lct ∈ 1:slct)
    @cast B4[lb, lct, rct, rb] := B[lb, (lct, rct), rb] (lct ∈ 1:slct)

    L = permutedims(L, (2, 1, 3))
    @cast L[lc, (lb, lt)] := L[lc, lb, lt]
    ps = CuSparseMatrixCSC(eltype(LE), p_lt, p_l, p_lb)
    L = ps * L

    @cast L[lct, lc, lcb, lb, lt] := L[(lct, lc, lcb), (lb, lt)] (lct ∈ 1:slct, lc ∈ 1:slc, lb ∈ 1:slb)
    L = permutedims(L, (4, 1, 2, 5, 3))  # [lb, lct, lc, lt, lcb]

    @cast L[(lb, lct), lc, (lt, lcb)] := L[lb, lct, lc, lt, lcb]

    L = attach_central_left(L, h)
    @cast L[lb, lct, lc, lt, lcb] := L[(lb, lct), lc, (lt, lcb)] (lcb ∈ 1:slcb, lct ∈ 1:slct)

    R = permutedims(R, (2, 3, 1))
    @cast R[rc, (rb, rt)] := R[rc, rb, rt]
    ps = CuSparseMatrixCSC(eltype(LE), p_rb, p_r, p_rt)
    R = ps * R

    @cast R[rct, rc, rcb, rb, rt] := R[(rct, rc, rcb), (rb, rt)] (rcb ∈ 1:srcb, rc ∈ 1:src, rb ∈ 1:srb)

    R = permutedims(R, (5, 3, 2, 4, 1)) #[rt, rcb, rc, rb, rct]
    @tensor LR[lt, lcb, rcb, rt] := L[lb, lct, c, lt, lcb] * R[rt, rcb, c, rb, rct] *
                                    B4[lb, lct, rct, rb] order = (lb, lct, rct, rb, c)
    @cast LR[lt, (lcb, rcb), rt] := LR[lt, lcb, rcb, rt]

    Array(LR ./ maximum(abs.(LR)))
end
