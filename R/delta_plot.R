#' Volcano plot
#'
#' @param data.fdr .
#' @return A ggplot2 object.
#' @import data.table
#' @export
#' @include generics.R
plot_volcano <- function(
  data.fdr,
  contours = NULL,
  error.bars = TRUE,
  labels = 25,
  stdev.col = "PosteriorSD",
  x.col = "PosteriorMean",
  y.col = "qvalue"
) {
  DT.fdr <- as.data.table(data.fdr)
  DT.fdr[, s := get(stdev.col)]
  DT.fdr[, x := get(x.col)]
  if ("truth" %in% colnames(data.fdr)) {
    if (tolower(y.col) == "fdp") {
      # compute FDP
      DT.fdr[, FD := ifelse(truth == 0 | x * truth < 0, 1, 0)]
      DT.fdr[, Discoveries := 1:nrow(DT.fdr)]
      DT.fdr[, TrueDiscoveries := cumsum(1 - FD)]
      DT.fdr[, y := (0.5 + cumsum(FD)) / Discoveries]
      DT.fdr[, y := rev(cummin(rev(y)))]
    } else {
      DT.fdr[, y := get(y.col)]
    }
  } else {
    DT.fdr[, truth := 0]
    DT.fdr[, y := get(y.col)]
  }
  DT.fdr <- DT.fdr[complete.cases(DT.fdr)]
  suppressWarnings({
    DT.fdr[, lower := extraDistr::qlst(0.025, df, x, s)]
    DT.fdr[is.nan(lower), lower := x]
    DT.fdr[, upper := extraDistr::qlst(0.975, df, x, s)]
    DT.fdr[is.nan(upper), upper := x]
  })
  DT.fdr[, variable := Reduce(
    function(...) paste(..., sep = " : "),
    .SD[, (ifelse("Baseline" %in% colnames(DT.fdr), which(colnames(DT.fdr) == "Baseline"), 0) + 1):(which(colnames(DT.fdr) == "m") - 1)]
  )]
  DT.fdr[, Truth := factor(truth)]
  DT.fdr[, label := NA_character_]
  if (labels > 0) {
    if (y.col == "s" || y.col == "PosteriorSD") {
      DT.fdr[1:labels, label := as.character(variable)]
    } else {
      DT.fdr[1:labels, label := ifelse(get(y.col) < 0.1, as.character(variable), NA_character_)]
    }
  }
  DT.meta <- DT.fdr[, .(median = median(x, na.rm = T), .N), by = .(truth, Truth)]

  # transform y
  if (y.col == "s") {
    DT.fdr[, y := -log2(y)]
  } else {
    DT.fdr[, y := -log10(y)]
  }

  # contours
  DT.density <- NULL
  if (!(is.null(contours) || length(contours) == 0)) {
    DT <- DT.fdr[, .(x = rnorm(16, x, s), y, Truth), by = 1:nrow(DT.fdr)]
    DT <- DT[is.finite(x) & is.finite(y)]

    # bandwidth from all data
    try({
      H <- ks::Hpi(cbind(DT[, x], DT[, y]))
      xmin.kde <- c(min(DT[, x]), ifelse(y.col == "s" || y.col == "PosteriorSD", min(DT[, y]), 0))
      xmax.kde <- c(max(DT[, x]), max(DT[, y]))

      # generate density contour line
      DT.density <- DT[, {
        try(if (length(y) >= 5 * 16) {
          dens <- ks::kde.boundary(cbind(x, y), H, xmin = xmin.kde, xmax = xmax.kde, binned = T, bgridsize = c(1001, 1001))
          data.table(
            expand.grid(x = dens$eval.points[[1]], y = dens$eval.points[[2]]),
            z1 = as.vector(dens$estimate) / dens$cont["32%"],
            z2 = as.vector(dens$estimate) / dens$cont["5%"],
            z3 = as.vector(dens$estimate) / dens$cont["1%"]
          )
        })
      }, by = Truth]
    }, silent = T)
    rm(DT)
  }

  # plot
  xlim.plot <- c(min(DT.fdr[is.finite(x), m]), max(DT.fdr[is.finite(x), m]))
  xlim.plot <- c(-1.1, 1.1) * max(-xlim.plot[1], xlim.plot[2])
  ylim.plot <- c(min(DT.fdr[is.finite(y), y]), max(DT.fdr[is.finite(y), y]))
  ylim.plot <- ylim.plot + c(-0.01, 0.01) * (ylim.plot[2] - ylim.plot[1])
  ebh <- (ylim.plot[2] - ylim.plot[1]) / 500
  if (xlim.plot[2] < 1) xlim.plot <- c(-1, 1)
  if (ylim.plot[2] < 2) ylim.plot[2] <- 2
  DT.fdr[x <= xlim.plot[1], x := -Inf]
  DT.fdr[x >= xlim.plot[2], x := Inf]
  DT.fdr[y <= ylim.plot[1], y := -Inf]
  DT.fdr[y >= ylim.plot[2], y := Inf]

  g <- ggplot2::ggplot(DT.fdr, ggplot2::aes(x = x, y = y), colour = Truth)
  if (!is.null(DT.density)) {
    if (1 %in% contours) g <- g + ggplot2::stat_contour(data = DT.density, ggplot2::aes(x = x, y = y, z = z1, colour = Truth), breaks = 1)
    if (2 %in% contours) g <- g + ggplot2::stat_contour(data = DT.density, ggplot2::aes(x = x, y = y, z = z2, colour = Truth), breaks = 1)
    if (3 %in% contours) g <- g + ggplot2::stat_contour(data = DT.density, ggplot2::aes(x = x, y = y, z = z3, colour = Truth), breaks = 1)
  }
  if (error.bars) g <- g + ggplot2::geom_rect(ggplot2::aes(fill = Truth, xmin = lower, xmax = upper, ymin = y-ebh, ymax = y+ebh), size = 0, alpha = 0.2)
  g <- g + ggplot2::geom_point(ggplot2::aes(colour = Truth), size = 1)
  g <- g + ggplot2::geom_vline(xintercept = 0)
  g <- g + ggplot2::geom_hline(yintercept = ylim.plot[1])
  if (x.col == "m") {
    g <- g + ggplot2::xlab("log2(Fold Change)")
  } else if (x.col == "PosteriorMean") {
    g <- g + ggplot2::xlab("log2(Shrunk Fold Change)")
  } else {
    g <- g + ggplot2::xlab(paste0("log2(", x.col, ")"))
  }
  if (y.col == "s") {
    g <- g + ggplot2::ylab(paste0("-log2(Fold Change) Posterior Standard Deviation"))
  } else if (y.col == "PosteriorSD") {
    g <- g + ggplot2::ylab(paste0("-log2(Shrunk Fold Change) Posterior Standard Deviation"))
  } else {
    g <- g + ggplot2::ylab(paste0(paste0("-log10(", y.col, ")")))
    g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = -log10(0.01)), linetype = "dashed")
    g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = -log10(0.05)), linetype = "dashed")
  }
  if ("truth" %in% colnames(data.fdr)) {
    g <- g + ggplot2::geom_vline(ggplot2::aes(color = Truth, xintercept = truth), DT.meta[N >= 5])
    g <- g + ggplot2::geom_vline(ggplot2::aes(color = Truth, xintercept = median), DT.meta[N >= 5], lty = "longdash")
    g <- g + ggplot2::theme(legend.position = "top")
  } else {
    g <- g + ggplot2::theme(legend.position = "none")
  }
  g <- g + ggrepel::geom_label_repel(ggplot2::aes(label = label), size = 2.5, na.rm = T)
  g <- g + ggplot2::coord_cartesian(xlim = xlim.plot, ylim = ylim.plot, expand = F)
  g <- g + ggplot2::scale_colour_hue(l = 50)
  g <- g + ggplot2::scale_fill_discrete(guide = NULL)
  g
}


