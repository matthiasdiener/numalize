#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1]

if (length(args) != 1) {
	stop("Usage: heterogeneity.R <CommPattern.csv>\n")
}

data <- read.csv(filename, header=F)
nt <- length(data)

d <- data / max(data) * 100

v <- 0
for (i in 1:nt) {v=v+var(d[-nt+1-i,i])}

avg <- sum(data)/nt/nt

# cat("hf_old:", var(data)/sum(data)/nt/nt, "\n")
cat("hf_new:", v/nt, "\n")
cat("a:", avg, "\n")
