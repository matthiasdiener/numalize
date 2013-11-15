#!/usr/bin/env Rscript

## How to use:
# install required packages in R console:
# install.packages(c("treemap", "RColorBrewer", "plyr")
#
# then run this script:
# $ ./analyze.R <input.csv>

paste0 <- function(..., sep = "") paste(..., sep = sep)

library("treemap")
library("RColorBrewer")
library("plyr")

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1:(length(args)-1)]
outfilename <- gsub(".csv", ".pdf", filename)
outfilename <- gsub(".gz", "", outfilename)
nnodes <- as.numeric(args[length(args)])

data <- NULL

for (i in 1:length(filename)) {
	name <- gsub("[.].*", "" ,filename[i])
	name <- toupper(gsub(".*/", "" , name))
	cat ("Loading", filename[i],"=>",name, fill=TRUE)
	temp <- read.csv(filename[i])
	temp$name <- name
	data <- rbind(data, temp)
}

nthreads <- length(grep("T[0-9]*", names(data)))
cpn <- nthreads / nnodes

cat("\n#nodes:", nnodes, "\t#threads:", nthreads, fill=TRUE)

data$sum <- rowSums(data[,4:(4+nthreads-1)]) #Total number of memory accesses

for (i in 0:(nnodes-1)) {
  data[paste("N",i,sep="")] <- rowSums(data[,(i*cpn+4):((i+1)*cpn+3)]) #NUmber of accesses per node
}

data$max <- apply(data[,(ncol(data)-nnodes+1):ncol(data)], 1, max) #Highest number of accesses

data$excl <- data$max / data$sum * 100

myround <- function(x){val <- round_any(x, 10, f=floor); val<-lapply(val, max, 30); lapply(val, min, 90)}

data$excl_round <- as.numeric(myround(data$excl))

data$excl_round <- paste(data$excl_round, "%", sep="")
data$excl_round <- paste(ifelse(data$excl_round=="30%","<",""), data$excl_round, sep="")
data$excl_round <- paste(ifelse(data$excl_round=="90%",">",""), data$excl_round, sep="")
data <- transform(data, data.excl = factor(excl_round))

pdf(outfilename)

if (length(filename)>1) {
	ind <- c("name", "excl_round")
} else {
	ind <- "excl_round"
}

options(warn=-1)

treemap(data,
	index=ind,
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
