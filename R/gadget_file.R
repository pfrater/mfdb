gadget_file <- function (file_name, components = list(), data = NULL, file_type = c()) {
    structure(list(
        filename = file_name,
        components = as.list(components),
        file_type = c(file_type),
        data = data), class = "gadget_file")
}

# Print character representation of the gadget file to stdout
print.gadget_file <- function (x, ...) {
    preamble_str <- function (obj) {
        lines <- as.list(attr(obj, 'preamble'))
        if (length(lines) > 0) paste0("; ", lines, "\n", collapse = "") else ""
    }
    print_component <- function (comp, name) {
        # Print all preambles as comments
        cat(preamble_str(comp))

        if (!is.character(name) || !nzchar(name)) {
            # No name, do nothing
        } else if ("implicit_component" %in% names(x$file_type) && regexpr(x$file_type[['implicit_component']], name) > -1) {
            # Do nothing, the name comes from the key/value line
        } else if ('bare_component' %in% x$file_type) {
            cat(paste0(name,'\n'))
        } else {
            cat(paste0('[', name,']\n'))
        }

        # properties are in key\tvalue1\tvalue2... form
        for (i in seq_len(length(comp))) {
            cat(names(comp)[[i]], "\t", sep = "")
            cat(comp[[i]], sep = "\t")

            if (length(attr(comp[[i]], "comment")) > 0) {
                if (length(comp[[i]]) > 0) cat("\t\t")
                cat("; ", attr(comp[[i]], "comment"), sep = "")
            }
            cat("\n")
        }
    }

    # Print header to top of file
    cat(paste0("; Generated by mfdb ", packageVersion("mfdb"), "\n"))

    for (i in seq_len(length(x$components))) {
        print_component(
            x$components[[i]],
            names(x$components)[[i]])
    }

    if (!is.null(x$data)) {
        cat(preamble_str(x$data))
        cat("; -- data --\n; ")
        write.table(x$data,
                file = "",
                quote = FALSE,
                sep = "\t",
                col.names = TRUE,
                row.names = FALSE,
                fileEncoding = "utf-8")
    }
}

# Return a character representation of the gadget file
as.character.gadget_file <- function (x, ...) {
    paste0(capture.output(print.gadget_file(x)), "\n", collapse = "")
}

# Write gadget file to directory
gadget_dir_write.gadget_file <- function(gd, obj) {
    dir.create(
        dirname(file.path(gd$dir, obj$filename)),
        recursive = TRUE,
        showWarnings = FALSE)

    # For each component, inspect for any stored gadget_files and write these out first
    for (i in seq_len(length(obj$components))) {
        for (j in which("gadget_file" == lapply(obj$components[[i]], class))) {
            gadget_dir_write(gd, obj$components[[i]][[j]])
            obj$components[[i]][[j]] <- obj$components[[i]][[j]]$filename
        }
    }

    fh = file(file.path(gd$dir, obj$filename), "w")
    tryCatch(
        capture.output(print(obj), file = fh),
        finally = close(fh))
}

# Load gadget file into memory
read.gadget_file <- function(file_name, file_type = c(), fileEncoding = "UTF-8") {
    extract <- function (pattern, line) {
        m <- regmatches(line, regexec(pattern, line))[[1]]
        if (length(m) > 1) m[2:length(m)] else c()
    }

    # Open file
    if (file.access(file_name, 4) == -1) {
        stop("File ", file_name, " does not exist")
    }
    file <- file(file_name, "rt", encoding = fileEncoding)
    on.exit(close(file))

    components <- list(list())
    data <- NULL
    comp_name <- NULL
    cur_comp <- list()
    cur_preamble <- list()

    while(TRUE) {
        line <- readLines(file, n = 1)
        # Got to end of file, stop here
        if (length(line) == 0) {
            if(is.null(comp_name)) {
                components[[1]] <- cur_comp
            } else {
                new_comp <- list()
                new_comp[[comp_name]] <- cur_comp
                components <- c(components, new_comp)
            }
            break
        }

        # Ignore version preamble, since this will be replaced on output
        if (length(grep("^; Generated by mfdb", line)) > 0) {
            next
        }

        # Switching to data mode
        if (length(grep("^; -- data --$", line)) > 0) {
            if(is.null(comp_name)) {
                components[[1]] <- cur_comp
            } else {
                new_comp <- list()
                new_comp[[comp_name]] <- cur_comp
                components <- c(components, new_comp)
            }
            header <- strsplit(readLines(file, n = 1), "\\s")[[1]]
            if(length(header) < 2) stop(paste("Not enough parts in data header", header))
            # TODO: error-check header
            data <- read.table(file,
                header=FALSE,
                quote = "",
                sep = "\t",
                col.names = header[2:length(header)],
                fileEncoding = "utf-8")
            attr(data, 'preamble') <- cur_preamble
            break
        }

        # Add any full-line comments as a preamble
        x <- extract("^;\\s*(.*)", line)
        if (length(x) > 0) {
            cur_preamble <- c(cur_preamble, list(x[[1]]))
            next
        }

        # Start of new component
        x <- extract(ifelse(
            "bare_component" %in% file_type,
            "^(\\w+)$",
            "^\\[(\\w+)\\]"), line)
        if (length(x) > 0) {
            if(is.null(comp_name)) {
                components[[1]] <- cur_comp
            } else {
                new_comp <- list()
                new_comp[[comp_name]] <- cur_comp
                components <- c(components, new_comp)
            }
            comp_name <- x[[1]]
            cur_comp <- list()
            next
        }

        # Any other line shoud be a tab seperated list
        match <- extract("([a-zA-Z0-9\\-_]*)\\s+([^;]*);?\\s*(.*)", line)
        line_name <- match[[1]]
        line_values <- if (length(match[[2]]) > 0) unlist(strsplit(sub("\\s+$", "", match[[2]]), "\\t+")) else c()
        line_comment <- match[[3]]

        # This might be an implicit component, if so start a new component but carry on parsing
        if ("implicit_component" %in% names(file_type) && regexpr(file_type[['implicit_component']], line_name) > -1) {
            if(is.null(comp_name)) {
                components[[1]] <- cur_comp
            } else {
                new_comp <- list()
                new_comp[[comp_name]] <- cur_comp
                components <- c(components, new_comp)
            }
            comp_name <- line_name
            cur_comp <- list()
        }

        if (length(line_name) > 0) {
            # Started writing items, so must have got to the end of the preamble
            if (length(cur_preamble) > 0) {
                attr(cur_comp, 'preamble') <- cur_preamble
                cur_preamble <- list()
            }

            # Append to cur_comp
            cur_comp[[length(cur_comp) + 1]] <- structure(
                tryCatch(as.numeric(line_values), warning = function (w) line_values),
                comment = (if (nzchar(line_comment)) line_comment else NULL))
            names(cur_comp)[[length(cur_comp)]] <- line_name
            next
        }
    }
    gadget_file(
        basename(file_name),
        components = components,
        data = data,
        file_type = file_type)
}