#' Add together two numbers.
#'
#' @param datafile A number.
#' @return The sum of \code{x} and \code{y}.
#' @import data.table
#' @export
plot_fdr <- function(
  data.fdr,
  y.max = NULL,
  y.col = "qvalue"
) {
  DT <- as.data.table(data.fdr)
  DT <- DT[!is.na(get(y.col))]
  DT <- rbind(DT[1], DT)
  DT[1, (y.col) := 0]
  DT[, Discoveries := 0:(.N-1)]

  pi <- y.max <- max(DT[, get(y.col)])
  if (is.null(y.max)) y.max <- pi
  xmax <- max(DT[get(y.col) <= y.max, Discoveries])
  ylabels <- function() function(x) format(x, digits = 2)

  g <- ggplot2::ggplot(DT, ggplot2::aes_string(x = "Discoveries", y = y.col))
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.01), linetype = "dotted")
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.05), linetype = "dotted")
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.10), linetype = "dotted")
  g <- g + ggplot2::geom_step(direction = "vh")
  g <- g + ggplot2::scale_x_continuous(expand = c(0, 0))
  g <- g + ggplot2::scale_y_reverse(breaks = sort(c(pi, 0.0, 0.01, 0.05, 0.1, 0.2, 0.5, 1.0)), labels = ylabels(), expand = c(0.001, 0.001))
  g <- g + ggplot2::coord_cartesian(xlim = c(0, xmax), ylim = c(y.max, 0))
  g <- g + ggplot2::xlab("Number of Discoveries")
  g <- g + ggplot2::ylab("False Discovery Rate")
  g
}


