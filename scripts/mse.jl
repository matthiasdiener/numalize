#!/usr/bin/env julia

function mse(A, B)
    if size(A) != size(B)
        error("Input matrices do not have same dimensions")
    end

    if size(A)[1] != size(A)[2]
        error("Input matrices are not square")
    end

    nt = size(A)[1]

    # remove diagonal
    for i in 1:nt
        A[i,nt+1-i] = 0
        B[i,nt+1-i] = 0
    end

    # normalize values
    A = A/maximum(A) * 100
    B = B/maximum(B) * 100

    mse = mean((A - B).^2)
end


if length(ARGS) != 2
    error("Usage: ", PROGRAM_FILE, " <comm_pattern_A.csv> <comm_pattern_B.csv>")
end

mat1 = readdlm(ARGS[1], ',')
mat2 = readdlm(ARGS[2], ',')

println(mse(mat1, mat2))
