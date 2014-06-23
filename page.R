#!/usr/bin/env Rscript

options("scipen"=1000)

library(data.table)

args = commandArgs(trailingOnly=T)
if (length(args) != 2)
	stop("Usage: mkPageUp.R <page.csv> <#nodes>\n")

data = read.csv(args[1])
nnodes = as.numeric(args[2])

# data$addr = data$addr %/% 512
# data=data.table(data)
# data=data[, lapply(.SD, as.numeric)]
# data=data[, lapply(.SD, sum), by=addr]
# data=data.frame(data)


threads = grep("T\\d+", names(data))
nthreads = length(threads)
tpn = nthreads / nnodes
nodes=c((ncol(data)+1):(ncol(data)+nnodes))
n = split(threads, ceiling(seq_along(threads)/tpn))

ttn=c()
for (i in 1:length(n)) ttn[n[[i]]-3] = i


for (i in 1:length(nodes))
	data[nodes[i]] = rowSums(data[unlist(n[i])])

data = data[-threads]
data = data[-c(1:2)]

nodes = c(2:ncol(data))

data$sum = rowSums(data[nodes])
data$max = do.call(pmax, data[nodes])

cat("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn, "\n\n")

# first-touch correctness
data$correct_node = max.col(data[nodes], "first")
data$first_node = ttn[data$firstacc+1]
data$firsttouch_acc = (data$correct_node == data$first_node) * data$sum

# memory imbalance
num_pages = nrow(data)
data$rr_node = rep_len(c(1:nnodes), num_pages)

cat("memory balance (pages), first-touch\n")
table(data$first_node)
cat("memory balance (pages), correct_node\n")
table(data$correct_node)
cat("memory balance (pages), rr_node\n")
table(data$rr_node)

total=sum(data$sum)

cat("memory balance (accesses), first-touch\n")
for (i in 1:nnodes)
	cat(i, sum(data$sum[data$first_node==i])/total*100, "\n")

cat("memory balance (accesses), correct_node\n")
for (i in 1:nnodes)
	cat(i, sum(data$sum[data$correct_node==i])/total*100, "\n")

cat("memory balance (accesses), rr_node\n")
for (i in 1:nnodes)
	cat(i, sum(data$sum[data$rr_node==i])/total*100, "\n")


# Exclusivity
data$excl = data$max / data$sum * 100
data$excl[is.na(data$excl)] = 100
excl_min = ceiling(100/nnodes/10) * 10

# Round exclusivity and put >, < and %
data$excl_round = pmax(pmin(round(data$excl/10)*10, 90), excl_min)
data$excl_round = paste(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%", sep="")

DT = data.table(data)
DT[order(excl_round), sum(max), by=excl_round]

cat("\nApp Exclusivity:", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%\n")
cat("First touch correctness (pages):", sum((data$correct_node == data$first_node))/nrow(data)*100, "%\n")
cat("First touch correctness (accesses):", sum(data$firsttouch_acc, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%\n")
