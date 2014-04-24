#!/usr/bin/env Rscript

paste0 <- function(..., sep = "") paste(..., sep = sep)

args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 2)
	stop("Usage: mkPageUp.R <page.csv>... <#nodes>\n")

filenames <- args[1:(length(args)-1)]
# nnodes <- as.numeric(args[length(args)])

# cn = data.frame()

i=1
nnodes=4
nthreads=64
tpn=16
ttn <- floor(0:(nthreads-1))/tpn
nodes <- paste0("N", 0:(nnodes-1))
# threads <- paste0("T", 0:(nnodes-1))

for (f in filenames) {
	cat(f, "\n")

	data=read.csv(f)
	threads <- grep("T\\d+", names(data))

	for (i in 0:(nnodes-1))
		data[nodes[i+1]] <- rowSums(data[threads[(i*tpn+1):((i+1)*tpn)]])


	data$cn=apply(data[,nodes],1,which.max)

	if (exists("cn"))
		cn = cbind(cn, data$cn)
	else
		cn =data.frame(data$addr, data$cn)
	i=i+1
}

# write.csv(cn)

cn= cn[-1]
# cn= cn[-c(1,2)]
write.csv(cn)

apply(cn, 1, var)
