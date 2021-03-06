% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/import.R
\name{import_DIANN}
\alias{import_DIANN}
\title{Import DIA-NN data}
\usage{
import_DIANN(file = NULL, use.shared.peptides = FALSE, data = NULL)
}
\arguments{
\item{data}{Advanced: Rather than specifying \code{file}, you can enter a \link{data.frame} preloaded with
\link[data.table]{fread} default parameters.}

\item{proteinGroups.file}{Location of the \code{proteinGroups.txt} file.}

\item{evidence.file}{Location of the \code{evidence.txt} file.}

\item{shared}{Include shared peptides?}
}
\value{
A \link{data.frame} for input into \link{bayesprot}.
}
\description{
Reads in DIA-NN \code{report.tsv} for processing.
}
