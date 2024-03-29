#' @include Driver.R
#' @include dplyr_integration.R
NULL

#' Athena Connection Methods
#'
#' Implementations of pure virtual functions defined in the `DBI` package
#' for AthenaConnection objects.
#' @slot ptr a list of connecting objects from the python SDK boto3.
#' @slot info a list of metadata objects
#' @slot quote syntax to quote sql query when creating Athena ddl
#' @name AthenaConnection
#' @inheritParams methods::show
#' @importFrom utils modifyList
NULL

class_cache <- new.env(parent = emptyenv())

AthenaConnection <- function(aws_access_key_id = NULL,
                             aws_secret_access_key = NULL,
                             aws_session_token = NULL,
                             schema_name = NULL,
                             work_group = NULL,
                             poll_interval = NULL,
                             encryption_option = NULL,
                             kms_key = NULL,
                             s3_staging_dir = NULL,
                             region_name = NULL,
                             botocore_session = NULL,
                             profile_name = NULL,
                             aws_expiration = NULL,
                             keyboard_interrupt = NULL,
                             endpoint_override = NULL,
                             ...) {
  kwargs <- list(...)
  sess_kwargs <- c(
    aws_access_key_id = aws_access_key_id,
    aws_secret_access_key = aws_secret_access_key,
    aws_session_token = aws_session_token,
    region_name = region_name,
    botocore_session = botocore_session,
    profile_name = profile_name,
    .boto_param(kwargs, .SESSION_PASSING_ARGS)
  )
  tryCatch(
    sess <- do.call(boto$Session, sess_kwargs),
    error = function(e) py_error(e)
  )
  # stop connection if region_name is not set in backend or hardcoded
  if (is.null(sess$region_name)) {
    stop(
      "AWS `region_name` is required to be set. Please set `region` in .config file, ",
      "`AWS_REGION` in environment variables or `region_name` hard coded in `dbConnect()`.",
      call. = FALSE
    )
  }
  # set up any endpoint url for each aws service: athena, s3, glue
  endpoints <- set_endpoints(endpoint_override)

  ptr_ll <- list(
    Athena = do.call(
      sess$client,
      c(service_name = "athena", modifyList(.boto_param(kwargs, .CLIENT_PASSING_ARGS), list(endpoint_url = endpoints$athena)))
    ),
    S3 = do.call(
      sess$client,
      c(service_name = "s3", modifyList(.boto_param(kwargs, .CLIENT_PASSING_ARGS), list(endpoint_url = endpoints$s3)))
    ),
    glue = do.call(
      sess$client,
      c(service_name = "glue", modifyList(.boto_param(kwargs, .CLIENT_PASSING_ARGS), list(endpoint_url = endpoints$glue)))
    )
  )
  if (is.null(s3_staging_dir) && !is.null(work_group)) {
    tryCatch(
      {
        s3_staging_dir <- reticulate::py_to_r(ptr_ll$Athena$get_work_group(
          WorkGroup = work_group
        )$WorkGroup$Configuration$ResultConfiguration$OutputLocation)
      },
      error = function(e) py_error(e)
    )
  }
  s3_staging_dir <- s3_staging_dir %||% get_aws_env("AWS_ATHENA_S3_STAGING_DIR")

  if (is.null(s3_staging_dir)) {
    stop(
      "Please set `s3_staging_dir` either in parameter `s3_staging_dir`, environmental varaible `AWS_ATHENA_S3_STAGING_DIR`",
      "or when work_group is defined in `create_work_group()`",
      call. = F
    )
  }
  info <- list(
    profile_name = profile_name, s3_staging = s3_staging_dir,
    dbms.name = schema_name, work_group = work_group %||% "primary",
    poll_interval = poll_interval, encryption_option = encryption_option,
    kms_key = kms_key, expiration = aws_expiration,
    timezone = character(),
    keyboard_interrupt = keyboard_interrupt,
    region_name = sess$region_name,
    endpoint_override = endpoints
  )
  res <- new(
    "AthenaConnection",
    ptr = list2env(ptr_ll, parent = emptyenv()),
    info = list2env(info, parent = emptyenv()),
    quote = "`"
  )
}

