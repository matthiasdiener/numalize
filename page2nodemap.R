#!/usr/bin/env Rscript

# mappings:
# - rr_node: round-robin mapping of pages to nodes
# - interleave: rr based on page address (equal to numactl -i all? uses last two bits of page addr to determine node)
# - locality: put page on node with highest locality
# - membalance: rr, such that number of memory accesses to all nodes are equal
# - locality+distribution: locality for pages with high exclusivity, rr for low excl.
# - random: random assignment

options("scipen"=1000)

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

data$excl = data$max / data$sum * 100

# first-touch correctness
data$local_node = max.col(data[nodes], "first")
data$first_node = ttn[data$firstacc+1]
data$firsttouch_acc = (data$local_node == data$first_node) * data$sum

# memory imbalance
num_pages = nrow(data)
total = sum(data$sum)


### data mappings
# round robin (rr)
data$rr_node = rep_len(c(1:nnodes), num_pages)
write.table(data[, c("addr", "rr_node")], file=paste(args[1], ".rr", sep=""), row.names=F, col.names=F)
cat("wrote .rr\n")


# locality (local)
write.table(data[, c("addr", "local_node")], file=paste(args[1], ".local", sep=""), row.names=F, col.names=F)
cat("wrote .local\n")

# interleave (inter)
data$inter_node = (data$addr %% nnodes) + 1
write.table(data[, c("addr", "inter_node")], file=paste(args[1], ".inter", sep=""), row.names=F, col.names=F)
cat("wrote .inter\n")


# random
set.seed(1)
data$random_node = floor(runif(num_pages, 1, nnodes+1))
write.table(data[, c("addr", "random_node")], file=paste(args[1], ".random", sep=""), row.names=F, col.names=F)
cat("wrote .random\n")


# mixed
data$mixed_node = ifelse(data$excl > 95, data$local_node, data$rr_node)
write.table(data[, c("addr", "mixed_node")], file=paste(args[1], ".mixed", sep=""), row.names=F, col.names=F)
cat("wrote .mixed\n")


# membalance (bal)
# sort pages by #accesses

x = data[order(data$sum,decreasing = T),]
x$bal_node = 0

total = sum(x$sum)

for (i in 1:num_pages) {
	n = x[i,'local_node']
	a = x[i,'addr']

	if (sum(x$sum[x$bal_node==n])/total < 1/nnodes)
		x[i,'bal_node'] = n
	else {
		j = 1
		while (sum(x$sum[x$bal_node==j])/total > 1/nnodes)
			j = (j %% nnodes) + 1
		x[i,'bal_node'] = j
	}
}

cat("memory balance (accesses), bal_node\n")
for (i in 1:nnodes)
	cat(i, sum(x$sum[x$bal_node==i])/sum(x$sum)*100, "\n")

write.table(x[, c("addr", "bal_node")], file=paste(args[1], ".bal", sep=""), row.names=F, col.names=F)
cat("wrote .bal\n")
