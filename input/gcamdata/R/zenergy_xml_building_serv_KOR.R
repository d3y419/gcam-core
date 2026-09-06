# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_xml_building_serv_KOR
#'
#' Construct XML data structure for \code{building_serv_KOR.xml}.
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs, a vector of output
#' names, or (if \code{command} is "MAKE") all the generated outputs:
#' \code{building_serv_KOR.xml}.
#' @details Writes South Korea's detailed non-thermal building services (batch 1) to a
#' standalone scenario component, loaded after \code{building_det.xml} so it overlays only
#' South Korea. Both the supply side (new supplysectors, subsectors, technologies) and the
#' consumer side (building service inputs and their demand-function parameters) are written
#' here, since these services do not exist for South Korea in core.
#' @author HCM 2026
module_energy_xml_building_serv_KOR <- function(command, ...) {
  if(command == driver.DECLARE_INPUTS) {
    return(c("K1442.Supplysector_bld_KOR",
             "K1442.FinalEnergyKeyword_bld_KOR",
             "K1442.SubsectorLogit_bld_KOR",
             "K1442.SubsectorShrwtFllt_bld_KOR",
             "K1442.FuelPrefElast_bld_KOR",
             "K1442.StubTech_bld_KOR",
             "K1442.StubTechEff_bld_KOR",
             "K1442.StubTechIntGainOutputRatio_KOR",
             "K1442.StubTechCalInput_bld_KOR",
             "K1442.GenericBaseService_KOR",
             "K1442.GenericServiceSatiation_KOR",
             "K1442.GenericServiceImpedance_KOR",
             "K1442.GenericServiceCoef_KOR",
             "K1442.DeleteStubTech_bld_KOR",
             "K1442.DeleteSubsector_bld_KOR",
             "K1442.GenericServicePrice_KOR",
             "K1442.GenericBaseDens_KOR",
             "K1442.GenericServiceAdder_KOR"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c(XML = "building_serv_KOR.xml"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    K1442.Supplysector_bld_KOR <- get_data(all_data, "K1442.Supplysector_bld_KOR")
    K1442.FinalEnergyKeyword_bld_KOR <- get_data(all_data, "K1442.FinalEnergyKeyword_bld_KOR")
    K1442.SubsectorLogit_bld_KOR <- get_data(all_data, "K1442.SubsectorLogit_bld_KOR")
    K1442.SubsectorShrwtFllt_bld_KOR <- get_data(all_data, "K1442.SubsectorShrwtFllt_bld_KOR")
    K1442.FuelPrefElast_bld_KOR <- get_data(all_data, "K1442.FuelPrefElast_bld_KOR")
    K1442.StubTech_bld_KOR <- get_data(all_data, "K1442.StubTech_bld_KOR")
    K1442.StubTechEff_bld_KOR <- get_data(all_data, "K1442.StubTechEff_bld_KOR")
    K1442.StubTechIntGainOutputRatio_KOR <- get_data(all_data, "K1442.StubTechIntGainOutputRatio_KOR")
    K1442.StubTechCalInput_bld_KOR <- get_data(all_data, "K1442.StubTechCalInput_bld_KOR")
    K1442.GenericBaseService_KOR <- get_data(all_data, "K1442.GenericBaseService_KOR")
    K1442.GenericServiceSatiation_KOR <- get_data(all_data, "K1442.GenericServiceSatiation_KOR")
    K1442.GenericServiceImpedance_KOR <- get_data(all_data, "K1442.GenericServiceImpedance_KOR")
    K1442.GenericServiceCoef_KOR <- get_data(all_data, "K1442.GenericServiceCoef_KOR")
    K1442.DeleteStubTech_bld_KOR <- get_data(all_data, "K1442.DeleteStubTech_bld_KOR")
    K1442.DeleteSubsector_bld_KOR <- get_data(all_data, "K1442.DeleteSubsector_bld_KOR")
    K1442.GenericServicePrice_KOR <- get_data(all_data, "K1442.GenericServicePrice_KOR")
    K1442.GenericBaseDens_KOR <- get_data(all_data, "K1442.GenericBaseDens_KOR")
    K1442.GenericServiceAdder_KOR <- get_data(all_data, "K1442.GenericServiceAdder_KOR")

    create_xml("building_serv_KOR.xml") %>%
      add_xml_data(K1442.DeleteSubsector_bld_KOR, "DeleteSubsector") %>%
      add_xml_data(K1442.DeleteStubTech_bld_KOR, "DeleteStubTech") %>%
      add_logit_tables_xml(K1442.Supplysector_bld_KOR, "Supplysector") %>%
      add_xml_data(K1442.FinalEnergyKeyword_bld_KOR, "FinalEnergyKeyword") %>%
      add_logit_tables_xml(K1442.SubsectorLogit_bld_KOR, "SubsectorLogit") %>%
      add_xml_data(K1442.SubsectorShrwtFllt_bld_KOR, "SubsectorShrwtFllt") %>%
      add_xml_data(K1442.FuelPrefElast_bld_KOR, "FuelPrefElast") %>%
      add_xml_data(K1442.StubTech_bld_KOR, "StubTech") %>%
      add_xml_data(K1442.StubTechEff_bld_KOR, "StubTechEff") %>%
      add_xml_data(K1442.StubTechIntGainOutputRatio_KOR, "StubTechIntGainOutputRatio") %>%
      add_xml_data(K1442.StubTechCalInput_bld_KOR, "StubTechCalInput") %>%
      add_xml_data(K1442.GenericBaseService_KOR, "GenericBaseService") %>%
      add_xml_data(K1442.GenericServiceSatiation_KOR, "GenericServiceSatiation") %>%
      add_xml_data(K1442.GenericServiceImpedance_KOR, "GenericServiceImpedance") %>%
      add_xml_data(K1442.GenericServiceCoef_KOR, "GenericServiceCoef") %>%
      add_xml_data(K1442.GenericServicePrice_KOR, "GenericServicePrice") %>%
      add_xml_data(K1442.GenericBaseDens_KOR, "GenericBaseDens") %>%
      add_xml_data(K1442.GenericServiceAdder_KOR, "GenericServiceAdder") %>%
      add_precursors("K1442.Supplysector_bld_KOR", "K1442.FinalEnergyKeyword_bld_KOR",
                     "K1442.SubsectorLogit_bld_KOR", "K1442.SubsectorShrwtFllt_bld_KOR",
                     "K1442.FuelPrefElast_bld_KOR", "K1442.StubTech_bld_KOR",
                     "K1442.StubTechEff_bld_KOR", "K1442.StubTechIntGainOutputRatio_KOR",
                     "K1442.StubTechCalInput_bld_KOR", "K1442.GenericBaseService_KOR",
                     "K1442.GenericServiceSatiation_KOR", "K1442.GenericServiceImpedance_KOR",
                     "K1442.GenericServiceCoef_KOR", "K1442.DeleteStubTech_bld_KOR", "K1442.DeleteSubsector_bld_KOR",
                     "K1442.GenericServicePrice_KOR", "K1442.GenericBaseDens_KOR", "K1442.GenericServiceAdder_KOR") ->
      building_serv_KOR.xml

    return_data(building_serv_KOR.xml)
  } else {
    stop("Unknown command")
  }
}