#' @rdname AthenaConnection
#' @keywords internal
#' @export
setClass(
  "AthenaConnection",
  contains = "DBIConnection",
  slots = list(
    ptr = "environment",
    info = "environment",
    quote = "character"
  )
)

#' @rdname AthenaConnection
#' @export
setMethod(
  "show", "AthenaConnection",
  function(object) {
    cat("<AthenaConnection>\n")
    if (!dbIsValid(object)) {
      cat("  DISCONNECTED\n")
    }
  }
)

#' Disconnect (close) an Athena connection
#'
#' This closes the connection to Athena.
#' @name dbDisconnect
#' @inheritParams DBI::dbDisconnect
#' @return \code{dbDisconnect()} returns \code{TRUE}, invisibly.
#' @seealso \code{\link[DBI]{dbDisconnect}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbDisconnect
#' @export
setMethod(
  "dbDisconnect", "AthenaConnection",
  function(conn, ...) {
    if (!dbIsValid(conn)) {
      warning("Connection already closed.", call. = FALSE)
    } else {
      on_connection_closed(conn)
      rm(list = ls(all.names = TRUE, envir = conn@ptr), envir = conn@ptr)
    }
    invisible(NULL)
  }
)

#' Is this DBMS object still valid?
#'
#' This method tests whether the \code{dbObj} is still valid.
#' @name dbIsValid
#' @inheritParams DBI::dbIsValid
#' @return \code{dbIsValid()} returns logical scalar, \code{TRUE} if the object (\code{dbObj}) is valid, \code{FALSE} otherwise.
#' @seealso \code{\link[DBI]{dbIsValid}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Check is connection is valid
#' dbIsValid(con)
#'
#' # Check is query is valid
#' res <- dbSendQuery(con, "show databases")
#' dbIsValid(res)
#'
#' # Check if query is valid after clearing result
#' dbClearResult(res)
#' dbIsValid(res)
#'
#' # Check if connection if valid after closing connection
#' dbDisconnect(con)
#' dbIsValid(con)
#' }
#' @docType methods
NULL

#' @rdname dbIsValid
#' @export
setMethod(
  "dbIsValid", "AthenaConnection",
  function(dbObj, ...) {
    resource_active(dbObj)
  }
)

#' Execute a query on Athena
#'
#' @description The \code{dbSendQuery()} and \code{dbSendStatement()} method submits a query to Athena but does not wait for query to execute.
#'              \code{\link{dbHasCompleted}} method will need to ran to check if query has been completed or not.
#'              The \code{dbExecute()} method submits a query to Athena and waits for the query to be executed.
#' @name Query
#' @inheritParams DBI::dbSendQuery
#' @param unload boolean input to modify `statement` to align with \href{https://docs.aws.amazon.com/athena/latest/ug/unload.html}{AWS Athena UNLOAD},
#'              default is set to \code{FALSE}.
#' @return Returns \code{AthenaResult} s4 class.
#' @seealso \code{\link[DBI]{dbSendQuery}}, \code{\link[DBI]{dbSendStatement}}, \code{\link[DBI]{dbExecute}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Sending Queries to Athena
#' res1 <- dbSendQuery(con, "show databases")
#' res2 <- dbSendStatement(con, "show databases")
#' res3 <- dbExecute(con, "show databases")
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname Query
#' @export
setMethod(
  "dbSendQuery", c("AthenaConnection", "character"),
  function(conn,
           statement,
           unload = athena_unload(),
           ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(is.logical(unload))
    res <- AthenaResult(
      conn = conn,
      statement = statement,
      s3_staging_dir = conn@info$s3_staging,
      unload = unload
    )
    return(res)
  }
)

#' @rdname Query
#' @export
setMethod(
  "dbSendStatement", c("AthenaConnection", "character"),
  function(conn,
           statement,
           unload = athena_unload(),
           ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(is.logical(unload))
    res <- AthenaResult(
      conn = conn,
      statement = statement,
      s3_staging_dir = conn@info$s3_staging,
      unload = unload
    )
    return(res)
  }
)

