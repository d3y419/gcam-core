# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_xml_building_KOR
#'
#' Construct XML data structure for \code{building_det_KOR.xml}.
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs,
#' a vector of output names, or (if \code{command} is "MAKE") all
#' the generated outputs: \code{building_det_KOR.xml}.
#' @details Writes South Korea's efficiency-tier building technology calibration
#' (\code{K1441.StubTechCalInput_bld_KOR}) to a standalone XML scenario component,
#' loaded after \code{building_det.xml} so it overlays South Korea's calibration only.
#' @author HCM 2026
module_energy_xml_building_KOR <- function(command, ...) {
  if(command == driver.DECLARE_INPUTS) {
    return(c("K1441.StubTechCalInput_bld_KOR", "K1441.StubTechShrwt_bld_KOR", "K1441.StubTechSCurve_bld_KOR",
             "K1441.StubTechEff_bld_KOR", "K1441.StubTechInterp_bld_KOR"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c(XML = "building_det_KOR.xml"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    K1441.StubTechCalInput_bld_KOR <- get_data(all_data, "K1441.StubTechCalInput_bld_KOR")
    K1441.StubTechShrwt_bld_KOR <- get_data(all_data, "K1441.StubTechShrwt_bld_KOR")
    K1441.StubTechSCurve_bld_KOR <- get_data(all_data, "K1441.StubTechSCurve_bld_KOR")
    K1441.StubTechEff_bld_KOR <- get_data(all_data, "K1441.StubTechEff_bld_KOR")
    K1441.StubTechInterp_bld_KOR <- get_data(all_data, "K1441.StubTechInterp_bld_KOR")

    create_xml("building_det_KOR.xml") %>%
      add_xml_data(K1441.StubTechCalInput_bld_KOR, "StubTechCalInput") %>%
      add_xml_data(K1441.StubTechShrwt_bld_KOR, "StubTechShrwt") %>%
      add_xml_data(K1441.StubTechSCurve_bld_KOR, "StubTechSCurve") %>%
      add_xml_data(K1441.StubTechEff_bld_KOR, "StubTechEff") %>%
      add_xml_data(K1441.StubTechInterp_bld_KOR, "StubTechInterp") %>%
      add_precursors("K1441.StubTechCalInput_bld_KOR", "K1441.StubTechShrwt_bld_KOR", "K1441.StubTechSCurve_bld_KOR",
                     "K1441.StubTechEff_bld_KOR", "K1441.StubTechInterp_bld_KOR") ->
      building_det_KOR.xml

    return_data(building_det_KOR.xml)
  } else {
    stop("Unknown command")
  }
}
