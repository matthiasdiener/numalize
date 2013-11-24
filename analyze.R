#!/usr/bin/env Rscript

## How to use:
# install required packages in R console:
# $ sudo R
# > install.packages("treemap")
#
# then run this script:
# $ ./analyze.R <input.csv> <#nodes>

paste0 <- function(..., sep = "") paste(..., sep = sep)

library(treemap)

# Get command line arguments
args <- commandArgs(trailingOnly=TRUE)
filenames <- args[1:(length(args)-1)]
outfilename <- gsub(".gz", "", gsub(".csv", ".pdf", filenames[1]))
nnodes <- as.numeric(args[length(args)])

# Read csv files
data <- do.call(rbind, lapply(filenames, function(f) {
	name <- toupper(gsub(".*/", "" , gsub("[.].*", "" , f)))
	cat ("Loading", f, "=>", name, "\n")
	temp <- read.csv(f)
	temp$name <- name
	return(temp)
	}))

threads <- grep("T\\d+", names(data))
nthreads <- length(threads)
nodes <- paste0("N", 1:nnodes)
tpn <- nthreads / nnodes

cat("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn, "\n")

# Total number of memory accesses
data$sum <- rowSums(data[threads])

# Number of accesses per node
for (i in 1:nnodes) {
	data[nodes[i]] <- rowSums(data[threads[((i-1)*tpn+1):(i*tpn)]])
}

# Highest number of accesses
data$max<-do.call(pmax, data[nodes])

# Exclusivity
data$excl <- data$max / data$sum * 100
excl_min <- ceiling(100/nnodes/10) * 10

# Round exclusivity and put >, < and %
data$excl_round <- pmax(pmin(round(data$excl/10)*10, 90), excl_min)
data$excl_round <- paste0(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%")

data$data.excl <- factor(data$excl_round)


pdf(outfilename)

options(warn=-1)

treemap(data,
	index=if (length(filenames)>1) c("name", "excl_round") else "excl_round",
	vSize="sum",
	vColor= "data.excl",
	type="categorical",
#	aspRatio=1,
	palette="Greens",
	# palette=c("#FFFFFF","#D2D2D2","#A8A8A8","#7E7E7E","#545454","#2A2A2A","#000000"),
	title="",
	title.legend="Exclusivity level",
	fontsize.labels=c(60,50,15),
	fontsize.legend=14,
	bg.labels="#FFFFFF",
	algorithm="pivotSize",
	sortID="color",
	position.legend="bottom",
	#overlap.labels=0
)

garbage <- dev.off()

system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))
cat("Exclusivity: ", sum(data$max)/sum(data$sum)*100, "\n")
cat("=> saved pdf in", outfilename, "\n")
