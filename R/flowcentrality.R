#' Determine dendritic/axonal by calculating flow centrality
#'
#' @description implementation of the algorithm for calculating  flow
#'   centralities from Schneider-Mizell et al. (2016)
#'
#' @param x a neuronlist or neuron object
#' @param mode type of flow centrality to calculate. There are three flavors:
#'   (1) centrifugal, which counts paths from proximal inputs to distal outputs;
#'   (2) centripetal, which counts paths from distal inputs to proximal outputs;
#'   and (3) the sum of both.
#' @param polypre whether to consider the number of presynapses as a multiple of
#'   the numbers of connections each makes
#' @param primary.dendrite whether to try to assign nodes to a 'primary
#'   dendrite'. Defaults to considering nodes of 0.9*maximal flow centrality.
#'   Assigning to NULL will prevent generating this compartment.
#' @param ... additional arguments passed to methods.
#'
#' @details From Schneider-Mizell et al. (2016): "We use flow centrality for
#'   four purposes. First, to split an arbor into axon and dendrite at the
#'   maximum centrifugal SFC, which is a preliminary step for computing the
#'   segregation index, for expressing all kinds of connectivity edges (e.g.
#'   axo-axonic, dendro-dendritic) in the wiring diagram, or for rendering the
#'   arbor in 3d with differently colored regions. Second, to quantitatively
#'   estimate the cable distance between the axon terminals and dendritic arbor
#'   by measuring the amount of cable with the maximum centrifugal SFC value.
#'   Third, to measure the cable length of the main den- dritic shafts using
#'   centripetal SFC, which applies only to insect neurons with at least one
#'   output syn- apse in their dendritic arbor. And fourth, to weigh the color
#'   of each skeleton node in a 3d view, providing a characteristic signature of
#'   the arbor that enables subjective evaluation of its identity."
#'
#' @references Schneider-Mizell, C. M., Gerhard, S., Longair, M., Kazimiers, T.,
#'   Li, F., Zwart, M. F., … Cardona, A. (2015). Quantitative neuroanatomy for
#'   connectomics in Drosophila. bioRxiv, 026617. http://doi.org/10.1101/026617
#'
#' @return the neuron or neuron list object inputted, with centipetal flow
#'   centrality information added to neuron$d, a segregation idnex score and
#'   estimation of neuronal type (intertneuron or PN) based on this score (>0.05
#'   = PN).
#' @export
#' @rdname flow.centrality
#' @seealso \code{\link{seesplit3d}} \code{\link{get.synapses}}
flow.centrality <-function(someneuronlist, mode = c("average","centrifugal","centripetal"), polypre = T, primary.dendrite = 0.9, ...) UseMethod("flow.centrality")