#' @rdname Query
#' @export
setMethod(
  "dbExecute", c("AthenaConnection", "character"),
  function(conn,
           statement,
           unload = athena_unload(),
           ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(is.logical(unload))
    res <- AthenaResult(
      conn = conn,
      statement = statement,
      s3_staging_dir = conn@info$s3_staging,
      unload = unload
    )
    poll(res)

    # if query failed stop
    if (res@info$Status == "FAILED") {
      stop(res@info$StateChangeReason, call. = FALSE)
    }

    # cache query metadata if caching is enabled
    if (athena_option_env$cache_size > 0) {
      cache_query(res)
    }

    return(res)
  }
)

#' Determine SQL data type of object
#'
#' Returns a character string that describes the Athena SQL data type for the \code{obj} object.
#' @name dbDataType
#' @inheritParams DBI::dbDataType
#' @return \code{dbDataType} returns the Athena type that correspond to the obj argument as an non-empty character string.
#' @seealso \code{\link[DBI]{dbDataType}}
#' @examples
#' library(RAthena)
#' dbDataType(athena(), 1:5)
#' dbDataType(athena(), 1)
#' dbDataType(athena(), TRUE)
#' dbDataType(athena(), Sys.Date())
#' dbDataType(athena(), Sys.time())
#' dbDataType(athena(), c("x", "abc"))
#' dbDataType(athena(), list(raw(10), raw(20)))
#'
#' vapply(iris, function(x) dbDataType(RAthena::athena(), x),
#'   FUN.VALUE = character(1), USE.NAMES = TRUE
#' )
#'
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Sending Queries to Athena
#' dbDataType(con, iris)
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbDataType
#' @export
setMethod("dbDataType", "AthenaConnection", function(dbObj, obj, ...) {
  dbDataType(athena(), obj, ...)
})

#' @rdname dbDataType
#' @export
setMethod("dbDataType", c("AthenaConnection", "data.frame"), function(dbObj, obj, ...) {
  vapply(obj, AthenaDataType, FUN.VALUE = character(1), USE.NAMES = TRUE)
})

#' Quote Identifiers
#'
#' Call this method to generate string that is suitable for use in a query as a column or table name.
#' @name dbQuote
#' @inheritParams DBI::dbQuoteString
#' @return Returns a character object, for more information please check out: \code{\link[DBI]{dbQuoteString}}, \code{\link[DBI]{dbQuoteIdentifier}}
#' @seealso \code{\link[DBI]{dbQuoteString}}, \code{\link[DBI]{dbQuoteIdentifier}}
#' @docType methods
NULL

# import DBI quote_string method
dbi_quote <- methods::getMethod("dbQuoteString", c("DBIConnection", "character"), asNamespace("DBI"))

detect_date <- function(x, try_format = c("%Y-%m-%d", "%Y/%m/%d")) {
  return(all_dates = all(try(as.Date(x, tryFormats = try_format), silent = T) == x) & all(nchar(x) == 10))
}

detect_date_time <- function(x) {
  timestamp_fmt <- c("%Y-%m-%d %H:%M:%OS", "%Y/%m/%d %H:%M:%OS", "%Y-%m-%d %H:%M", "%Y/%m/%d %H:%M")
  return(all(try(as.POSIXct(x, tryFormats = timestamp_fmt), silent = T) == x))
}

#' @rdname dbQuote
#' @export
setMethod(
  "dbQuoteString", c("AthenaConnection", "character"),
  function(conn, x, ...) {
    if (identical(dbplyr_env$major, 2L)) {
      all_ts <- detect_date_time(x)
      all_dates <- detect_date(x)
      if (all_dates & !is.na(all_dates)) {
        return(paste0("date ", dbi_quote(conn, strftime(x, "%Y-%m-%d"), ...)))
      } else if (all_ts & !is.na(all_ts)) {
        return(paste0("timestamp ", dbi_quote(conn, strftime(x, "%Y-%m-%d %H:%M:%OS3"), ...)))
      }
    }
    return(dbi_quote(conn, x, ...))
  }
)

#' @rdname dbQuote
#' @export
setMethod(
  "dbQuoteString", c("AthenaConnection", "POSIXct"),
  function(conn, x, ...) {
    x <- strftime(x, "%Y-%m-%d %H:%M:%OS3")
    paste0("timestamp ", dbi_quote(conn, x, ...))
  }
)

