# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_K1440.building_det_serv_KOR
#'
#' South Korea's heating electricity base service, recomputed with the GCAM-USA efficiency tiers
#' that \code{module_energy_K1441.building_det_en_KOR} gives South Korea.
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs,
#' a vector of output names, or (if \code{command} is "MAKE") all
#' the generated outputs: \code{K1440.base_service_EJ_serv_fuel_KOR}.
#' @details K1441 splits South Korea's resid and comm heating electricity into "electric furnace" and
#' "electric heat pump", with USA's base-year split and USA's efficiencies. Core L144 computes the base
#' service with South Korea's single electricity efficiency (about 0.91), so the tiers' calibrated output
#' would exceed the base service and GCAM would cut the other heating fuels to match. This chunk gives
#' the base service the tiers actually produce: energy x (share-weighted tier efficiency). L244 uses it in
#' place of the core values, as it does for USA with \code{L1441.base_service_EJ_serv_fuel_tech_USA}, so
#' the satiation floors and impedances follow. It runs before L244 because K1441 needs L244's outputs.
#' Only the model base years are changed, the years K1441 calibrates. K1441 checks that the calibrated
#' output of all South Korea building technologies equals the base service L244 writes.
#' @importFrom dplyr filter group_by inner_join mutate select summarise ungroup
#' @author JH 2026
module_energy_K1440.building_det_serv_KOR <- function(command, ...) {
  if(command == driver.DECLARE_INPUTS) {
    return(c(FILE = "common/GCAM_region_names",
             FILE = "gcam-usa/A44.globaltech_shares",
             FILE = "gcam-usa/A44.globaltech_eff",
             "L144.in_EJ_R_bld_serv_F_Yh"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c("K1440.base_service_EJ_serv_fuel_KOR"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    GCAM_region_ID <- region <- supplysector <- subsector <- technology <- technology1 <- technology2 <-
      share_tech2 <- share <- service <- category <- efficiency <- tier.efficiency <- n.tiers <- sum.share <-
      sector <- fuel <- year <- value <- NULL  # silence package check notes

    GCAM_region_names <- get_data(all_data, "common/GCAM_region_names")
    A44.globaltech_shares <- get_data(all_data, "gcam-usa/A44.globaltech_shares", strip_attributes = TRUE)
    A44.globaltech_eff <- get_data(all_data, "gcam-usa/A44.globaltech_eff", strip_attributes = TRUE)
    L144.in_EJ_R_bld_serv_F_Yh <- get_data(all_data, "L144.in_EJ_R_bld_serv_F_Yh", strip_attributes = TRUE)

    GCAM_region_names %>%
      filter(region == gcam.KOREA_REGION) %>%
      dplyr::pull(GCAM_region_ID) ->
      KOREA_ID

    # Same split as K1441: USA's base-year resid heating electricity share of "electric heat pump",
    # used for both resid and comm heating
    A44.globaltech_shares %>%
      filter(supplysector == "resid heating", subsector == "electricity",
             technology1 == "electric furnace", technology2 == "electric heat pump") %>%
      dplyr::pull(share_tech2) ->
      elec.heat.share
    assertthat::assert_that(length(elec.heat.share) == 1)

    TIER_SHARE <- tibble::tibble(technology = c("electric furnace", "electric heat pump"),
                                 share = c(1 - elec.heat.share, elec.heat.share))

    # L144 service -> A44.globaltech_eff category, the same category K1441 uses for the tier efficiency
    SERVICE_CATEGORY <- tibble::tribble(
      ~service, ~category,
      "resid heating modern", "resid heating",
      "comm heating", "comm heating")

    L144.in_EJ_R_bld_serv_F_Yh %>%
      filter(GCAM_region_ID == KOREA_ID, fuel == "electricity", service %in% SERVICE_CATEGORY$service,
             year %in% MODEL_BASE_YEARS) ->
      K1440.elec_heat_KOR

    # Tier efficiencies interpolated to each year, as K1441 does, then weighted by the split
    A44.globaltech_eff %>%
      gather_years(value_col = "efficiency") %>%
      mutate(year = as.integer(year)) %>%
      filter(subsector == "electricity") %>%
      inner_join(SERVICE_CATEGORY, by = c("supplysector" = "category")) %>%
      inner_join(TIER_SHARE, by = "technology") %>%
      group_by(service, technology, share) %>%
      tidyr::complete(year = unique(K1440.elec_heat_KOR$year)) %>%
      mutate(efficiency = approx_fun(year, efficiency, rule = 2)) %>%
      ungroup() %>%
      filter(year %in% K1440.elec_heat_KOR$year) %>%
      group_by(service, year) %>%
      summarise(tier.efficiency = sum(share * efficiency), n.tiers = dplyr::n(), sum.share = sum(share)) %>%
      ungroup() ->
      K1440.tier_eff
    # one efficiency row per tier, and the two tiers make up the whole electricity subsector
    assertthat::assert_that(all(K1440.tier_eff$n.tiers == nrow(TIER_SHARE)),
                            all(abs(K1440.tier_eff$sum.share - 1) < 1e-9),
                            msg = "K1440: expected exactly one efficiency row for each of the two electricity tiers")

    K1440.elec_heat_KOR %>%
      left_join_error_no_match(K1440.tier_eff %>% select(service, year, tier.efficiency), by = c("service", "year")) %>%
      mutate(value = value * tier.efficiency) %>%
      select(GCAM_region_ID, sector, fuel, service, year, value) ->
      K1440.base_service_EJ_serv_fuel_KOR

    assertthat::assert_that(nrow(K1440.base_service_EJ_serv_fuel_KOR) > 0,
                            msg = "K1440: no South Korea heating electricity in L144.in_EJ_R_bld_serv_F_Yh")

    K1440.base_service_EJ_serv_fuel_KOR %>%
      add_title("South Korea heating electricity base service with the efficiency-tier split") %>%
      add_units("EJ/yr") %>%
      add_comments("L144 heating electricity x share-weighted efficiency of electric furnace and electric heat pump") %>%
      add_comments("USA base-year split and USA efficiencies, as in K1441; replaces the L144 values in L244 for the model base years") %>%
      add_legacy_name("K1440.base_service_EJ_serv_fuel_KOR") %>%
      add_precursors("common/GCAM_region_names", "gcam-usa/A44.globaltech_shares", "gcam-usa/A44.globaltech_eff",
                     "L144.in_EJ_R_bld_serv_F_Yh") ->
      K1440.base_service_EJ_serv_fuel_KOR

    return_data(K1440.base_service_EJ_serv_fuel_KOR)
  } else {
    stop("Unknown command")
  }
}
