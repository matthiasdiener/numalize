#!/usr/bin/env Rscript

# mappings:
# - rr_node: round-robin mapping of pages to nodes
# - interleave: rr based on page address (equal to numactl -i all? uses last two bits of page addr to determine node)
# - locality: put page on node with highest locality
# - membalance: rr, such that number of memory accesses to all nodes are equal
# - locality+distribution: locality for pages with high exclusivity, rr for low excl.
# - random: random assignment

options("scipen"=1000)
library(data.table)

args = commandArgs(trailingOnly=T)
if (length(args) != 1)
	stop("Usage: page2nodemap.R <page.csv>\n")

data = read.csv(args[1])
nnodes = 4

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
data = data[-1]

nodes = c(3:ncol(data))

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


write.table(data[, c("addr", "rr_node")], file=paste(args[1], ".rr", sep=""), row.names=F, col.names=F)
cat("wrote .rr\n")

write.table(data[, c("addr", "correct_node")], file=paste(args[1], ".local", sep=""), row.names=F, col.names=F)
cat("wrote .local\n")