#' @rdname dbQuote
#' @export
setMethod(
  "dbQuoteString", c("AthenaConnection", "Date"),
  function(conn, x, ...) {
    paste0("date ", dbi_quote(conn, strftime(x, "%Y-%m-%d"), ...))
  }
)

#' @rdname dbQuote
#' @export
setMethod(
  "dbQuoteIdentifier", c("AthenaConnection", "SQL"),
  getMethod("dbQuoteIdentifier", c("DBIConnection", "SQL"), asNamespace("DBI"))
)

#' List Athena Tables
#'
#' Returns the unquoted names of Athena tables accessible through this connection.
#' @name dbListTables
#' @inheritParams DBI::dbListTables
#' @param schema Athena schema, default set to NULL to return all tables from all Athena schemas.
#'               Note: The use of DATABASE and SCHEMA is interchangeable within Athena.
#' @aliases dbListTables
#' @return \code{dbListTables()} returns a character vector with all the tables from Athena.
#' @seealso \code{\link[DBI]{dbListTables}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Return list of tables in Athena
#' dbListTables(con)
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
NULL

#' @rdname dbListTables
#' @export
setMethod(
  "dbListTables", "AthenaConnection",
  function(conn, schema = NULL, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    glue <- conn@ptr$glue
    if (is.null(schema)) {
      schema <- get_databases(glue)
    }
    tryCatch(
      {
        output <- lapply(schema, function(i) get_table_list(glue = glue, schema = i))
      },
      error = function(cond) NULL
    )
    return(
      vapply(
        unlist(output, recursive = FALSE),
        function(y) y$Name,
        FUN.VALUE = character(1)
      )
    )
  }
)

#' List Athena Schema, Tables and Table Types
#'
#' Method to get Athena schema, tables and table types return as a data.frame
#' @name dbGetTables
#' @inheritParams DBI::dbListTables
#' @param schema Athena schema, default set to NULL to return all tables from all Athena schemas.
#'               Note: The use of DATABASE and SCHEMA is interchangeable within Athena.
#' @aliases dbGetTables
#' @return \code{dbGetTables()} returns a data.frame.
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#' library(RAthena)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Return hierarchy of tables in Athena
#' dbGetTables(con)
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
NULL

#' @rdname dbGetTables
#' @export
setGeneric("dbGetTables", function(conn, ...) standardGeneric("dbGetTables"))

#' @rdname dbGetTables
#' @export
setMethod(
  "dbGetTables", "AthenaConnection",
  function(conn, schema = NULL, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    glue <- conn@ptr$glue
    if (is.null(schema)) {
      schema <- get_databases(glue)
    }
    tryCatch(
      {
        output <- lapply(schema, function(i) get_table_list(glue = glue, schema = i))
      },
      error = function(cond) NULL
    )
    output <- rbindlist(unlist(output, recursive = FALSE), use.names = TRUE)
    setnames(output, new = c("Schema", "TableName", "TableType"))
    return(output)
  }
)

#' List Field names of Athena table
#'
#' @name dbListFields
#' @inheritParams DBI::dbListFields
#' @return \code{dbListFields()} returns a character vector with all the fields from an Athena table.
#' @seealso \code{\link[DBI]{dbListFields}}
#' @aliases dbListFields
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Write data.frame to Athena table
#' dbWriteTable(con, "mtcars", mtcars,
#'   partition = c("TIMESTAMP" = format(Sys.Date(), "%Y%m%d")),
#'   s3.location = "s3://mybucket/data/"
#' )
#'
#' # Return list of fields in table
#' dbListFields(con, "mtcars")
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbListFields
#' @export
setMethod(
  "dbListFields", c("AthenaConnection", "character"),
  function(conn, name, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    ll <- db_detect(conn, name)
    retry_api_call(
      output <- py_to_r(conn@ptr$glue$get_table(
        DatabaseName = ll[["dbms.name"]],
        Name = ll[["table"]]
      )$Table)
    )
    col_names <- vapply(output$StorageDescriptor$Columns, function(y) y$Name, FUN.VALUE = character(1))
    partitions <- vapply(output$PartitionKeys, function(y) y$Name, FUN.VALUE = character(1))
    c(col_names, partitions)
  }
)

