% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Connection.R
\docType{methods}
\name{dbQuote}
\alias{dbQuote}
\alias{dbQuoteString,AthenaConnection,character-method}
\alias{dbQuoteString,AthenaConnection,POSIXct-method}
\alias{dbQuoteString,AthenaConnection,Date-method}
\alias{dbQuoteIdentifier,AthenaConnection,SQL-method}
\title{Quote Identifiers}
\usage{
\S4method{dbQuoteString}{AthenaConnection,character}(conn, x, ...)

\S4method{dbQuoteString}{AthenaConnection,POSIXct}(conn, x, ...)

\S4method{dbQuoteString}{AthenaConnection,Date}(conn, x, ...)

\S4method{dbQuoteIdentifier}{AthenaConnection,SQL}(conn, x, ...)
}
\arguments{
\item{conn}{A \linkS4class{DBIConnection} object, as returned by
\code{\link[DBI:dbConnect]{dbConnect()}}.}

\item{x}{A character vector to quote as string.}

\item{...}{Other arguments passed on to methods.}
}
\value{
Returns a character object, for more information please check out: \code{\link[DBI]{dbQuoteString}}, \code{\link[DBI]{dbQuoteIdentifier}}
}
\description{
Call this method to generate string that is suitable for use in a query as a column or table name.
}
\seealso{
\code{\link[DBI]{dbQuoteString}}, \code{\link[DBI]{dbQuoteIdentifier}}
}
