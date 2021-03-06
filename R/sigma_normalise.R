#' @include generics.R
#' @export
setMethod("normalise_theta", "sigma_block", function(object, data.design = assay_design(object), norm.groups = NULL, input = "model1", type = "group.quants", ...) {
  cat(paste0("[", Sys.time(), "]    seaMass-theta normalisation...\n"))

  unlink(file.path(filepath(object), input, "*.normalised.group.quants.fst"))
  unlink(file.path(filepath(object), input, "*.normalised.group.variances.fst"))
  unlink(file.path(filepath(object), input, "*.assay.means.fst"))

  dir.create(file.path(filepath(object), input, "normalised.group.quants"), showWarnings = F)
  dir.create(file.path(filepath(object), input, "normalised.group.variances"), showWarnings = F)
  dir.create(file.path(filepath(object), input, "assay.means"), showWarnings = F)

  if (!is.null(norm.groups)) norm.groups <- groups(object, as.data.table = T)[grep(norm.groups, Group), Group]

  ctrl <- control(object)
  parallel_lapply(as.list(1:ctrl@model.nchain), function(item, object, norm.groups, input, type) {
    ctrl <- control(object)
    DT.summary <- read_samples(object, input, type, norm.groups, summary = T, as.data.table = T)[, .(Group, Assay, m, s)]
    DT <- copy(DT.summary)
    DT[, Assay := factor(as.integer(Assay))]
    DT[, Group := factor(as.integer(Group))]

    # seaMass-Θ Bayesian model
    set.seed(ctrl@random.seed + item - 1)
    model <- MCMCglmm::MCMCglmm(
      m ~ Group + Assay,
      mev = DT[, s]^2,
      rcov = ~ idh(Group):units,
      data = DT,
      prior = list(R = list(V = diag(nlevels(DT[, Group])), nu = 2e-4)),
      burnin = ctrl@norm.nwarmup,
      nitt = ctrl@norm.nwarmup + (ctrl@model.nsample * ctrl@norm.thin) / ctrl@model.nchain,
      thin = ctrl@norm.thin,
      verbose = F
    )

    # create emmeans ref grid
    class(model) <- "MCMCglmm_seaMass"
    frg <- emmeans::ref_grid(model, data = DT, nesting = NULL)

    # extract normalised group variances
    if ("normalised.group.variances" %in% ctrl@summarise || "normalised.group.variances" %in% ctrl@keep) {
      DT <- as.data.table(model$VCV[, grep("^Group.*\\.units", colnames(model$VCV))])
      DT[, chain := item]
      DT[, sample := 1:nrow(DT)]
      DT <- melt(DT, variable.name = "Group", value.name = "value", id.vars = c("chain", "sample"))
      DT[, Group := as.integer(sub("^Group(.+)\\.units", "\\1", as.character(Group)))]
      setcolorder(DT, "Group")
      # write
      setorder(DT, Group)
      fst::write.fst(DT, file.path(filepath(object), input, "normalised.group.variances", paste(item, "fst", sep = ".")))
      if (item == 1) {
        DT <- DT[, .(file = factor(file.path("normalised.group.variances", "1.fst")), from = min(.I), to = max(.I)), by = Group]
        DT[, Group := factor(Group, levels = 1:nlevels(DT.summary[, Group]), labels = levels(DT.summary[, Group]))]
        fst::write.fst(DT, file.path(filepath(object), input, "normalised.group.variances.index.fst"))
      }
    }

    # extract assay means
    DT.assay.means <- as.data.table(coda::as.mcmc(emmeans::emmeans(frg, "Assay")))
    DT.assay.means[, chain := item]
    DT.assay.means[, sample := 1:nrow(DT.assay.means)]
    DT.assay.means <- melt(DT.assay.means, variable.name = "Assay", id.vars = c("chain", "sample"))
    DT.assay.means[, Assay := as.integer(sub("^Assay ", "", as.character(Assay)))]
    setcolorder(DT.assay.means, "Assay")
    # write
    setorder(DT.assay.means, Assay)
    fst::write.fst(DT.assay.means, file.path(filepath(object), input, "assay.means", paste(item, "fst", sep = ".")))
    DT.assay.means[, Assay := factor(Assay, levels = 1:nlevels(DT.summary[, Assay]), labels = levels(DT.summary[, Assay]))]
    if (item == 1) {
      DT.index.assay.means <- DT.assay.means[, .(file = factor(file.path("assay.means", "1.fst")), from = min(.I), to = max(.I)), by = Assay]
      fst::write.fst(DT.index.assay.means, file.path(filepath(object), input, "assay.means.index.fst"))
    }

    # transform to assay deviations
    DT.assay.means[, value := value - mean(value), by = .(chain, sample)]
    # normalise group quants
    DT <- read_samples(object, input, "group.quants", chain = item, as.data.table = T)[, Block := NULL]
    DT <- merge(DT, DT.assay.means[, .(Assay, chain, sample, deviation = value)], by = c("Assay", "chain", "sample"), sort = F)
    DT[, value := value - deviation]
    DT[, deviation := NULL]
    setcolorder(DT, "Group")
    # write normalised group quants
    if (item == 1) fst::write.fst(DT[, .(file = file.path("normalised.group.quants", "1.fst"), from = min(.I), to = max(.I)), by = .(Group, Assay)], file.path(filepath(object), input, "normalised.group.quants.index.fst"))
    DT[, Group := as.integer(Group)]
    DT[, Assay := as.integer(Assay)]
    fst::write.fst(DT, file.path(filepath(object), input, "normalised.group.quants", paste(item, "fst", sep = ".")))

    return(NULL)
  }, nthread = ctrl@nthread)

  return(invisible(object))
})


