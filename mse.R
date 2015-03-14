#!/usr/bin/env Rscript

args = commandArgs(trailingOnly=T)
if (length(args) != 2)
	stop("Usage: mse.R <comm_patternA.csv> <comm_patternB.csv>\n")

mat1 = data.matrix(read.csv(args[1]))
mat2 = data.matrix(read.csv(args[2]))

mat1 = mat1/max(mat1) * 100
mat2 = mat2/max(mat2) * 100

mse = mean((mat1 - mat2)^2)

cat(mse, "\n")
