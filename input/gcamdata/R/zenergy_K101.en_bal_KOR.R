# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_K101.en_bal_KOR
#'
#' Overlay the South Korea (GCAM_region_ID 28) energy balance with a Korea-specific data source,
#' independent of the rest of the global IEA-based energy balance.
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs,
#' a vector of output names, or (if \code{command} is "MAKE") all
#' the generated outputs: \code{K101.en_bal_EJ_R_Si_Fi_Yh_full}.
#' @details Replaces South Korea's rows in \code{L101.en_bal_EJ_R_Si_Fi_Yh_full} with the
#' contents of \code{energy/KOR_en_bal.csv}, an editable Korea-only overlay. Total primary
#' energy supply (TES) is recomputed for Korea from the overlay's in_/net_ sector rows, using
#' the same logic as \code{module_energy_L101.en_bal_IEA}, so the two stay internally consistent.
#' All other regions pass through unchanged.
#' @importFrom dplyr bind_rows distinct filter group_by left_join mutate select summarise
#' @importFrom tidyr gather replace_na
#' @author HCM 2026
module_energy_K101.en_bal_KOR <- function(command, ...) {
  KOREA_REGION_ID <- 28

  if(command == driver.DECLARE_INPUTS) {
    return(c(FILE = "energy/KOR_en_bal.csv",
             "L101.en_bal_EJ_R_Si_Fi_Yh_full"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c("K101.en_bal_EJ_R_Si_Fi_Yh_full"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    GCAM_region_ID <- sector <- fuel <- year <- value <- NULL  # silence package check notes

    L101.en_bal_EJ_R_Si_Fi_Yh_full <- get_data(all_data, "L101.en_bal_EJ_R_Si_Fi_Yh_full", strip_attributes = TRUE)
    KOR_en_bal.csv <- get_data(all_data, "energy/KOR_en_bal.csv")

    # Long-form Korea overlay
    KOR_en_bal.csv %>%
      gather_years() %>%
      filter(year %in% HISTORICAL_YEARS) %>%
      mutate(GCAM_region_ID = KOREA_REGION_ID) ->
      K101.KOR_overlay_sparse

    # Backfill to the full (sector, fuel, year) grid used everywhere else in
    # L101.en_bal_EJ_R_Si_Fi_Yh_full (every combination that appears in any region, all
    # HISTORICAL_YEARS, zero-filled where absent). KOR_en_bal.csv only lists combinations
    # that are ever nonzero for Korea; several downstream chunks rely on every region having
    # the complete template (e.g. an explicit zero row for a sector Korea has no activity in),
    # via left_join_error_no_match, so this substitution must preserve that structural shape.
    L101.en_bal_EJ_R_Si_Fi_Yh_full %>%
      filter(sector != energy.TPES_FLOW) %>%
      distinct(sector, fuel) %>%
      repeat_add_columns(tibble::tibble(year = HISTORICAL_YEARS)) %>%
      mutate(GCAM_region_ID = KOREA_REGION_ID) %>%
      left_join(K101.KOR_overlay_sparse, by = c("GCAM_region_ID", "sector", "fuel", "year")) %>%
      replace_na(list(value = 0)) ->
      K101.KOR_overlay

    # Recompute TES for Korea from the overlay, mirroring L101.en_bal_IEA's TES logic:
    # sum of all flows that are inputs (sector starting with in_ or net_)
    K101.KOR_overlay %>%
      filter(grepl("^in_", sector) | grepl("^net_", sector)) %>%
      mutate(sector = energy.TPES_FLOW) %>%
      group_by(GCAM_region_ID, sector, fuel, year) %>%
      summarise(value = sum(value)) %>%
      ungroup() ->
      K101.KOR_TES

    K101.KOR_overlay %>%
      bind_rows(K101.KOR_TES) ->
      K101.KOR_full

    # Replace Korea's rows in the full table; leave all other regions untouched.
    # Preserve the original region-ascending row order so downstream chunks that are
    # sensitive to floating-point summation order are unaffected by this substitution.
    L101.en_bal_EJ_R_Si_Fi_Yh_full %>%
      filter(GCAM_region_ID != KOREA_REGION_ID) %>%
      bind_rows(K101.KOR_full) %>%
      arrange(GCAM_region_ID, sector, fuel, year) ->
      K101.en_bal_EJ_R_Si_Fi_Yh_full

    K101.en_bal_EJ_R_Si_Fi_Yh_full %>%
      add_title("Energy balances by GCAM region / intermediate sector / intermediate fuel / historical year, with South Korea overlaid from a Korea-specific data source") %>%
      add_units("EJ") %>%
      add_comments("South Korea (GCAM_region_ID 28) rows are replaced with energy/KOR_en_bal.csv; TES is recomputed for Korea; all other regions pass through unchanged from L101.en_bal_EJ_R_Si_Fi_Yh_full") %>%
      add_legacy_name("K101.en_bal_EJ_R_Si_Fi_Yh_full") %>%
      add_precursors("energy/KOR_en_bal.csv", "L101.en_bal_EJ_R_Si_Fi_Yh_full") ->
      K101.en_bal_EJ_R_Si_Fi_Yh_full

    return_data(K101.en_bal_EJ_R_Si_Fi_Yh_full)
  } else {
    stop("Unknown command")
  }
}
