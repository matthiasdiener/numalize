#!/usr/bin/env Rscript

library(data.table)

paste0 <- function(..., sep = "") paste(..., sep = sep)
catn <- function(...) cat(..., "\n")

local({r <- getOption("repos"); r["CRAN"] <- "http://cran.r-project.org"; options(repos=r)})

if (!suppressPackageStartupMessages(require(treemap))) {
	install.packages("treemap")
	library(treemap)
}

# Get command line arguments
args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 2)
	stop("Usage: mkPageUp.R <page.csv>... <#nodes>\n")

filenames <- args[1:(length(args)-1)]
nnodes <- as.numeric(args[length(args)])
outfilename <- ""

# Read csv files
# data <- do.call(rbind, lapply(filenames, function(f) {
# 	name <- toupper(gsub(".*/", "" , gsub("[.].*", "" , f)))
# 	catn("Loading", f, "=>", name)
# 	temp <- read.csv(f)
# 	# aggregate(temp, by=list(temp$addr%/%64), sum)
# 	temp$name <- name
# 	outfilename <<- paste0(outfilename, name, "_")
# 	return(temp)
# 	}))

data=read.csv(filenames[1])

# data$addr = data$addr %/% 512
# data=data.table(data)
# data=data[, lapply(.SD, as.numeric)]
# data=data[, lapply(.SD, sum), by=addr]
# data=data.frame(data)

outfilename <- paste0(gsub(".$", "", outfilename), ".pdf")

threads <- grep("T\\d+", names(data))
nthreads <- length(threads)

if (nnodes > nthreads)
	nnodes <- nthreads

nodes <- paste0("N", 0:(nnodes-1))
tpn <- nthreads / nnodes

catn("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn)

# Total number of memory accesses
data$sum <- rowSums(data[threads])

# Number of accesses per node
for (i in 0:(nnodes-1))
	data[nodes[i+1]] <- rowSums(data[threads[(i*tpn+1):((i+1)*tpn)]])

# Highest number of accesses
data$max <- do.call(pmax, data[nodes])

# first-touch correctness
data$correct_node <- max.col(data[nodes], "first")-1
ttn <- ceiling((threads-3)/tpn)-1
data$first_node <- ttn[data$firstacc+1]
data$firsttouch_acc <- (data$correct_node == data$first_node) * data$sum

# Exclusivity
data$excl <- data$max / data$sum * 100
excl_min <- ceiling(100/nnodes/10) * 10

# Round exclusivity and put >, < and %
data$excl_round <- pmax(pmin(round(data$excl/10)*10, 90), excl_min)
data$excl_round <- paste0(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%")

DT <- data.table(data)
DT[order(excl_round), sum(max), by=excl_round]

# data$data.excl <- factor(data$excl_round)


# pdf(outfilename)

# options(warn=-1)

# treemap(data,
# 	index=c("name", "excl_round"),
# 	vSize="sum",
# 	vColor= "data.excl",
# 	type="categorical",
# 	aspRatio=2,
# 	palette="Greys",
# 	# palette=c("#FFFFFF","#D2D2D2","#A8A8A8","#7E7E7E","#545454","#2A2A2A","#000000"),
# 	title="",
# 	title.legend="Exclusivity level",
# 	fontsize.labels=c(25,0,0),
# 	fontsize.legend=20,
# 	bg.labels="#FFFFFF",
# 	algorithm="pivotSize",
# 	sortID="color",
# 	position.legend="bottom",
# 	#overlap.labels=0
# )

# garbage <- dev.off()

# system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))
catn("Exclusivity:", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%")
catn("First touch correctness:", sum(data$firsttouch_acc)/sum(data$sum)*100, "%")
# catn("=> saved pdf in", outfilename)
