#!/usr/bin/env Rscript

files = list.files(pattern="\\.page\\.csv$")

nnodes = 4

cat("#nodes:", nnodes, "\n")

excl = c()

addn = function(frame) {
	threads = grep("T\\d+", names(frame))
	nthreads = length(threads)
	tpn = nthreads / nnodes
	nodes = c((ncol(frame)+1):(ncol(frame)+nnodes))
	n = split(threads, ceiling(seq_along(threads)/tpn))

	cat("\t#threads:", nthreads)

	for (i in 1:length(nodes)) {
		frame[nodes[i]] = rowSums(frame[unlist(n[i])])
	}

	frame$sum = rowSums(frame[nodes])
	frame$max = do.call(pmax, frame[nodes])
	excl <<- c(excl, sum(frame$max, na.rm=TRUE)/sum(frame$sum, na.rm=TRUE)*100)

	frame$cn = max.col(frame[nodes], ties.method="first")
	frame = data.frame(frame$addr, frame$cn)
	frame = frame[!duplicated(frame[,1]),]

	return(frame)
}

tmp = list()

for (i in 1:length(files)) {
	cat("Reading ", files[i], " (", i, "/" ,length(files), ")", sep="")
	tmp[[i]] = addn(read.csv(files[i]))
	cat("\tdone\n")
}

cn = tmp[[1]]

for (i in 2:length(tmp)) {
	cat("Merging file ", i, "/", length(tmp), sep="")
	cn = merge(cn, tmp[[i]], all=T, by=1)
	names(cn)[ncol(cn)] = i
	# cat (max(table(cn[,1])))
	cat("\tdone\n")
}


# remove addr column
cn= cn[-1]


cnt2 = function(vec) {
	cur = 0
	res = vector()
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


res = apply(cn, 1, cnt2)
res = data.frame(t(res))
names(res) = sub("X", "Step", names(res))
res[nrow(res)+1,] = colSums(res)
res$sum = rowSums(res)

excl = c(round(excl, 2), 0)

res = rbind(res, excl)

row.names(res)[nrow(res)] = "excl"
row.names(res)[nrow(res)-1] = "nmig"

res = cbind(id=rownames(res), res)

write.csv(res, file="page_dyn.csv", quote=F, row.names=F)

cat("Created file page_dyn.csv\n")
