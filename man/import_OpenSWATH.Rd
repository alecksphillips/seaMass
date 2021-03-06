% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/import.R
\name{import_OpenSWATH}
\alias{import_OpenSWATH}
\title{Import OpenSWATH data}
\usage{
import_OpenSWATH(
  file = NULL,
  max.m_score = 0.05,
  use.shared.peptides = FALSE,
  use.decoys = FALSE,
  data = NULL
)
}
\arguments{
\item{max.m_score}{Include only measurements with PyProphet m_score >= than this?}

\item{data}{Advanced: Rather than specifying a \code{file}, you can enter a \link{data.frame} preloaded with
\link[data.table]{fread} default parameters.}

\item{files}{A \code{csv} file to import.}
}
\value{
A \link{data.frame} for input into \link{seaMass_sigma}.
}
\description{
Reads in the output of an OpenSWATH -> PyProphet -> TRIC pipeline.
}
