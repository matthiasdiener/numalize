#!/usr/bin/env Rscript

library(data.table)

fs <- list.files(pattern="*.comm.csv") 

if (length(fs) < 1)
	stop("Usage: phases.R <CommPattern.csv>*\n")

l=c()

for (f in fs) {
	cat(f, "\n")

	d <- fread(f, header=F)
	#d=scan("~/Dropbox/CommP/bt.csv", sep=",", quiet=T, multi.line=F)
	nt <- length(d)

	# d <- (data / max(data)) * 100
	# d[d<30] <- 0
	d[d>30] <- 100

	#v <- 0
	#for (i in 1:nt) {
#		v <- v + var(d[-nt+1-i,i])
		# print (var(d[-nt+1-i,i]))
	#}
	v=sum(apply(d,1,var))

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