#' Does Athena table exist?
#'
#' Returns logical scalar if the table exists or not. \code{TRUE} if the table exists, \code{FALSE} otherwise.
#' @name dbExistsTable
#' @inheritParams DBI::dbExistsTable
#' @return \code{dbExistsTable()} returns logical scalar. \code{TRUE} if the table exists, \code{FALSE} otherwise.
#' @seealso \code{\link[DBI]{dbExistsTable}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Write data.frame to Athena table
#' dbWriteTable(con, "mtcars", mtcars,
#'   partition = c("TIMESTAMP" = format(Sys.Date(), "%Y%m%d")),
#'   s3.location = "s3://mybucket/data/"
#' )
#'
#' # Check if table exists from Athena
#' dbExistsTable(con, "mtcars")
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbExistsTable
#' @export
setMethod(
  "dbExistsTable", c("AthenaConnection", "character"),
  function(conn, name, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    ll <- db_detect(conn, name)

    for (i in seq_len(athena_option_env$retry)) {
      resp <- tryCatch(
        {
          py_to_r(conn@ptr$glue$get_table(
            DatabaseName = ll[["dbms.name"]], Name = ll[["table"]]
          ))
        },
        error = function(e) retry_error(e)
      )

      # exponential step back if error and not expected error
      if (inherits(resp, "error") && !grepl(".*table.*not.*found.*", resp, ignore.case = T)) {
        backoff_len <- runif(n = 1, min = 0, max = (2^i - 1))

        info_msg(resp, "Request failed. Retrying in ", round(backoff_len, 1), " seconds...")

        Sys.sleep(backoff_len)
      } else {
        break
      }
    }
    if (inherits(resp, "error") &&
      !grepl(".*table.*not.*found.*", resp, ignore.case = T)) {
      stop(resp)
    }
    return(!grepl(".*table.*not.*found.*", resp[1], ignore.case = T))
  }
)

#' Remove table from Athena
#'
#' Removes Athena table but does not remove the data from Amazon S3 bucket.
#' @name dbRemoveTable
#' @return \code{dbRemoveTable()} returns \code{TRUE}, invisibly.
#' @inheritParams DBI::dbRemoveTable
#' @param delete_data Deletes S3 files linking to AWS Athena table
#' @param confirm Allows for S3 files to be deleted without the prompt check. It is recommend to leave this set to \code{FALSE}
#'                   to avoid deleting other S3 files when the table's definition points to the root of S3 bucket.
#' @seealso \code{\link[DBI]{dbRemoveTable}}
#' @note If you are having difficulty removing AWS S3 files please check if the AWS S3 location following AWS best practises: \href{https://docs.aws.amazon.com/athena/latest/ug/tables-location-format.html}{Table Location in Amazon S3}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Write data.frame to Athena table
#' dbWriteTable(con, "mtcars", mtcars,
#'   partition = c("TIMESTAMP" = format(Sys.Date(), "%Y%m%d")),
#'   s3.location = "s3://mybucket/data/"
#' )
#'
#' # Remove Table from Athena
#' dbRemoveTable(con, "mtcars")
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbRemoveTable
#' @export
setMethod(
  "dbRemoveTable", c("AthenaConnection", "character"),
  function(conn, name, delete_data = TRUE, confirm = FALSE, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(
      is.logical(delete_data),
      is.logical(confirm)
    )
    ll <- db_detect(conn, name)

    tryCatch(TableType <- conn@ptr$glue$get_table(DatabaseName = ll[["dbms.name"]], Name = ll[["table"]])[["Table"]][["TableType"]],
      error = function(e) py_error(e)
    )

    if (delete_data && TableType == "EXTERNAL_TABLE") {
      tryCatch(
        s3_path <- split_s3_uri(
          conn@ptr$glue$get_table(DatabaseName = ll[["dbms.name"]], Name = ll[["table"]])[["Table"]][["StorageDescriptor"]][["Location"]]
        ),
        error = function(e) py_error(e)
      )
      # Detect if key ends with "/" or if it has ".": https://github.com/DyfanJones/noctua/issues/125
      if (!grepl("\\.|/$", s3_path$key)) {
        s3_path[["key"]] <- sprintf("%s/", s3_path[["key"]])
      }
      all_keys <- list()
      # Get all s3 objects linked to table
      i <- 1
      kwargs <- list(Bucket = s3_path[["bucket"]], Prefix = s3_path[["key"]])
      token <- ""
      while (!is.null(token)) {
        kwargs[["ContinuationToken"]] <- (if (!nzchar(token)) NULL else token)
        objects <- py_to_r(do.call(conn@ptr$S3$list_objects_v2, kwargs))
        all_keys[[i]] <- lapply(objects$Contents, function(x) list(Key = x$Key))
        token <- objects$NextContinuationToken
        i <- i + 1
      }
      info_msg(
        "The S3 objects in prefix will be deleted:\n",
        paste0("s3://", s3_path$bucket, "/", s3_path$key)
      )
      if (!confirm) {
        confirm <- readline(prompt = "Delete files (y/n)?: ")
        if (tolower(confirm) != "y") {
          info_msg("Table deletion aborted.")
          return(NULL)
        }
      }

      all_keys <- unlist(all_keys, recursive = FALSE, use.names = FALSE)

      # Only remove if files are found
      if (length(all_keys) > 0) {
        # Delete S3 files in batch size 1000
        key_parts <- split_vec(all_keys, 1000)
        for (i in seq_along(key_parts)) {
          conn@ptr$S3$delete_objects(Bucket = s3_path$bucket, Delete = list(Objects = key_parts[[i]]))
        }
      } else {
        warning(sprintf(
          'Failed to remove AWS S3 files from: "s3://%s/%s". Please check if AWS S3 files exist.',
          s3_path$bucket, s3_path$key
        ), call. = F)
      }
    }

    # use glue to remove table from glue catalog
    tryCatch(conn@ptr$glue$delete_table(DatabaseName = ll[["dbms.name"]], Name = ll[["table"]]),
      error = function(e) py_error(e)
    )

    if (!delete_data) info_msg("Only Athena table has been removed.")
    on_connection_updated(conn, ll[["table"]])
    invisible(TRUE)
  }
)

