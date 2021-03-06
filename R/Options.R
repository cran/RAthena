# Set environmental variable 
athena_option_env <- new.env(parent=emptyenv())
athena_option_env$file_parser <- "file_method"
athena_option_env$cache_size <- 0
class(athena_option_env$file_parser) <- "athena_data.table"

cache_dt = data.table("QueryId" = character(), "Query" = character(), "State"= character(),
                      "StatementType"= character(),"WorkGroup" = character())
athena_option_env$cache_dt <-  cache_dt
athena_option_env$retry <- 5
athena_option_env$retry_quiet <- FALSE
athena_option_env$bigint <- "integer64"
athena_option_env$binary <- "raw"
athena_option_env$json <- "auto"
athena_option_env$rstudio_conn_tab <- TRUE

# ==========================================================================
# helper function to handle big integers
big_int <- function(bigint){
  fp <- class(athena_option_env$file_parser)
  
  if(fp == "athena_data.table")
    return(switch(bigint,
                  "I" = bit64_check("integer64"),
                  "i" = "integer",
                  "d" = "double",
                  "c" = "character",
                  "numeric" = "double",
                  bigint)
    )
  if(fp == "athena_vroom")
    return(switch(bigint,
                  "integer64" = bit64_check("I"), 
                  "integer" = "i",
                  "numeric" = "d",
                  "double" = "d",
                  "character" = "c",
                  bigint)
    )
  }

bit64_check <- function(value){
  if(!requireNamespace("bit64", quietly = TRUE))
    stop('integer64 is supported by `bit64`. Please install `bit64` package and try again', call. = F)
  return(value)
}

# ==========================================================================
# Setting file parser method

#' A method to configure RAthena backend options.
#'
#' \code{RAthena_options()} provides a method to change the backend. This includes changing the file parser,
#' whether \code{RAthena} should cache query ids locally and number of retries on a failed api call.
#' @param file_parser Method to read and write tables to Athena, currently defaults to \code{data.table}. The file_parser also
#'                    determines the data format returned for example \code{data.table} will return \code{data.table} and \code{vroom} will return \code{tibble}.
#' @param bigint The R type that 64-bit integer types should be mapped to. Default \code{NULL} won't make any changes that \code{dbConnect} has set.
#'    Inbuilt bigint conversion types ["integer64", "integer", "numeric", "character"].
#' @param binary The R type that [binary/varbinary] types should be mapped to. Default \code{NULL} won't make any changes that \code{dbConnect} has set.
#'    Inbuilt binary conversion types ["raw", "character"].
#' @param json Attempt to converts AWS Athena data types [arrays, json] using \code{jsonlite:parse_json}. 
#'   Default \code{NULL} won't make any changes that \code{dbConnect} has set. Inbuilt json conversion types ["auto", "character"].
#'   Custom Json parsers can be provide by using a function with data frame parameter.
#' @param cache_size Number of queries to be cached. Currently only support caching up to 100 distinct queries.
#' @param clear_cache Clears all previous cached query metadata
#' @param retry Maximum number of requests to attempt.
#' @param retry_quiet If \code{FALSE}, will print a message from retry displaying how long until the next request.
#' @return \code{RAthena_options()} returns \code{NULL}, invisibly.
#' @examples
#' library(RAthena)
#' 
#' # change file parser from default data.table to vroom
#' RAthena_options("vroom")
#' 
#' # cache queries locally
#' RAthena_options(cache_size = 5)
#' @export
RAthena_options <- function(file_parser = c("data.table", "vroom"),
                            bigint = NULL,
                            binary = NULL,
                            json = NULL,
                            cache_size = 0,
                            clear_cache = FALSE, 
                            retry = 5,
                            retry_quiet = FALSE) {
  file_parser = match.arg(file_parser)
  stopifnot(is.logical(clear_cache),
            is.numeric(retry),
            is.numeric(cache_size),
            is.logical(retry_quiet))
  
  if(cache_size < 0 | cache_size > 100) stop("RAthena currently only supports up to 100 queries being cached", call. = F)
  if(retry < 0) stop("Number of retries is required to be greater than 0.")
  
  if (!requireNamespace(file_parser, quietly = TRUE))
    stop('Please install ', file_parser, ' package and try again', call. = F)
  
  switch(file_parser,
         "vroom" = if(packageVersion(file_parser) < '1.2.0')  
                       stop("Please update `vroom` to  `1.2.0` or later", call. = FALSE))
  
  # only change bigint when not null
  if(!is.null(bigint)){
    athena_option_env$bigint <- big_int(match.arg(bigint, c("integer64", "integer", "numeric", "character")))
  }
  
  # only change binary when not null
  if(!is.null(binary))
    athena_option_env$binary <- match.arg(binary, c("raw", "character"))
  
  # only change json when not null  
  if(!is.null(json)){
    if(is.character(json)) {
      athena_option_env$json <- match.arg(json, c("auto", "character"))
    } else if(is.function(json)) {
      athena_option_env$json <- json
    } else{
      stop('Unknown json parser. Please use defaults ["auto", "character"] or a custom function.',
           call. = F)
    }
  }
  
  class(athena_option_env$file_parser) <- paste("athena", file_parser, sep = "_")
  athena_option_env$bigint <- big_int(athena_option_env$bigint)
  
  athena_option_env$cache_size <- as.integer(cache_size)
  athena_option_env$retry <- as.integer(retry)
  athena_option_env$retry_quiet <- retry_quiet
  
  if(clear_cache) athena_option_env$cache_dt <- athena_option_env$cache_dt[0]
  
  invisible(NULL)
}