#' Precision-Recall plot
#'
#' @param data.fdr .
#' @param y.max .
#' @return A ggplot2 object.
#' @import data.table
#' @export
plot_pr <- function(
  data.fdr,
  plot.fdr = TRUE,
  y.max = NULL,
  legend.nrow = 1,
  y.col = "qvalue"
) {
  if (is.data.frame(data.fdr)) {
    DTs.pr <- list(unknown = data.fdr)
  } else {
    if (is.null(names(data.fdr))) stop("if data is a list, it needs to be a named list of data.frames")
    if (any(duplicated(names(data.fdr)))) stop("if data is a named list, none of the names should be duplicates")
    DTs.pr <- data.fdr
  }

  for (method in names(DTs.pr)) {
    DT.pr <- setDT(DTs.pr[[method]])
    DT.pr <- DT.pr[!is.na(truth)]
    if (is.null(DT.pr$lower)) DT.pr[, lower := get(y.col)]
    if (is.null(DT.pr$upper)) DT.pr[, upper := get(y.col)]
    DT.pr <- DT.pr[, .(lower, y = get(y.col), upper, FD = ifelse(truth == 0, 1, 0))]
    setorder(DT.pr, y, na.last = T)
    DT.pr[, Discoveries := 1:nrow(DT.pr)]
    DT.pr[, TrueDiscoveries := cumsum(1 - FD)]
    DT.pr[, FDP := cumsum(FD) / Discoveries]
    DT.pr[, FDP := rev(cummin(rev(FDP)))]
    DT.pr[, Method := method]
    DTs.pr[[method]] <- DT.pr
  }
  DTs.pr <- rbindlist(DTs.pr)
  DTs.pr[, Method := factor(Method, levels = unique(Method))]

  ylabels <- function() function(x) format(x, digits = 2)

  pi <- 1.0 - max(DTs.pr$TrueDiscoveries) / max(DTs.pr$Discoveries)
  if (is.null(y.max)) y.max <- pi

  g <- ggplot2::ggplot(DTs.pr, ggplot2::aes(x = TrueDiscoveries, y = FDP, colour = Method, fill = Method, linetype = Method))
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.01), linetype = "dotted")
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.05), linetype = "dotted")
  g <- g + ggplot2::geom_hline(ggplot2::aes(yintercept=yintercept), data.frame(yintercept = 0.10), linetype = "dotted")
  g <- g + ggplot2::geom_ribbon(ggplot2::aes(ymin = lower, ymax = upper), colour = NA, alpha = 0.3)
  if (plot.fdr) g <- g + ggplot2::geom_line(ggplot2::aes(y = y), lty = "dashed")
  g <- g + ggplot2::geom_step(direction = "vh")
  g <- g + ggplot2::scale_x_continuous(expand = c(0, 0))
  g <- g + ggplot2::scale_y_reverse(breaks = sort(c(pi, 0.0, 0.01, 0.05, 0.1, 0.2, 0.5, 1.0)), labels = ylabels(), expand = c(0.001, 0.001))
  g <- g + ggplot2::coord_cartesian(xlim = c(0, max(DTs.pr$TrueDiscoveries)), ylim = c(y.max, 0))
  g <- g + ggplot2::xlab(paste0("True Discoveries [ Sensitivity x ", max(DTs.pr$TrueDiscoveries), " ] from ", max(DTs.pr$Discoveries), " total groups"))
  g <- g + ggplot2::ylab("Solid Line: False Discovery Proportion [ 1 - Precision ], Dashed Line: FDR")
  g <- g + ggplot2::scale_linetype_manual(values = rep("solid", length(levels(DTs.pr$Method))))

  if (is.data.frame(data.fdr)) {
    g + ggplot2::theme(legend.position = "none")
  } else {
    g + ggplot2::theme(legend.position = "top") + ggplot2::guides(lty = ggplot2::guide_legend(nrow = legend.nrow))
  }
}
