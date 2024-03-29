% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Driver.R, R/Connection.R
\docType{methods}
\name{dbDataType,AthenaDriver,ANY-method}
\alias{dbDataType,AthenaDriver,ANY-method}
\alias{dbDataType,AthenaDriver,list-method}
\alias{dbDataType}
\alias{dbDataType,AthenaConnection,ANY-method}
\alias{dbDataType,AthenaConnection,data.frame-method}
\title{Determine SQL data type of object}
\usage{
\S4method{dbDataType}{AthenaDriver,ANY}(dbObj, obj, ...)

\S4method{dbDataType}{AthenaDriver,list}(dbObj, obj, ...)

\S4method{dbDataType}{AthenaConnection,ANY}(dbObj, obj, ...)

\S4method{dbDataType}{AthenaConnection,data.frame}(dbObj, obj, ...)
}
\arguments{
\item{dbObj}{A object inheriting from \linkS4class{DBIDriver}
or \linkS4class{DBIConnection}}

\item{obj}{An R object whose SQL type we want to determine.}

\item{...}{Other arguments passed on to methods.}
}
\value{
\code{dbDataType} returns the Athena type that correspond to the obj argument as an non-empty character string.
}
\description{
Returns a character string that describes the Athena SQL data type for the \code{obj} object.
}
\examples{
library(RAthena)
dbDataType(athena(), 1:5)
dbDataType(athena(), 1)
dbDataType(athena(), TRUE)
dbDataType(athena(), Sys.Date())
dbDataType(athena(), Sys.time())
dbDataType(athena(), c("x", "abc"))
dbDataType(athena(), list(raw(10), raw(20)))

vapply(iris, function(x) dbDataType(RAthena::athena(), x),
  FUN.VALUE = character(1), USE.NAMES = TRUE
)

\dontrun{
# Note:
# - Require AWS Account to run below example.
# - Different connection methods can be used please see `RAthena::dbConnect` documnentation

library(DBI)

# Demo connection to Athena using profile name
con <- dbConnect(RAthena::athena())

# Sending Queries to Athena
dbDataType(con, iris)

# Disconnect conenction
dbDisconnect(con)
}
}
\seealso{
\code{\link[DBI]{dbDataType}}
}
