#!/usr/bin/env Rscript

## How to use:
# install required packages in R console:
# install.packages(c("treemap", "RColorBrewer", "plyr")
#
# then run this script:
# $ ./analyze.R <input.csv>


library("treemap")
library("RColorBrewer")
library("plyr")

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1]
outfilename <- gsub("csv", "pdf", filename)

datamap <- read.csv(filename)

datamap$sum <- rowSums(datamap[,4:35])

datamap$N1 <- rowSums(datamap[,4:11])
datamap$N2 <- rowSums(datamap[,12:19])
datamap$N3 <- rowSums(datamap[,20:27])
datamap$N4 <- rowSums(datamap[,28:35])

datamap$max <- apply(datamap[,37:40], 1, max)

datamap$excl <- datamap$max / datamap$sum *100

myround <- function(x){val <- round_any(x, 10, f=floor); val<-lapply(val, max, 30); lapply(val, min, 90)}

datamap$excl_round <- as.numeric(myround(datamap$excl))

datamap$excl_round <- paste(datamap$excl_round, "%", sep="")
datamap$excl_round <- paste(ifelse(datamap$excl_round=="30%","<",""), datamap$excl_round, sep="")
datamap$excl_round <- paste(ifelse(datamap$excl_round=="90%",">",""), datamap$excl_round, sep="")
datamap <- transform(datamap, data.excl = factor(excl_round))

pdf(outfilename)

options(warn=-1)

treemap(datamap,
	index=c("excl_round"),
	vSize="sum",
	vColor= "data.excl",
	type="categorical",
	aspRatio=1,
	palette="Greys",
	# palette=c("#FFFFFF","#D2D2D2","#A8A8A8","#7E7E7E","#545454","#2A2A2A","#000000"),
	title="",
	title.legend="Exclusivity level",
	fontsize.labels=c(90,50,15),
	fontsize.legend=14,
	bg.labels="#FFFFFF",
	algorithm="pivotSize",
	sortID="color",
	position.legend="bottom",
	overlap.labels=0)

garbage <- dev.off()

system(paste("pdfcrop ", outfilename, outfilename))
