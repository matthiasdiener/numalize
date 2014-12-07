#!/usr/bin/env Rscript

library(lattice) # for levelplot

cleardiag = 1    # remove diagnoal?
every = 1        # every x thread IDs
scale = 3.5  # font size
printnum = 0     # print cell values?

myPanel <- function(x, y, z, ...) {
	panel.levelplot(x,y,z,...)
	if (printnum) {
		panel.abline(h=c(1:(nt-1))+0.5, v=c(1:(nt-1))+0.5)
		panel.text(x, y, round(z,1),cex=scale)
	}
}


lambda=function(l) {return((max(l)/mean(l)-1)*100)}

args = commandArgs(trailingOnly=TRUE)

if (length(args) < 1)
	stop("Usage: mkCommMatrix.R <CommPattern.csv>...\n")

for (i in 1:length(args)) {
	filename = args[i]

	if (grepl(".csv", filename)) {
		outfilename = gsub(".csv", ".load.pdf", filename)
		if (filename == outfilename)
			outfilename = paste(filename, ".load.pdf", sep="")

		csv = as.data.frame(read.csv(filename, header=FALSE))
	} else if (grepl(".dat", filename)) {
		outfilename = gsub(".dat", ".load.pdf", filename)
		if (filename == outfilename)
			outfilename = paste(filename, ".load.pdf", sep="")

		csv = data.matrix(read.table(filename, header=FALSE))
		csv = apply(csv, 2, rev) # reverse csv
		csv = data.frame(csv)
	}

	nt = ncol(csv)

	rownames(csv) = rev(as.integer(rownames(csv)) - 1)
	colnames(csv) = rev(rownames(csv))

	mat = data.matrix(csv)
	mat = t(mat[nrow(mat):1,])

	if (cleardiag==1)
		for (i in 1:nt)
			mat[i,i] = 0

	for (i in 1:nt) {
		if (i<nt/2)
			for (j in 1:i)
				mat[i,j] = 0
		else
			for (j in i:nt)
				mat[i,j] = 0
	}


	mat = matrix(rowSums(mat))

	mat = mat/max(mat) * 100
	v = lambda(mat)

	optlist=list(cex=scale,limits=range(-0.5:nt+1),labels=seq(0,nt-1,every),tck=c(1,0),at=seq(1,nt,every))

	pdf(outfilename, family="NimbusSan", width=nt, height=nt)
	print(levelplot(mat, panel=myPanel, col.regions=grey(seq(1,0,-0.01)), colorkey=F, xlab=NULL, ylab=NULL, scales=list(x=optlist,y=list(labels=NULL,tck=c(0,0)))))
	garbage <- dev.off()

	embedFonts(outfilename)

	system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))

	cat("Generated", outfilename, "var=", v, "\n")
}
