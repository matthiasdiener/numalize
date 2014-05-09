#!/usr/bin/env Rscript

filenames <- commandArgs(trailingOnly=TRUE)

if (length(filenames) < 1)
	stop("Usage: heterogeneity.R <CommPattern.csv>*\n")


comm_het = function(frame) {
	frame = frame / max(frame) * 100
	frame[frame>30] = 100
	return(sum(apply(frame, 1, var))/length(frame))
}

comm_avg = function(frame)
	return(sum(as.numeric(unlist(frame)))/length(frame)/length(frame))

for (i in 1:length(filenames)) {
	cat(filenames[i], " ")

	data <- read.csv(filenames[i], header=F)

	cat(" ", comm_het(data))
	cat(" ", comm_avg(data), "\n")
}
