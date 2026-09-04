# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_K1441.building_det_en_KOR
#'
#' Adds GCAM-USA-style efficiency-tier building technologies (e.g. "gas furnace hi-eff",
#' "electric heat pump") to South Korea's resid/comm heating and cooling subsectors.
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs,
#' a vector of output names, or (if \code{command} is "MAKE") all
#' the generated outputs: \code{K1441.StubTechCalInput_bld_KOR}.
#' @details South Korea's core building technologies are a single flat technology per fuel
#' (e.g. "gas", "electricity"). GCAM-USA's buildings module models several of the same
#' fuels as multiple efficiency-tier technologies (e.g. "gas furnace" vs "gas furnace
#' hi-eff", "electric furnace" vs "electric heat pump") -- these already exist in the
#' shared global-technology-database (written by \code{module_energy_L244.building_det},
#' sourced from GCAM-USA's own assumption files), so no new global technology definitions
#' are needed; South Korea just needs its own calibrated stub-technology instantiations of
#' them, following \code{L244.StubTechCalInput_bld}'s own conventions.
#'
#' South Korea has no equivalent of GCAM-USA's "Scout" technology-partitioning survey data,
#' so base-year (\code{MODEL_FINAL_BASE_YEAR}) tier splits are BORROWED from USA's own
#' base-year exogenous shares (\code{gcam-usa/A44.globaltech_shares}) as a placeholder:
#' \itemize{
#'   \item resid/comm heating electricity: split 76%/24% between "electric furnace" and
#'     "electric heat pump" (USA's only nonzero base-year partition among these tiers).
#'     Korea's existing "electricity" stub-technology calibration is zeroed out for this
#'     split so total calibrated energy is unchanged.
#'   \item All other new tiers ("gas furnace hi-eff", "fuel furnace hi-eff",
#'     "air conditioning hi-eff", "gas cooling") get 0% in the base year, matching USA's own
#'     base-year treatment of these technologies -- they only grow in future periods via the
#'     already-shared global cost/efficiency trajectory. Korea's existing base technology
#'     ("gas", "refined liquids") keeps 100% of its calibration, so nothing is double-counted.
#' }
#'
#' TODO(Korea building technology shares): replace the borrowed USA split with real Korean
#' data once available. What's actually needed is Korea-specific survey/statistical data on
#' building heating/cooling equipment stock composition -- analogous to the US DOE/EIA
#' "Scout" dataset -- ideally covering: (1) the historical share of heat-pump vs. resistance/
#' furnace-type electric heating equipment in the residential and commercial stock; (2) the
#' share of high-efficiency vs. standard-efficiency gas furnaces, oil/LPG furnaces, and air
#' conditioners; (3) any existing gas-fired absorption/engine-driven cooling capacity in the
#' commercial sector. Plausible Korean sources to check: Korea Energy Agency (KEA) building
#' energy statistics, Korea Energy Economics Institute (KEEI) energy consumption surveys,
#' KOSIS household/building appliance ownership surveys, or KDHC (for anything district-heat
#' adjacent). Until then, this chunk's split is a structural placeholder, not measured data.
#' @importFrom dplyr bind_rows filter group_by left_join mutate rename select ungroup
#' @author HCM 2026
module_energy_K1441.building_det_en_KOR <- function(command, ...) {
  KOREA_REGION_NAME <- "South Korea"

  # Base technology -> new efficiency-tier technology, by subsector, and which supplysectors
  # (by regex on supplysector name) the pairing applies to. "split" pairs replace part of the
  # base technology's calibration; "add" pairs are introduced at zero calibrated energy.
  # retirement.category matches gcam-usa/A44.globaltech_retirement.csv's "supplysector" column
  # (a USA end-use category, not a literal GCAM supplysector name) -- every new technology
  # needs an explicit S-curve retirement like its sibling base technology already has
  # (input/extra/korea_bld_retirement_scurve.xml), or GCAM's default (unvintaged, full-
  # turnover) behavior for the new technology can misbehave once mixed into a subsector whose
  # sibling *is* vintaged.
  TIER_MAP <- tibble::tribble(
    ~sector_regex, ~subsector, ~base.technology, ~new.technology, ~mode, ~retirement.category,
    "^resid heating modern_d[0-9]+$", "electricity", "electricity", "electric furnace", "split", "resid heating",
    "^resid heating modern_d[0-9]+$", "electricity", "electricity", "electric heat pump", "split", "resid heating",
    "^comm heating$", "electricity", "electricity", "electric furnace", "split", "comm heating",
    "^comm heating$", "electricity", "electricity", "electric heat pump", "split", "comm heating",
    "^resid heating modern_d[0-9]+$", "gas", "gas", "gas furnace hi-eff", "add", "resid heating",
    "^comm heating$", "gas", "gas", "gas furnace hi-eff", "add", "comm heating",
    "^resid heating modern_d[0-9]+$", "refined liquids", "refined liquids", "fuel furnace hi-eff", "add", "resid heating",
    "^resid cooling modern_d[0-9]+$", "electricity", "electricity", "air conditioning hi-eff", "add", "resid cooling",
    "^comm cooling$", "electricity", "electricity", "air conditioning hi-eff", "add", "comm cooling",
    "^comm cooling$", "gas", "gas", "gas cooling", "add", "comm cooling"
  )

  # NOTE: an earlier version of this chunk also harmonized South Korea's EXISTING base
  # technology cost (e.g. "electricity" heating, ~$12.84/GJ-service, calibration-derived) to
  # GCAM-USA's cost for the corresponding base-tier technology (~$1.3/GJ-service for
  # "electric furnace"), trying to smooth the ~9.5x cost cliff between 2021 and 2025 once the
  # new tiers take over. That override was removed: it targets a technology that already has
  # ZERO calibrated share from 2021 onward (its energy was already reallocated to the new
  # tiers), so it has no effect on the actual future-year competition -- confirmed by
  # re-running with the override and finding the 2021-2025 output trajectory unchanged.
  #
  # The REAL cause of the cost cliff: the shared global-technology-database entries for these
  # building technologies (both old and new) carry ONLY a capital-cost accounting block
  # (tracking-non-energy-input) -- no minicam-energy-input/efficiency at all. That link is
  # provided per-region via StubTechEff. Core's own L244 chunk writes it for every core
  # region's EXISTING technologies (e.g. "electricity"), which is why the old technology's
  # reported cost correctly includes both capital cost AND Korea's real electricity fuel
  # price. This chunk originally did NOT write StubTechEff for the NEW technologies, so their
  # fuel cost was never wired in for South Korea -- their reported cost was effectively just
  # the bare capital-cost figure, missing ~$10/GJ of real fuel cost, making them look far
  # cheaper than they actually are. K1441.StubTechEff_bld_KOR below fixes this, using
  # GCAM-USA's own efficiency data (gcam-usa/A44.globaltech_eff) for the new technologies --
  # see [[project_korea_bld_tier_cost_gap]] memory for the full story.

  if(command == driver.DECLARE_INPUTS) {
    return(c(FILE = "gcam-usa/A44.globaltech_shares",
             FILE = "gcam-usa/A44.globaltech_retirement",
             FILE = "gcam-usa/A44.globaltech_eff",
             "L244.StubTechCalInput_bld"))
  } else if(command == driver.DECLARE_OUTPUTS) {
    return(c("K1441.StubTechCalInput_bld_KOR", "K1441.StubTechShrwt_bld_KOR", "K1441.StubTechSCurve_bld_KOR",
             "K1441.StubTechEff_bld_KOR"))
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    region <- supplysector <- subsector <- stub.technology <- year <- minicam.energy.input <-
      calibrated.value <- share.weight.year <- subs.share.weight <- tech.share.weight <-
      base.technology <- new.technology <- mode <- sector_regex <- share_tech1 <- share_tech2 <-
      technology1 <- technology2 <- elec.heat.share <- retirement.category <- lifetime <-
      half_life_stock <- steepness_stock <- half_life_new <- steepness_new <- steepness <-
      half.life <- technology <- efficiency <- market.name <- NULL  # silence package check notes

    A44.globaltech_shares <- get_data(all_data, "gcam-usa/A44.globaltech_shares", strip_attributes = TRUE)
    A44.globaltech_retirement <- get_data(all_data, "gcam-usa/A44.globaltech_retirement", strip_attributes = TRUE)
    A44.globaltech_eff <- get_data(all_data, "gcam-usa/A44.globaltech_eff", strip_attributes = TRUE)
    L244.StubTechCalInput_bld <- get_data(all_data, "L244.StubTechCalInput_bld", strip_attributes = TRUE)

    # USA's base-year exogenous share of "electric heat pump" within resid heating / electricity.
    # This is the one nonzero split among the tiers K1441 adds; used as South Korea's
    # placeholder split too (see TODO in chunk docs above).
    A44.globaltech_shares %>%
      filter(supplysector == "resid heating", subsector == "electricity",
             technology1 == "electric furnace", technology2 == "electric heat pump") %>%
      dplyr::pull(share_tech2) ->
      elec.heat.share

    # South Korea's existing calibrated base technologies, for the subsector/supplysector
    # combinations eligible for a new efficiency tier.
    L244.StubTechCalInput_bld %>%
      filter(region == KOREA_REGION_NAME) ->
      K1441.KOR_all

    build_rows_for_mapping <- function(map_row, base_data) {
      base_data %>%
        filter(grepl(map_row$sector_regex, supplysector),
               subsector == map_row$subsector,
               stub.technology == map_row$base.technology) ->
        matched

      if(nrow(matched) == 0) return(NULL)

      if(map_row$mode == "add") {
        matched %>%
          mutate(stub.technology = map_row$new.technology,
                 calibrated.value = 0,
                 tech.share.weight = 0,
                 retirement.category = map_row$retirement.category) ->
          new_rows
        return(new_rows)
      } else {
        # "split": scale the base technology's own calibrated value by USA's exogenous share
        # for this specific new.technology, and zero the remainder of the base technology's
        # allocation (handled once per base tech below, not per new-tech row).
        share <- if(map_row$new.technology == "electric heat pump") elec.heat.share else (1 - elec.heat.share)
        matched %>%
          mutate(stub.technology = map_row$new.technology,
                 calibrated.value = round(calibrated.value * share, energy.DIGITS_CALOUTPUT),
                 tech.share.weight = if_else(calibrated.value > 0, 1, 0),
                 retirement.category = map_row$retirement.category) ->
          new_rows
        return(new_rows)
      }
    }

    new_tier_rows <- purrr::map(seq_len(nrow(TIER_MAP)), function(i) {
      build_rows_for_mapping(TIER_MAP[i, ], K1441.KOR_all)
    }) %>%
      dplyr::bind_rows()

    # For the "split" pairs, zero out the base technology's own calibrated value (its energy
    # has been reallocated to the new tiers above) so total calibrated energy is unchanged.
    split_bases <- TIER_MAP %>%
      filter(mode == "split") %>%
      dplyr::distinct(sector_regex, subsector, base.technology)

    zeroed_base_rows <- purrr::map(seq_len(nrow(split_bases)), function(i) {
      map_row <- split_bases[i, ]
      K1441.KOR_all %>%
        filter(grepl(map_row$sector_regex, supplysector),
               subsector == map_row$subsector,
               stub.technology == map_row$base.technology) %>%
        mutate(calibrated.value = 0,
               tech.share.weight = 0)
    }) %>%
      dplyr::bind_rows()

    new_tier_rows %>%
      bind_rows(zeroed_base_rows) %>%
      select(LEVEL2_DATA_NAMES[["StubTechCalInput"]]) ->
      K1441.StubTechCalInput_bld_KOR

    # The zeroed-out base technologies (e.g. "electricity" in resid heating, once its energy
    # is reallocated to "electric furnace" + "electric heat pump") also need an explicit
    # zero share-weight in every future model year. Without this, their future share-weight
    # would fall back to the shared GLOBAL technology's share-weight trajectory (used by other
    # core regions that still rely on "electricity" as their only heating technology), which
    # could let this now-empty technology revive and compete for share alongside its two
    # replacements -- double-counting South Korea's electric heating/cooling capacity.
    zeroed_base_rows %>%
      dplyr::distinct(region, supplysector, subsector, stub.technology) %>%
      repeat_add_columns(tibble::tibble(year = MODEL_FUTURE_YEARS)) %>%
      mutate(share.weight = 0) %>%
      select(LEVEL2_DATA_NAMES[["StubTechShrwt"]]) ->
      K1441.StubTechShrwt_bld_KOR

    # Give every new tier technology the same S-curve age-based retirement as its sibling base
    # technology already has (input/extra/korea_bld_retirement_scurve.xml), using the same
    # borrowed-from-USA retirement category lookup. Applied at MODEL_FINAL_BASE_YEAR (stock
    # parameters) and every future year (new-investment parameters), matching the existing file.
    new_tier_rows %>%
      dplyr::distinct(region, supplysector, subsector, stub.technology, retirement.category) %>%
      left_join_error_no_match(A44.globaltech_retirement, by = c("retirement.category" = "supplysector")) ->
      new_tier_retirement_base

    new_tier_retirement_base %>%
      mutate(year = MODEL_FINAL_BASE_YEAR,
             lifetime = lifetime,
             steepness = steepness_stock,
             half.life = half_life_stock) %>%
      bind_rows(new_tier_retirement_base %>%
                  repeat_add_columns(tibble::tibble(year = MODEL_FUTURE_YEARS)) %>%
                  mutate(steepness = steepness_new,
                         half.life = half_life_new)) %>%
      select(LEVEL2_DATA_NAMES[["StubTechSCurve"]]) ->
      K1441.StubTechSCurve_bld_KOR

    # Wire in the fuel input/efficiency link GCAM-USA's own detailed technologies rely on
    # (see chunk-level NOTE above for why this is needed). A44.globaltech_eff already carries
    # its own minicam.energy.input per row, keyed the same way as A44.globaltech_retirement
    # (supplysector = USA end-use category, e.g. "resid heating"; subsector = fuel;
    # technology = the new tier name), so it's joined the same way as retirement was.
    new_tier_rows %>%
      dplyr::distinct(region, supplysector, subsector, stub.technology, retirement.category) %>%
      # plain left_join (not left_join_error_no_match): each Korea sector/subsector/tech row
      # intentionally expands to one row per USA data year here, ahead of interpolation below
      dplyr::left_join(A44.globaltech_eff %>% gather_years(value_col = "efficiency"),
                        by = c("retirement.category" = "supplysector", "subsector",
                               "stub.technology" = "technology")) %>%
      mutate(year = as.integer(year)) %>%
      # group by the full (supplysector, subsector, stub.technology) key, not just
      # stub.technology -- the same new-technology name (e.g. "electric furnace") appears
      # under multiple supplysectors (each resid dwelling type, comm heating), and those can
      # carry DIFFERENT efficiency schedules (resid vs comm heating categories), so each needs
      # its own interpolation rather than one pooled across all of them.
      group_by(region, supplysector, subsector, stub.technology, minicam.energy.input) %>%
      tidyr::complete(year = MODEL_YEARS) %>%
      mutate(efficiency = approx_fun(year, efficiency, rule = 2)) %>%
      ungroup() %>%
      filter(year %in% MODEL_YEARS) %>%
      mutate(market.name = region) %>%
      select(LEVEL2_DATA_NAMES[["StubTechEff"]]) ->
      K1441.StubTechEff_bld_KOR

    K1441.StubTechCalInput_bld_KOR %>%
      add_title("South Korea efficiency-tier building technology calibration (USA structure, USA-borrowed base-year shares)") %>%
      add_units("EJ") %>%
      add_comments("Adds GCAM-USA's efficiency-tier heating/cooling technologies to South Korea, calibrated using USA's base-year exogenous tier shares as a placeholder (see chunk docs TODO); total calibrated energy per fuel/dwelling-type/year is unchanged") %>%
      add_legacy_name("K1441.StubTechCalInput_bld_KOR") %>%
      add_precursors("gcam-usa/A44.globaltech_shares", "L244.StubTechCalInput_bld") ->
      K1441.StubTechCalInput_bld_KOR

    K1441.StubTechShrwt_bld_KOR %>%
      add_title("South Korea zero share-weight for building technologies replaced by efficiency-tier splits") %>%
      add_units("Unitless") %>%
      add_comments("Keeps technologies like resid/comm heating 'electricity' (replaced by 'electric furnace' + 'electric heat pump') from reviving via the shared global technology's future share-weight trajectory") %>%
      add_legacy_name("K1441.StubTechShrwt_bld_KOR") %>%
      add_precursors("gcam-usa/A44.globaltech_shares", "L244.StubTechCalInput_bld") ->
      K1441.StubTechShrwt_bld_KOR

    K1441.StubTechSCurve_bld_KOR %>%
      add_title("South Korea S-curve retirement for new efficiency-tier building technologies") %>%
      add_units("lifetime/half.life: years; steepness: unitless") %>%
      add_comments("Same borrowed-from-USA retirement category lookup as input/extra/korea_bld_retirement_scurve.xml, applied to the new technologies this chunk adds, so they vintage consistently with their sibling base technology instead of using GCAM's default unvintaged behavior") %>%
      add_legacy_name("K1441.StubTechSCurve_bld_KOR") %>%
      add_precursors("gcam-usa/A44.globaltech_retirement", "L244.StubTechCalInput_bld") ->
      K1441.StubTechSCurve_bld_KOR

    K1441.StubTechEff_bld_KOR %>%
      add_title("South Korea fuel input efficiency for new efficiency-tier building technologies") %>%
      add_units("Unitless efficiency") %>%
      add_comments("Wires the new technologies' minicam-energy-input/efficiency (missing from the shared global-technology-database, which only carries capital-cost tracking) using GCAM-USA's own efficiency data, so their fuel cost is correctly included in their competitive cost -- see chunk docs NOTE for why this was needed") %>%
      add_legacy_name("K1441.StubTechEff_bld_KOR") %>%
      add_precursors("gcam-usa/A44.globaltech_eff", "L244.StubTechCalInput_bld") ->
      K1441.StubTechEff_bld_KOR

    return_data(K1441.StubTechCalInput_bld_KOR, K1441.StubTechShrwt_bld_KOR, K1441.StubTechSCurve_bld_KOR,
                K1441.StubTechEff_bld_KOR)
  } else {
    stop("Unknown command")
  }
}
