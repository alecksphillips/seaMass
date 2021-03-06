% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/delta_plot.R
\name{plot_volcano}
\alias{plot_volcano}
\title{Volcano plot}
\usage{
plot_volcano(
  data.fdr,
  contours = NULL,
  error.bars = TRUE,
  labels = 25,
  stdev.col = "PosteriorSD",
  x.col = "PosteriorMean",
  y.col = "qvalue"
)
}
\arguments{
\item{data.fdr}{.}
}
\value{
A ggplot2 object.
}
\description{
Volcano plot
}