#' @title Send query, retrieve results and then clear result set
#'
#' @note If the user does not have permission to remove AWS S3 resource from AWS Athena output location, then an AWS warning will be returned.
#'       For example \code{AccessDenied (HTTP 403). Access Denied}.
#'       It is better use query caching or optionally prevent clear AWS S3 resource using \code{\link{RAthena_options}}
#'       so that the warning doesn't repeatedly show.
#' @name dbGetQuery
#' @inheritParams DBI::dbGetQuery
#' @param statistics If set to \code{TRUE} will print out AWS Athena statistics of query.
#' @param unload boolean input to modify `statement` to align with \href{https://docs.aws.amazon.com/athena/latest/ug/unload.html}{AWS Athena UNLOAD},
#'              default is set to \code{FALSE}.
#' @return \code{dbGetQuery()} returns a dataframe.
#' @seealso \code{\link[DBI]{dbGetQuery}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Sending Queries to Athena
#' dbGetQuery(con, "show databases")
#'
#' # Disconnect conenction
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbGetQuery
#' @export
setMethod(
  "dbGetQuery", c("AthenaConnection", "character"),
  function(conn,
           statement,
           statistics = FALSE,
           unload = athena_unload(),
           ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(is.logical(statistics), is.logical(unload))

    # dbplyr v2 support: dbplyr class ident
    if (!inherits(statement, "ident")) {
      rs <- dbSendQuery(conn, statement = statement, unload = unload)
      if (statistics) print(dbStatistics(rs))
      out <- dbFetch(res = rs, n = -1, ...)
      dbClearResult(rs)
    } else {
      # Create an empty table using AWS GLUE to retrieve column names
      field_names <- athena_query_fields_ident(conn, statement)
      empty_shell <- rep(list(character()), length(field_names))
      names(empty_shell) <- field_names

      if (inherits(athena_option_env[["file_parser"]], "athena_data.table")) {
        out <- as.data.table(empty_shell)
      } else {
        as_tibble <- pkg_method("as_tibble", "tibble")
        out <- as_tibble(empty_shell)
      }
    }
    return(out)
  }
)

