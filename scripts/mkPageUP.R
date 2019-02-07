#!/usr/bin/env Rscript

library(treemap)

paste0 = function(..., sep = "") paste(..., sep = sep)
catn = function(...) cat(..., "\n")

local({r = getOption("repos"); r["CRAN"] = "http://cran.r-project.org"; options(repos=r)})

if (!suppressPackageStartupMessages(require(treemap))) {
	install.packages("treemap")
	library(treemap)
}

# Get command line arguments
args = commandArgs(trailingOnly=TRUE)
if (length(args) < 2)
	stop("Usage: mkPageUP.R <page.csv>... <#nodes>\n")

filenames = args[1:(length(args)-1)]
nnodes = as.numeric(args[length(args)])

for (filename in filenames) {

	data = read.csv(filename)

	outfilename = paste0(sub(".csv.xz", ".pageup", filename), ".pdf")

	# remove unused columns
	data = data[,!colnames(data) %in% c("nr", "alloc.thread", "alloc.location", "firsttouch.location", "structure.name")]

	colnames(data)[1] = "addr"
	colnames(data)[2] = "firstacc"

	threads = grep("T\\d+", names(data))
	nthreads = length(threads)
	tpn = nthreads / nnodes
	nodes = c((ncol(data)+1):(ncol(data)+nnodes))
	n = split(threads, ceiling(seq_along(threads)/tpn))

	ttn=c()
	for (i in 1:length(n)) ttn[n[[i]]-2] = i

	catn("#nodes:", nnodes, "  #threads:", nthreads, "  #threads per node:", tpn)


	for (i in 1:length(nodes))
		data[nodes[i]] = rowSums(data[unlist(n[i])])

	data = data[-threads]

	nodes = c(3:ncol(data))

	data$sum = rowSums(data[nodes])
	data$max = do.call(pmax, data[nodes])

	data$excl = data$max / data$sum * 100

	excl_min = ceiling(100/nnodes/10) * 10

	# Round exclusivity and put >, < and %
	data$excl_round = pmax(pmin(round(data$excl/10)*10, 90), excl_min)
	data$excl_round = paste0(ifelse(data$excl_round==excl_min,"<",""), ifelse(data$excl_round=="90",">",""), data$excl_round, "%")

	data$data.excl = factor(data$excl_round)


	pdf(outfilename, family="NimbusSan", width=8, height=8)

	options(warn=-1)

	treemap(data,
		index="excl_round",
		vSize="sum",
		vColor= "data.excl",
		type="categorical",
		aspRatio=1,
		palette="Greys",
		# palette=c("#FFFFFF","#D2D2D2","#A8A8A8","#7E7E7E","#545454","#2A2A2A","#000000"),
		title="",
		title.legend="Exclusivity level",
		fontsize.labels=c(25,0,0),
		fontsize.legend=20,
		bg.labels="#FFFFFF",
		algorithm="pivotSize",
		sortID="color",
		position.legend="bottom",
		#overlap.labels=0
	)

	garbage = dev.off()

	system(paste("pdfcrop ", outfilename, outfilename, "> /dev/null"))
	catn("Exclusivity:", sum(data$max, na.rm=TRUE)/sum(data$sum, na.rm=TRUE)*100, "%")
	catn("Generated", outfilename)
}
