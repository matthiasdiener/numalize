#!/usr/bin/env Rscript

## How to use:
# install required packages in R console:
# install.packages(c("treemap", "RColorBrewer")
#
# then run this script:
# $ ./analyze.R <input.csv> <nnodes>

paste0 <- function(..., sep = "") paste(..., sep = sep)

library("treemap")

args <- commandArgs(trailingOnly=TRUE)
filename <- args[1:(length(args)-1)]
outfilename <- gsub(".csv", ".pdf", filename[1])
outfilename <- gsub(".gz", "", outfilename)
nnodes <- as.numeric(args[length(args)])

# Read csv files
data <- do.call(rbind, lapply(filename, function(f) {
	name <- toupper(gsub(".*/", "" , gsub("[.].*", "" , f)))
	cat ("Loading", f, "=>", name, "\n")
	temp <- read.csv(f)
	temp$name <- name
	return(temp)
	}))

threads <- grep("T\\d+", names(data))
nthreads <- length(threads)
nodes <- paste0("N", 1:nnodes)
cpn <- nthreads / nnodes

cat("#nodes:", nnodes, "  #threads:", nthreads, fill=TRUE)

# Total number of memory accesses
data$sum <- rowSums(data[threads])

# Number of accesses per node
for (i in 1:nnodes) {
	data[nodes[i]] <- rowSums(data[threads[((i-1)*cpn+1):(i*cpn)]])
}

# Highest number of accesses
data$max<-do.call(pmax, data[nodes])

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
