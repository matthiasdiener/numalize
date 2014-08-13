#!/usr/bin/env Rscript

library(lattice) # for levelplot

cleardiag = 1

args = commandArgs(trailingOnly=TRUE)

if (length(args) < 1)
	stop("Usage: mkCommMatrix.R <CommPattern.csv>...\n")

for (i in 1:length(args)) {
	filename = args[i]
	outfilename = gsub(".csv", ".pdf", filename)
	if (filename == outfilename)
		outfilename = paste(filename, ".pdf", sep="")

	csv = as.data.frame(read.csv(filename, header=FALSE))
	nt = ncol(csv)

	rownames(csv) = rev(as.integer(rownames(csv)) - 1)
	colnames(csv) = rev(rownames(csv))

	mat = data.matrix(csv)
	mat = t(mat[nrow(mat):1,])

	if (cleardiag==1)
		for (i in 1:nt)
			mat[i,i] = 0

	pdf(outfilename, family="NimbusSan")
	print(levelplot(mat, col.regions=grey(seq(1,0,-0.01)), colorkey=F, xlab="", ylab="", scales=list(x=list(cex=1.5,at=seq(1,nt,5)), y=list(cex=1.5,at=seq(1,nt,5)))))
	garbage <- dev.off()

	embedFonts(outfilename)

	system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))

	cat("Generated", outfilename, "\n")
}
