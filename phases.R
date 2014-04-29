#!/usr/bin/env Rscript


filenames <- commandArgs(trailingOnly=TRUE)

if (length(filenames) < 1)
	stop("Usage: phases.R <CommPattern.csv>*\n")

l=c()

for (i in 1:length(filenames)) {
	cat(filenames[i], "\n")

	d <- read.csv(filenames[i], header=F)
	nt <- length(data)

	# d <- (data / max(data)) * 100
	# d[d<30] <- 0
	d[d>30] <- 100

	v <- 0
	for (i in 1:nt) {
		v <- v + var(d[-nt+1-i,i])
		# print (var(d[-nt+1-i,i]))
	}

	l=append(l, v/nt)
	# avg <- sum(as.numeric(unlist(data)))/nt/nt

	# cat("hf_old:", var(data)/sum(data)/nt/nt, "\n")

	# cat(" ", v/nt, "\n")
	# cat(" ", avg, "\n")
}

# cat (min(l), max(l), var(l))

xx=split(l, ceiling(seq_along(l)/50))


m=c()

for (x in xx)
	m=append(m, mean(x))

xold=0
n=0
for (x in m) {
	print(x)
	if (is.na(x)) next
	if (findInterval(x, c(xold/1.2, xold*1.2)) == 0){

		print("new phase")
		n=n+1
	}
	xold=x

}
cat ("n= ", n, "\n")

# print (m)

