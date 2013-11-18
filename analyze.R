#!/usr/bin/env Rscript

## How to use:
# install required packages in R console:
# install.packages(c("treemap", "RColorBrewer")
#
# then run this script:
# $ ./analyze.R <input.csv>

paste0 <- function(..., sep = "") paste(..., sep = sep)

library("treemap")

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1:(length(args)-1)]
outfilename <- gsub(".csv", ".pdf", filename[1])
outfilename <- gsub(".gz", "", outfilename)
nnodes <- as.numeric(args[length(args)])


data <- NULL

for (i in 1:length(filename)) {
	name <- gsub("[.].*", "" , filename[i])
	name <- toupper(gsub(".*/", "" , name))
	cat ("Loading", filename[i], "=>", name, "\n")
	temp <- read.csv(filename[i])
	temp$name <- name
	data <- rbind(data, temp)
}

nthreads <- length(grep("T[0-9]*", names(data)))
cpn <- nthreads / nnodes

cat("#nodes:", nnodes, "  #threads:", nthreads, fill=TRUE)

# Total number of memory accesses
data$sum <- rowSums(data[,4:(4+nthreads-1)])

# Number of accesses per node
for (i in 0:(nnodes-1)) {
  data[paste0("N",i)] <- rowSums(data[,(i*cpn+4):((i+1)*cpn+3)])
}

# Highest number of accesses
data$max<-do.call(pmax, data[,(3+nthreads+3):(3+nthreads+3+nnodes-1)])

# Exclusivity
data$excl <- data$max / data$sum * 100

# Round exclusivity and put >, < and %
data$excl_round <- pmax(pmin(round(data$excl/10)*10, 90), 30)
data$excl_round <- paste0(ifelse(data$excl_round=="30","<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%")

data <- transform(data, data.excl = factor(excl_round))

pdf(outfilename)

options(warn=-1)

treemap(data,
	index=if (length(filename)>1) c("name", "excl_round") else "excl_round",
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

system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))
cat("=> saved pdf in", outfilename)