#' Get DBMS metadata
#'
#' @inheritParams DBI::dbGetInfo
#' @name dbGetInfo
#' @return a named list
#' @seealso \code{\link[DBI]{dbGetInfo}}
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # Returns metadata from connnection object
#' metadata <- dbGetInfo(con)
#'
#' # Return metadata from Athena query object
#' res <- dbSendQuery(con, "show databases")
#' dbGetInfo(res)
#'
#' # Clear result
#' dbClearResult(res)
#'
#' # disconnect from Athena
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbGetInfo
#' @export
setMethod(
  "dbGetInfo", "AthenaConnection",
  function(dbObj, ...) {
    con_error_msg(dbObj, msg = "Connection already closed.")
    info <- as.list(dbObj@info)
    Boto <- as.character(boto_verison())
    rathena <- as.character(packageVersion("RAthena"))
    info <- c(info, boto3 = Boto, RAthena = rathena)
    return(info)
  }
)

#' Athena table partitions
#'
#' This method returns all partitions from Athena table.
#' @inheritParams DBI::dbExistsTable
#' @param .format re-formats AWS Athena partitions format. So that each column represents a partition
#'         from the AWS Athena table. Default set to \code{FALSE} to prevent breaking previous package behaviour.
#' @return data.frame that returns all partitions in table, if no partitions in Athena table then
#'         function will return error from Athena.
#' @name dbGetPartition
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # write iris table to Athena
#' dbWriteTable(con, "iris",
#'   iris,
#'   partition = c("timestamp" = format(Sys.Date(), "%Y%m%d")),
#'   s3.location = "s3://path/to/store/athena/table/"
#' )
#'
#' # return table partitions
#' RAthena::dbGetPartition(con, "iris")
#'
#' # disconnect from Athena
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbGetPartition
#' @export
setGeneric("dbGetPartition",
  def = function(conn, name, ..., .format = FALSE) standardGeneric("dbGetPartition"),
  valueClass = "data.frame"
)

#' @rdname dbGetPartition
#' @export
setMethod(
  "dbGetPartition", "AthenaConnection",
  function(conn, name, ..., .format = FALSE) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(is.logical(.format))
    ll <- db_detect(conn, name)
    dt <- dbGetQuery(conn, paste0("SHOW PARTITIONS ", ll[["dbms.name"]], ".", ll[["table"]]))

    if (.format) {
      # ensure returning format is data.table
      dt <- as.data.table(dt)
      dt <- dt[, tstrsplit(dt[[1]], split = "/")]
      partitions <- sapply(names(dt), function(x) strsplit(dt[[x]][1], split = "=")[[1]][1])
      for (col in names(dt)) set(dt, j = col, value = tstrsplit(dt[[col]], split = "=")[2])
      setnames(dt, old = names(dt), new = partitions)

      # convert data.table to tibble if using vroom as backend
      if (inherits(athena_option_env$file_parser, "athena_vroom")) {
        as_tibble <- pkg_method("as_tibble", "tibble")
        dt <- as_tibble(dt)
      }
    }
    return(dt)
  }
)

#' Show Athena table's DDL
#'
#' @description Executes a statement to return the data description language (DDL) of the Athena table.
#' @inheritParams DBI::dbExistsTable
#' @name dbShow
#' @return \code{dbShow()} returns \code{\link[DBI]{SQL}} characters of the Athena table DDL.
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(RAthena::athena())
#'
#' # write iris table to Athena
#' dbWriteTable(con, "iris",
#'   iris,
#'   partition = c("timestamp" = format(Sys.Date(), "%Y%m%d")),
#'   s3.location = "s3://path/to/store/athena/table/"
#' )
#'
#' # return table ddl
#' RAthena::dbShow(con, "iris")
#'
#' # disconnect from Athena
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbShow
#' @export
setGeneric(
  "dbShow",
  def = function(conn, name, ...) standardGeneric("dbShow"),
  valueClass = "character"
)

#' @rdname dbShow
#' @export
setMethod(
  "dbShow", "AthenaConnection",
  function(conn, name, ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    ll <- db_detect(conn, name)
    SQL(paste0(dbGetQuery(conn, paste0("SHOW CREATE TABLE ", ll[["dbms.name"]], ".", ll[["table"]]), unload = FALSE)[[1]], collapse = "\n"))
  }
)

