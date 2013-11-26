#!/usr/bin/env Rscript

local({r <- getOption("repos"); r["CRAN"] <- "http://cran.r-project.org"; options(repos=r)})

if (!suppressPackageStartupMessages(require(lattice))) {
	install.packages("lattice")
	library(lattice)
}

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1]
outfilename <- gsub(".csv", ".pdf", filename)

if (length(args) != 1) {
	stop("Usage: mkCommMatrix.R <CommPattern.csv>\n")
}

csv <- read.csv(filename, header=FALSE)
nt <- ncol(csv)

rownames(csv) <- rev(as.integer(rownames(csv)) - 1)
colnames(csv) <- rev(rownames(csv))

mat <- data.matrix(csv)
mat <- t(mat[nrow(mat):1,])

pdf(outfilename)
levelplot(mat, col.regions=grey(seq(1,0,-0.01)), colorkey=F, xlab="", ylab="", scales=list(x=list(at=seq(1,nt,5)), y=list(at=seq(1,nt,5))))
garbage <- dev.off()

system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))

cat("Generated", outfilename, "\n")
