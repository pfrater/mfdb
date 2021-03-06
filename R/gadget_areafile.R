gadget_areafile <- function (size, temperature, area = attr(size, 'area')) {
    # Replace areas in temp output with matching integers
    temperature$area <- as.factor(temperature$area)
    levels(temperature$area) <- vapply(
        levels(temperature$area),
        function (n) which(names(area) == n),
        0)

    # Round temperature results
    temperature$mean <- round(temperature$mean, 1)

    # Make sure sizes coming in match the aggregation file
    mapped_sizes <- vapply(names(area), function(n) {
        out <- size[size$area == n, 'size']
        if (length(out) == 0) 0 else out
    }, 0)

    structure(list(
        labels = names(area),
        areas = seq_len(length(area)),
        size = mapped_sizes,
        temperature = temperature
        ), class = "gadget_areafile")
}

gadget_dir_write.gadget_areafile <- function(gd, obj) {

    # Write out areafile
    gadget_dir_write(gd, gadget_file(
        "Modelfiles/area",
        components = list(
            structure(
                list(areas = obj$areas, size = obj$size),
                preamble = paste(obj$labels, collapse = "\t")),
            temperature = list()),
        data = obj$temperature,
        file_type = c("bare_component")))

    # Add to mainfile
    gadget_mainfile_update(gd, areafile = "Modelfiles/area")
}
