#!/usr/bin/env Rscript

extract = function (x) {
	from = x[1]+1
	to   = x[2]+1
	msg  = x[3]
	mat[from,to] <<- mat[from,to] + msg
	mat[to,from] <<- mat[from,to]       # make matrix symmetric
}

args = commandArgs(trailingOnly=T)
if (length(args) != 1)
	stop("Usage: convert_itac.R <itac_input.txt>\n")

file = args[1]
outfile = sub("\\..*", ".csv", args[1])

data = read.csv(file, sep=";")

data$Sender = as.integer(sub("Process ", "", data$Sender))
data$Reciever = as.integer(sub("Process ", "", data$Reciever))

nt = max(max(data$Sender), max(data$Reciever))+1

mat = matrix(0, nt, nt) # create empty matrix (global variable)

ignore = apply(data, 1, extract)

mat = mat[nrow(mat):1,] # reverse matrix

write.table(mat, file=outfile, sep=",", quote=F, row.names=F, col.names=F)
cat("Wrote", outfile, "-", nt, "threads", "\n")
