#!/usr/bin/env Rscript

filenames <- commandArgs(trailingOnly=TRUE)

if (length(filenames) < 1)
	stop("Usage: heterogeneity.R <CommPattern.csv>*\n")

for (i in 1:length(filenames)) {
	cat(filenames[i], " ")

	data <- read.csv(filenames[i], header=F)
	nt <- length(data)

	d <- (data / max(data))# * 100
	# d[d<30] <- 0
	d[d>0.3] <- 1

	v <- 0
	for (i in 1:nt) {
		v <- v + var(d[-nt+1-i,i])
		# print (var(d[-nt+1-i,i]))
	}

	avg <- sum(as.numeric(unlist(data)))/nt/nt

	# cat("hf_old:", var(data)/sum(data)/nt/nt, "\n")
	cat(" ", v/nt)
	cat(" ", avg, "\n")
}