#' @include generics.R
#' @export
setMethod("normalise_median", "sigma_block", function(object, norm.groups = NULL, input = "model1", type = "group.quants", ...) {
  cat(paste0("[", Sys.time(), "]    median normalisation...\n"))

  unlink(file.path(filepath(object), input, "*.normalised.group.quants.fst"))
  unlink(file.path(filepath(object), input, "*.assay.means.fst"))

  dir.create(file.path(filepath(object), input, "normalised.group.quants"), showWarnings = F)
  dir.create(file.path(filepath(object), input, "assay.means"), showWarnings = F)

  if (is.null(norm.groups)) norm.groups <- ".*"
  parallel_lapply(as.list(1:control(object)@model.nchain), function(item, object, norm.groups, input, type) {
    DT <- read_samples(object, input, type, chain = item, as.data.table = T)[, Block := NULL]

    # group mean centre
    DT[, value := value - mean(value), by = .(Group, chain, sample)]
    # median normalisation
    DT.assay.means <- DT[, .(deviation = median(value[grep(norm.groups, Group)])), by = .(Assay, chain, sample)]

    # normalise
    DT <- merge(DT, DT.assay.means, by = c("Assay", "chain", "sample"), sort = F)
    DT[, value := value - deviation]
    DT[, deviation := NULL]
    setcolorder(DT, "Group")

    # write normalised group quants
    if (item == 1) fst::write.fst(DT[, .(file = file.path("normalised.group.quants", "1.fst"), from = min(.I), to = max(.I)), by = .(Group, Assay)], file.path(filepath(object), input, "normalised.group.quants.index.fst"))
    DT[, Group := as.integer(Group)]
    DT[, Assay := as.integer(Assay)]
    fst::write.fst(DT, file.path(filepath(object), input, "normalised.group.quants", paste(item, "fst", sep = ".")))

    # write means
    setnames(DT.assay.means, "deviation", "value")
    if (item == 1) fst::write.fst(DT.assay.means[, .(file = file.path("assay.means", "1.fst"), from = min(.I), to = max(.I)), by = Assay], file.path(filepath(object), input, "assay.means.index.fst"))
    DT.assay.means[, Assay := as.integer(Assay)]
    fst::write.fst(DT.assay.means, file.path(filepath(object), input, "assay.means", paste(item, "fst", sep = ".")))

    return(NULL)
  }, nthread = control(object)@nthread)

  return(invisible(object))
})


#' @include generics.R
#' @export
setMethod("normalise_quantile", "sigma_block", function(object, input = "model1", type = "group.quants", ...) {
  cat(paste0("[", Sys.time(), "]    quantile normalisation...\n"))

  dir.create(file.path(filepath(object), input, "normalised.group.quants"), showWarnings = F)
  dir.create(file.path(filepath(object), input, "assay.means"), showWarnings = F)

  parallel_lapply(as.list(1:control(object)@model.nchain), function(item, object, input, type) {
    DT <- read_samples(object, input, type, chain = item, as.data.table = T)[, Block := NULL]

    # quantile normalisation
    DT[, mean := value]
    DT[, value := {
      DT <- dcast(.SD, Group ~ Assay, value.var = "value")
      DT.out <- as.data.table(preprocessCore::normalize.quantiles(as.matrix(DT[, !"Group"]), copy = T))
      DT.out$Group <- DT$Group
      setcolorder(DT.out, "Group")
      colnames(DT.out) <- colnames(DT)
      DT.out <- melt(DT.out, id.vars = "Group", variable.name = "Assay")
      DT.out <- merge(.SD[, .(Group, Assay)], DT.out, by = c("Group", "Assay"))
      DT.out[, value]
    }, by = .(chain, sample)]
    DT[, mean := mean - value]

    # mean means (for visualisation)
    DT.assay.means <- DT[, .(value = mean(mean)), by = .(Assay, chain, sample)]

    # write normalised group quants
    if (item == 1) fst::write.fst(DT[, .(file = file.path("normalised.group.quants", "1.fst"), from = min(.I), to = max(.I)), by = .(Group, Assay)], file.path(filepath(object), input, "normalised.group.quants.index.fst"))
    DT[, Group := as.integer(Group)]
    DT[, Assay := as.integer(Assay)]
    fst::write.fst(DT, file.path(filepath(object), input, "normalised.group.quants", paste(item, "fst", sep = ".")))

    # write mean means
    if (item == 1) fst::write.fst(DT.assay.means[, .(file = file.path("assay.means", "1.fst"), from = min(.I), to = max(.I)), by = Assay], file.path(filepath(object), input, "assay.means.index.fst"))
    DT.assay.means[, Assay := as.integer(Assay)]
    fst::write.fst(DT.assay.means, file.path(filepath(object), input, "assay.means", paste(item, "fst", sep = ".")))

    return(NULL)
  }, nthread = control(object)@nthread)

  return(invisible(object))
})
