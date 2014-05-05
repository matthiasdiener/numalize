#!/usr/bin/env Rscript

paste0 <- function(..., sep = "") paste(..., sep = sep)

files <- list.files(pattern=".page.csv$")

nnodes=4
tpn=16
nodes <- paste0("N", 0:(nnodes-1))

addn = function(frame) {
	threads <- grep("T\\d+", names(frame))

	for (i in 0:(nnodes-1))
		frame[nodes[i+1]] <- rowSums(frame[threads[(i*tpn+1):((i+1)*tpn)]])

	frame$cn = max.col(frame[nodes], ties.method="first")
	frame=data.frame(frame$addr, frame$cn)
	return(frame)
}

tmp=list()

for (i in 1:length(files)) {
	cat("Reading", files[i])
	tmp[[i]]=addn(read.csv(files[i]))
	cat(" done\n")
}

cn=tmp[[1]]

for (i in 2:length(tmp)) {
	cn=merge(cn, tmp[[i]], all=T, by=1)
	names(cn)[ncol(cn)] = i
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

write.csv(res, file="full.csv")

