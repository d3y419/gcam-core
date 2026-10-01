# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_K101.en_bal_KOR
#'
#' Overlay the South Korea (\code{gcam.KOREA_REGION}) energy balance with a Korea-specific data source,
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
#' @importFrom dplyr anti_join bind_rows distinct filter group_by left_join mutate select summarise
#' @importFrom tidyr gather replace_na
#' @author HCM 2026
module_energy_K101.en_bal_KOR <- function(command, ...) {
  if(command == driver.DECLARE_INPUTS) {
    return(c(FILE = "common/GCAM_region_names",
             FILE = "energy/KOR_en_bal.csv",
             "L101.en_bal_EJ_R_Si_Fi_Yh_full"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c("K101.en_bal_EJ_R_Si_Fi_Yh_full"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    GCAM_region_ID <- sector <- fuel <- year <- value <- value_KOR <- NULL  # silence package check notes

    GCAM_region_names <- get_data(all_data, "common/GCAM_region_names")
    L101.en_bal_EJ_R_Si_Fi_Yh_full <- get_data(all_data, "L101.en_bal_EJ_R_Si_Fi_Yh_full", strip_attributes = TRUE)
    KOR_en_bal.csv <- get_data(all_data, "energy/KOR_en_bal.csv")

    # Look up Korea's region ID by name so this chunk follows the region mapping file
    KOREA_REGION_ID <- GCAM_region_names$GCAM_region_ID[GCAM_region_names$region == gcam.KOREA_REGION]
    assertthat::assert_that(length(KOREA_REGION_ID) == 1,
                            msg = paste("Region", gcam.KOREA_REGION, "not found once in common/GCAM_region_names"))

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
      distinct(sector, fuel) ->
      K101.template_sector_fuel

    # The join below keeps only template combinations. Stop if the overlay has a (sector, fuel)
    # pair the template does not know (e.g. a typo in a sector name), or a duplicated pair,
    # instead of silently dropping or double counting that energy.
    KOR_en_bal.csv %>%
      distinct(sector, fuel) %>%
      anti_join(K101.template_sector_fuel, by = c("sector", "fuel")) ->
      K101.KOR_unmatched
    if(nrow(K101.KOR_unmatched) > 0) {
      stop("energy/KOR_en_bal.csv has sector/fuel pairs that are not in L101.en_bal_EJ_R_Si_Fi_Yh_full: ",
           paste(K101.KOR_unmatched$sector, K101.KOR_unmatched$fuel, sep = " / ", collapse = "; "))
    }
    if(anyDuplicated(KOR_en_bal.csv[c("sector", "fuel")]) > 0) {
      stop("energy/KOR_en_bal.csv has duplicated sector/fuel rows")
    }

    K101.template_sector_fuel %>%
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

    # Replace Korea's values in place. The output has exactly the rows of L101, in the same
    # order and with the same column types, so every other region (and any sum downstream
    # whose result depends on row order) sees the unchanged L101 table.
    L101.en_bal_EJ_R_Si_Fi_Yh_full %>%
      left_join(rename(K101.KOR_full, value_KOR = value),
                by = c("GCAM_region_ID", "sector", "fuel", "year")) ->
      K101.joined
    K101.is_KOR <- K101.joined$GCAM_region_ID == KOREA_REGION_ID
    assertthat::assert_that(nrow(K101.joined) == nrow(L101.en_bal_EJ_R_Si_Fi_Yh_full),
                            sum(K101.is_KOR) == nrow(K101.KOR_full),
                            !anyNA(K101.joined$value_KOR[K101.is_KOR]),
                            msg = "Korea overlay rows do not match Korea's rows in L101.en_bal_EJ_R_Si_Fi_Yh_full one to one")
    K101.joined %>%
      mutate(value = if_else(K101.is_KOR, value_KOR, value)) %>%
      select(-value_KOR) ->
      K101.en_bal_EJ_R_Si_Fi_Yh_full

    K101.en_bal_EJ_R_Si_Fi_Yh_full %>%
      add_title("Energy balances by GCAM region / intermediate sector / intermediate fuel / historical year, with South Korea overlaid from a Korea-specific data source") %>%
      add_units("EJ") %>%
      add_comments("South Korea rows are replaced with energy/KOR_en_bal.csv; TES is recomputed for Korea; all other regions pass through unchanged from L101.en_bal_EJ_R_Si_Fi_Yh_full") %>%
      add_legacy_name("K101.en_bal_EJ_R_Si_Fi_Yh_full") %>%
      add_precursors("common/GCAM_region_names", "energy/KOR_en_bal.csv", "L101.en_bal_EJ_R_Si_Fi_Yh_full") ->
      K101.en_bal_EJ_R_Si_Fi_Yh_full

    return_data(K101.en_bal_EJ_R_Si_Fi_Yh_full)
  } else {
    stop("Unknown command")
  }
}