#' @export
#' @rdname flow.centrality
flow.centrality.neuron <- function(neuron, mode = c("average","centrifugal","centripetal"), polypre = T, primary.dendrite = 0.9, ...){
  # prune Strahler first...and use segmentgraph?
  # Generate ngraph object
  el = neuron$d[neuron$d$Parent != -1, c("Parent", "PointNo")] # Get list of soma=leaf directed conenctions
  n = nat::ngraph(data.matrix(el[,2:1]), neuron$d$PointNo, directed = TRUE, xyz = nat::xyzmatrix(neuron$d),
                  diam = neuron$d$W) # Make ngraph object, but for centripetal, invert the el list
  # Get comprehensive paths list
  leaves = which(igraph::degree(n, v = igraph::V(n), mode = "in")==0, useNames = T)
  root= which(igraph::degree(n, v = igraph::V(n), mode = "out")==0, useNames = T)
  segs = neuron$SegList # Get the segment list
  nodes = neuron$d # get neuron's node data
  nodes[,"post"] <- 0 # raw synapse number at this location
  nodes[,"pre"] <- 0 # raw synapse number at this location
  nodes[,"up.syns.in"] <- 0 # Here, we are going to culmulatively count synapses
  nodes[,"up.syns.out"] <- 0 # Same but for outputs
  nodes[,"flow.cent"] <- 0 # We'll addd the score for each node here
  nodes[,"compartment"] <- 'dendrite'
  nodes = nodes[unlist(c(root, lapply(segs, function (x) x[-1]))),]
  syns.in = neuron$connectors[neuron$connectors[,3]==1,][,1]
  if (polypre == T){
    pres = neuron$connectors[neuron$connectors[,3]==0,][,2]
    pre.cons = catmaid_get_connectors(pres)$connector_id
    syns.out = neuron$connectors[,1][match(pre.cons, neuron$connectors[,2])]
  }else{
    syns.out = neuron$connectors[neuron$connectors[,3]==0,][,1]
  }
  # Rearrange so nodes are the indices and we can count no. of synapses to which nodes connect
  point.no.in = rownames(nodes)[match(syns.in,nodes[,"PointNo"])]
  nodes.in = rep(1,length(point.no.in))
  names(nodes.in) = point.no.in
  nodes.in = tapply(nodes.in, point.no.in, sum)
  point.no.out = rownames(nodes)[match(syns.out,nodes[,"PointNo"])]
  nodes.out = rep(1,length(point.no.out))
  names(nodes.out) = point.no.out
  nodes.out = tapply(nodes.out, point.no.out, sum)
  # Add more accurate synapose positions
  nodes[names(nodes.in),"post"] <- nodes.in
  nodes[names(nodes.out),"pre"] <- nodes.out
  # Add running totals from the seglist and synapse positions to data matrix
  ins = c(0,lapply(segs, function(x) if(!is.null(x)){rev(cumsum(rev(unlist(lapply(x, function(x) ifelse(x%in%names(nodes.in),nodes[as.character(x),"post"],0))))))}))
  outs = c(0,lapply(segs, function(x) if(!is.null(x)){rev(cumsum(rev(unlist(lapply(x, function(x) ifelse(x%in%names(nodes.out),nodes[as.character(x),"pre"],0))))))}))
  nodes[,"up.syns.in"] = nodes[,"up.syns.in"] + c(0,unlist(lapply(ins, function(x) x[-1])))
  nodes[,"up.syns.out"] = nodes[,"up.syns.out"] + c(0,unlist(lapply(outs, function(x) x[-1])))
  # Add in the branch node point carried on from other upstream branches
  in.bps = unlist(lapply(ins, function(x) x[1]))[-1]
  out.bps = unlist(lapply(outs, function(x) x[1]))[-1]
  names(in.bps) = names(out.bps) = bps = c(root,unlist(lapply(segs, function(x) x[1]))[-1])
  in.bps[names(in.bps)%in%names(nodes.in)] = in.bps[names(in.bps)%in%names(nodes.in)] - nodes[names(in.bps)[names(in.bps)%in%names(nodes.in)],"post"]
  out.bps[names(out.bps)%in%names(nodes.out)] = out.bps[names(out.bps)%in%names(nodes.out)] - nodes[names(out.bps)[names(out.bps)%in%names(nodes.out)],"pre"]
  # Propagate scores from branch nodes
  for (i in 1:length(bps)){
    bp = bps[i]
    new.in = new.out = c(rep(0,nrow(nodes)))
    names(new.in) = names(new.out) = rownames(nodes)
    vertices = unlist(igraph::shortest_paths(n, bp, to = root)$vpath)[-1]
    new.in[as.character(vertices)] = new.in[as.character(vertices)] + in.bps[i]
    new.out[as.character(vertices)] = new.out[as.character(vertices)] + out.bps[i]
    nodes[,"up.syns.in"] = nodes[,"up.syns.in"]+ new.in
    nodes[,"up.syns.out"] = nodes[,"up.syns.out"] + new.out
  }
  # Calculate flow centrality
  in.total = nodes[1,"up.syns.in"] = length(point.no.in)
  out.total = nodes[1,"up.syns.out"] = length(point.no.out)
  if(mode[1] == "centrifugal"){nodes[,"flow.cent"] = (in.total - nodes[,"up.syns.in"])*nodes[,"up.syns.out"]}
  if(mode[1] == "centripetal"){nodes[,"flow.cent"] = (out.total - nodes[,"up.syns.out"])*nodes[,"up.syns.in"]}
  if(mode[1] == "average"){nodes[,"flow.cent"] = (in.total - nodes[,"up.syns.in"])*nodes[,"up.syns.out"] + (out.total - nodes[,"up.syns.out"])*nodes[,"up.syns.in"]}
  nodes = nodes[order(as.numeric(rownames(nodes))),]
  ais = which(apply(nodes, 1, function(x) x["flow.cent"] == max(nodes[,"flow.cent"])))
  if (length(ais)>0){
    runstosoma = unlist(lapply(ais, function(x) length(unlist(igraph::shortest_paths(n, x, to = root)$vpath))))
    ais = ais[match(min(runstosoma),runstosoma)]
  }
  downstream = suppressWarnings(unique(unlist(igraph::shortest_paths(n, ais, to = leaves, mode = "in")$vpath)))
  upstream = rownames(nodes)[!rownames(nodes)%in%downstream]
  if (sum(nodes[as.character(downstream),"pre"]) > sum(nodes[as.character(upstream),"pre"])){
    nodes[as.character(downstream),"compartment"] = "axon"
  }else {
    nodes[as.character(upstream),"compartment"] = "axon"
  }
  # Work out the primary neurite and empty leaf compartments
  zeros = subset(rownames(nodes),nodes[,"flow.cent"]==0)
  remove = rownames(nodes)[!rownames(nodes)%in%zeros]
  igraph::V(n)$name = igraph::V(n)
  nn = igraph::delete_vertices(n, v = as.character(remove))
  clust = igraph::clusters(nn)
  soma.group = clust$membership[names(clust$membership)==root]
  p.n = names(clust$membership)[clust$membership==soma.group]
  nodes[p.n,"compartment"] = "primary neurite"
  nodes[zeros[!zeros%in%p.n],"compartment"] = "null"
  if(!is.null(primary.dendrite)){
    highs = subset(rownames(nodes),nodes[,"flow.cent"]>=primary.dendrite*max(nodes[,"flow.cent"]))
    nodes[as.character(highs),"compartment"] = "primary dendrite"
  }
  # Calculate segregation score
  dendrites = subset(nodes, nodes$compartment == "dendrite")
  dendrites.post = sum(subset(dendrites$post,dendrites$post>0))
  dendrites.pre = sum(subset(dendrites$pre,dendrites$pre>0))
  dendrites.both = dendrites.post + dendrites.pre
  dendrites.pi = dendrites.post/dendrites.both
  dendrites.si = -(dendrites.pi*log(dendrites.pi)+(1-dendrites.pi)*log(1-dendrites.pi))
  if(is.nan(dendrites.si)){dendrites.si = 0}
  axon = subset(nodes, nodes$compartment == "axon")
  axon.post = sum(subset(axon$post,axon$post>0))
  axon.pre = sum(subset(axon$pre,axon$pre>0))
  axon.both = axon.post + axon.pre
  axon.pi = axon.post/axon.both
  axon.si = -(axon.pi*log(axon.pi)+(1-axon.pi)*log(1-axon.pi))
  if(is.nan(axon.si)){axon.si = 0}
  entropy.score = (1/(dendrites.both+axon.both))*((axon.si*axon.both)+(dendrites.si*dendrites.both))
  both.comps = (dendrites.pre+axon.pre)/(dendrites.both+axon.both)
  # both.comps = sum(nodes$post)/(sum(nodes$pre+sum(nodes$post)))
  control.score = -(both.comps*log(both.comps)+(1-both.comps)*log(1-both.comps))
  segregation.index = 1 - (entropy.score/control.score)
  if(is.na(segregation.index)) { segregation.index = 0 }
  # Add new data to object
  neuron$d = nodes
  neuron$segregation.index = segregation.index
  neuron$type = ifelse(segregation.index > 0.05, "interneuron", "PN")
  neuron
}

