#!/usr/bin/env Rscript

library(lattice) # for levelplot

cleardiag = 1    # remove diagnoal?
every = 5        # every x thread IDs
scale = every/2  # font size
printnum = 0     # print cell values?

comm_het = function(frame) {
	if (length(frame) < 8)
	    return(0)
	frame = frame / max(frame, na.rm=T) * 100
	# frame[frame>30] = 100
	return(mean(apply(frame, 1, var, na.rm=T)))
}

comm_avg = function(frame)
	return(sum(as.numeric(unlist(frame)))/length(frame)/length(frame))

myPanel <- function(x, y, z, ...) {
	panel.levelplot(x,y,z,...)
	if (printnum) {
		panel.abline(h=c(1:(nt-1))+0.5, v=c(1:(nt-1))+0.5)
		panel.text(x, y, round(z,1),cex=scale)
	}
}

args = commandArgs(trailingOnly=TRUE)

if (length(args) < 1)
	stop("Usage: mkCommMatrix.R <CommPattern.csv>...\n")

for (i in 1:length(args)) {
	filename = args[i]

	if (grepl(".csv", filename)) {
		outfilename = gsub(".csv", ".pdf", filename)
		if (filename == outfilename)
			outfilename = paste(filename, ".pdf", sep="")

		csv = as.data.frame(read.csv(filename, header=FALSE))
	} else if (grepl(".dat", filename)) {
		outfilename = gsub(".dat", ".pdf", filename)
		if (filename == outfilename)
			outfilename = paste(filename, ".pdf", sep="")

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

	optlist=list(cex=scale,limits=range(-0.5:nt+1),labels=seq(0,nt-1,every),tck=c(1,0),at=seq(1,nt,every))

	pdf(outfilename, family="NimbusSan", width=nt, height=nt)
	print(levelplot(mat, panel=myPanel, col.regions=grey(seq(1,0,-0.01)), colorkey=F, xlab=NULL, ylab=NULL, scales=list(x=optlist, y=optlist)))
	garbage <- dev.off()

	embedFonts(outfilename)

	system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))

	cat("Generated", outfilename, " hetero: ", comm_het(csv), " avg:", comm_avg(csv),"\n")
}