#' Simple wrapper to convert Athena backend file types
#'
#' @description Utilises AWS Athena to convert AWS S3 backend file types. It also also to create more efficient file types i.e. "parquet" and "orc" from SQL queries.
#' @param conn An \code{\linkS4class{AthenaConnection}} object, produced by [DBI::dbConnect()]
#' @param obj Athena table or \code{SQL} DML query to be converted. For \code{SQL}, the query need to be wrapped with \code{DBI::SQL()} and
#'            follow AWS Athena DML format \href{https://docs.aws.amazon.com/athena/latest/ug/select.html}{link}
#' @param name Name of destination table
#' @param partition Partition Athena table
#' @param s3.location location to store output file, must be in s3 uri format for example ("s3://mybucket/data/").
#' @param file.type File type for \code{name}, currently support ["NULL","csv", "tsv", "parquet", "json", "orc"].
#'                  \code{"NULL"} will let Athena set the file type for you.
#' @param compress Compress \code{name}, currently can only compress ["parquet", "orc"] (\href{https://docs.aws.amazon.com/athena/latest/ug/create-table-as.html}{AWS Athena CTAS})
#' @param data If \code{name} should be created with data or not.
#' @param ... Extra parameters, currently not used
#' @name dbConvertTable
#' @return \code{dbConvertTable()} returns \code{TRUE} but invisible.
#' @examples
#' \dontrun{
#' # Note:
#' # - Require AWS Account to run below example.
#' # - Different connection methods can be used please see `RAthena::dbConnect` documnentation
#'
#' library(DBI)
#' library(RAthena)
#'
#' # Demo connection to Athena using profile name
#' con <- dbConnect(athena())
#'
#' # write iris table to Athena in defualt delimited format
#' dbWriteTable(con, "iris", iris)
#'
#' # convert delimited table to parquet
#' dbConvertTable(con,
#'   obj = "iris",
#'   name = "iris_parquet",
#'   file.type = "parquet"
#' )
#'
#' # Create partitioned table from non-partitioned
#' # iris table using SQL DML query
#' dbConvertTable(con,
#'   obj = SQL("select
#'                             iris.*,
#'                             date_format(current_date, '%Y%m%d') as time_stamp
#'                           from iris"),
#'   name = "iris_orc_partitioned",
#'   file.type = "orc",
#'   partition = "time_stamp"
#' )
#'
#' # disconnect from Athena
#' dbDisconnect(con)
#' }
#' @docType methods
NULL

#' @rdname dbConvertTable
#' @export
setGeneric(
  "dbConvertTable",
  def = function(conn, obj, name, ...) standardGeneric("dbConvertTable")
)

#' @rdname dbConvertTable
#' @export
setMethod(
  "dbConvertTable", "AthenaConnection",
  function(conn,
           obj,
           name,
           partition = NULL,
           s3.location = NULL,
           file.type = c("NULL", "csv", "tsv", "parquet", "json", "orc"),
           compress = TRUE,
           data = TRUE,
           ...) {
    con_error_msg(conn, msg = "Connection already closed.")
    stopifnot(
      is.character(obj),
      is.character(name),
      is.null(partition) || is.character(partition),
      is.null(s3.location) || is.s3_uri(s3.location),
      is.logical(compress),
      is.logical(data)
    )
    file.type <- match.arg(file.type)

    with_data <- if (data) " " else " NO "

    ins <- if (inherits(obj, "SQL")) {
      obj
    } else {
      paste0("SELECT * FROM ", paste0('"', unlist(strsplit(obj, "\\.")), '"', collapse = "."))
    }

    tt_sql <- paste0(
      "CREATE TABLE ", paste0('"', unlist(strsplit(name, "\\.")), '"', collapse = "."),
      " ", ctas_sql_with(partition, s3.location, file.type, compress), "AS ",
      ins, "\nWITH", with_data, "DATA", ";"
    )
    res <- dbExecute(conn, tt_sql, unload = FALSE)
    dbClearResult(res)
    return(invisible(TRUE))
  }
)