#' @export
#' @rdname flow.centrality
flow.centrality.neuronlist <- function(someneuronlist, mode = c("average","centrifugal","centripetal"), polypre = T, primary.dendrite = 0.9, ...){
  neurons = nat::nlapply(someneuronlist, flow.centrality, mode = mode, polypre = polypre, primary.dendrite = primary.dendrite, OmitFailures = T)
  neurons
}


#' Plot neurons split up by flow centrality
#'
#' @param someneuronlist a neuronlist or neuron object that has been modified by flow.centrality
#' @param col colours of sections. Defaults to orange or axons, green for primary dendrite, blue for dendrites and pink for nodes with no flow.
#' @param primary.dendrite Type of object for Deformetrica deformation. See Deformetrica's documentation. Default is appropriate for neuron skeletons.
#' @param WithConnectors whether ot plot the anatomical location of pre (red) and post (cyan) synapses.
#' @param soma whether to plot a soma, and what the radius should be
#' @param WithNodes whether to plot branch points
#' @param highflow wheather to plot the nodes of highest (with in one standard deviation less than maximum) flow centrality (pink points)
#' @param ... additional arguments passed to methods.
#'
#' @return Plots coloured neuron(s)
#' @export
#' @rdname seesplit3d
#' @seealso \code{\link{flow.centrality}} \code{\link{get.synapses}}
seesplit3d = function(someneuronlist, col = c("blue", "orange", "purple","green", "grey", "pink"), WithConnectors = T, WithNodes = F, soma = 100, highflow = F){
  someneuronlist = as.neuronlist(someneuronlist)
  for (n in 1:length(someneuronlist)){
    neuron = someneuronlist[[n]]
    if(is.null(neuron$d$flow.cent)){
      warning("No flow centrality calculated, dropping neuron")
      break
    }
    dendrites.v = subset(rownames(neuron$d), neuron$d$compartment == "dendrite")
    axon.v = subset(rownames(neuron$d), neuron$d$compartment == "axon")
    nulls.v = subset(rownames(neuron$d), neuron$d$compartment == "null")
    p.d.v = subset(rownames(neuron$d), neuron$d$compartment == "primary dendrite")
    p.n.v = subset(rownames(neuron$d), neuron$d$compartment == "primary neurite")
    dendrites = nat::prune_vertices(neuron, verticestoprune = as.integer(c(axon.v, nulls.v, p.d.v, p.n.v)))
    axon = nat::prune_vertices(neuron, verticestoprune = as.integer(c(nulls.v, dendrites.v, p.d.v, p.n.v)))
    nulls = nat::prune_vertices(neuron, verticestoprune = as.integer(c(axon.v, dendrites.v, p.d.v, p.n.v)))
    p.d = prune_vertices(neuron, verticestoprune = as.integer(c(axon.v, dendrites.v, nulls.v, p.n.v)))
    p.n = prune_vertices(neuron, verticestoprune = as.integer(c(axon.v, dendrites.v, nulls.v, p.d.v)))
    rgl::plot3d(dendrites, col = col[1], WithNodes = WithNodes)
    rgl::plot3d(axon, col = col[2], WithNodes = WithNodes)
    rgl::plot3d(p.n, col = col[3], WithNodes = WithNodes, soma = soma)
    rgl::plot3d(p.d, col = col[4], WithNodes = WithNodes)
    rgl::plot3d(nulls, col = col[5], WithNodes = WithNodes)
    if (WithConnectors == T){
      rgl::points3d(subset(xyzmatrix(neuron$d),neuron$d$post>0), col = 'cyan')
      rgl::points3d(subset(xyzmatrix(neuron$d),neuron$d$pre>0), col = 'red')
    }
    if (highflow == T){
      highest = max(neuron$d[,"flow.cent"])
      s.d = sd(neuron$d[,"flow.cent"], na.rm = T)
      high = subset(neuron$d, neuron$d[,"flow.cent"] > (highest - s.d))
      rgl::points3d(nat::xyzmatrix(high), col = col[6])
    }
  }
}


