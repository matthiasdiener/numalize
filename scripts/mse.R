#!/usr/bin/env Rscript

args = commandArgs(trailingOnly=T)
if (length(args) != 2)
	stop("Usage: mse.R <comm_patternA.csv> <comm_patternB.csv>\n")

mat1 = data.matrix(read.csv(args[1], header=F))
mat2 = data.matrix(read.csv(args[2], header=F))

mat1 = mat1/max(mat1,1) * 100
mat2 = mat2/max(mat2,1) * 100

if(nrow(mat1)!=ncol(mat1) || nrow(mat2)!=ncol(mat2) || nrow(mat1)!=ncol(mat2))
	stop("Input matrices are not square or do not have same dimensions")

nt = nrow(mat1)

# clear diagonal just in case
for (i in 1:nt) {
	mat1[i,nt+1-i] = 0
	mat2[i,nt+1-i] = 0
}

mse = mean((mat1 - mat2)^2)

cat(mse, "\n")
