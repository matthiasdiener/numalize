#!/usr/bin/env Rscript

paste0 <- function(..., sep = "") paste(..., sep = sep)

args <- commandArgs(trailingOnly=TRUE)
if (length(args) < 2)
	stop("Usage: mkPageUp.R <page.csv>... <#nodes>\n")

filenames <- args[1:(length(args)-1)]
# nnodes <- as.numeric(args[length(args)])

# cn = data.frame()

j=1
nnodes=4
# nthreads=64
tpn=16
# ttn <- floor(0:(nthreads-1))/tpn
nodes <- paste0("N", 0:(nnodes-1))
# threads <- paste0("T", 0:(nnodes-1))

for (f in filenames) {
	cat(f, "\n")

	data=read.csv(f)
	threads <- grep("T\\d+", names(data))

	for (i in 0:(nnodes-1))
		data[nodes[i+1]] <- rowSums(data[threads[(i*tpn+1):((i+1)*tpn)]])


	# data$cn=apply(data[,nodes], 1, which.max)
	data$cn = max.col(data[nodes], ties.method="first")

	if (exists("cn")) {
		tmp = data.frame(data$addr, data$cn)
		names(tmp)[1] = "addr"
		cn = merge(cn, tmp, all=TRUE, by= "addr")
		names(cn)[ncol(cn)] = j
	}
	else {
		cn =data.frame(data$addr, data$cn)
		names(cn) = c("addr", 1)
	}
	j=j+1
}


cn= cn[-1]


cnt2 <- function(vec) {
	cur=0
	res=vector()
	for (i in 1:length(vec)) {
		if (cur != vec[i] && !is.na(vec[i])) {
			cur = vec[i]
			res[i] = 1
		} else {
			res[i] = 0
		}

	}
	res[match(1, res)] = 0
	return (res)
}


res=apply(cn, 1, cnt2)
res=data.frame(t(res))
res[nrow(res)+1,]= colSums(res)
res$sum <- rowSums(res)

write.csv(res, file="full_page.csv")