#' @export
#' @rdname seesplit3d
splitscan <- function (someneuronlist, col = c("blue", "orange", "purple","green", "grey", "pink"), WithConnectors = T, WithNodes = F, soma = 100, highflow = F, Verbose = T, Wait = T,
          sleep = 0.1, extrafun = NULL, selected_file = NULL, selected_col = "black",
          yaml = TRUE, ...)
{
  if (is.neuronlist(someneuronlist)) {
    db = someneuronlist
    neurons = as.data.frame(db)$name
  }
  frames <- length(neurons)
  selected <- character()
  i <- 1
  if (!is.null(selected_file) && file.exists(selected_file)) {
    selected <- yaml.load_file(selected_file)
    if (!all(names(selected) %in% neurons))
      stop("Mismatch between selection file and neurons.")
  }
  savetodisk <- function(selected, selected_file) {
    if (is.null(selected_file))
      selected_file <- file.choose(new = TRUE)
    if (yaml) {
      if (!grepl("\\.yaml$", selected_file))
        selected_file <- paste(selected_file, sep = "",
                               ".yaml")
      message("Saving selection to disk as ", selected_file,
              ".")
      writeLines(as.yaml(selected), con = selected_file)
    }
    else {
      if (!grepl("\\.rda$", selected_file))
        selected_file <- paste(selected_file, sep = "",
                               ".rda")
      save(selected, file = selected_file)
      message("Saving selection to disk as ", selected_file)
    }
    selected_file
  }
  chc <- NULL
  while (TRUE) {
    if (i > length(neurons) || i < 1)
      break
    n <- neurons[i]
    cat("Current neuron:", n, "(", i, "/", length(neurons),
        ")\n")
    pl <- seesplit3d(someneuronlist[i], col = col, WithConnectors = WithConnectors, WithNodes = WithNodes, soma = soma, highflow = highflow)
    print(someneuronlist[[i]]$segregation.index)
    more_rgl_ids <- list()
    if (!is.null(extrafun))
      more_rgl_ids <- extrafun(n, selected = selected)
    if (Wait) {
      chc <- readline("Return to continue, b to go back, s to select, d [save to disk], t to stop, c to cancel (without returning a selection): ")
      if (chc == "c" || chc == "t") {
        sapply(pl, rgl::rgl.pop, type = "shape")
        sapply(more_rgl_ids, rgl::rgl.pop, type = "shape")
        break
      }
      if (chc == "s") {
        if (n %in% selected) {
          message("Deselected: ", n)
          selected <- setdiff(selected, n)
        }
        else selected <- union(selected, n)
      }
      if (chc == "b")
        i <- i - 1
      else if (chc == "d")
        savetodisk(selected, selected_file)
      else i <- i + 1
    }
    else {
      Sys.sleep(sleep)
      i <- i + 1
    }
    sapply(pl, rgl::rgl.pop, type = "shape")
    sapply(more_rgl_ids, rgl::rgl.pop, type = "shape")
    rgl::clear3d()
  }
  if (is.null(chc) || chc == "c")
    return(NULL)
  if (!is.null(selected_file))
    savetodisk(selected, selected_file)
  selected
}
