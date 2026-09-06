# Copyright 2019 Battelle Memorial Institute; see the LICENSE file.

#' module_energy_K1442.building_serv_KOR
#'
#' Splits South Korea's aggregate "resid others"/"comm others" building service into
#' GCAM-USA-style detailed non-thermal services (batch 1: cooking, hot water, lighting,
#' refrigeration/refrigerators, freezers, and the detailed "other" residual).
#'
#' @param command API command to execute
#' @param ... other optional parameters, depending on command
#' @return Depends on \code{command}: either a vector of required inputs, a vector of output
#' names, or (if \code{command} is "MAKE") all the generated outputs.
#' @details Core gives South Korea a single lumped non-thermal building service per consumer
#' ("comm others", "resid others modern_dN"), while the USA region resolves ~20 distinct
#' services. That lump is the LARGEST piece of Korea's building energy (~0.96 EJ of service
#' output in 2021, vs 0.49 heating and 0.17 cooling), so leaving it aggregated limits any
#' end-use analysis, and it also suppresses internal gains: waste heat from lighting,
#' appliances and hot water is defined per detailed service
#' (\code{L244.StubTechIntGainOutputRatio}) and feeds back into heating/cooling load.
#'
#' Structure is copied from the USA region's own detailed-service rows (same sector names,
#' logits, share-weights, efficiencies, internal-gain ratios and demand-function parameters),
#' and only the QUANTITIES are Korea's. This mirrors how core itself treats these services:
#' \code{L244.GenericServiceSatiation} is computed from USA data and explicitly
#' "read to all regions because they're all the same".
#'
#' Energy is conserved: each detailed service takes a share of Korea's existing "others"
#' calibrated energy (by consumer and fuel, using USA's own service split), and "others" is
#' reduced by exactly the amount reallocated. Batch 1 does not cover every USA service, so
#' "others" legitimately retains a remainder (USA does the same -- its own "comm others" keeps
#' a small residue while "resid others modern_dN" disappears entirely). Coverage of Korea's
#' "others" energy: 100% of commercial gas, ~97% of residential gas, ~75% of residential
#' electricity, ~53% of commercial electricity. Fuels with no USA non-thermal counterpart
#' (e.g. district heat) are left untouched in "others".
#'
#' Note that SERVICE output is not conserved even though ENERGY is: the detailed services
#' carry their own efficiencies rather than the lumped "others" efficiency, so service output
#' is recomputed as energy * efficiency per service. That is the intended effect of resolving
#' the services, not a leak.
#'
#' TODO(Korea building service shares): the split uses USA's service composition as a
#' placeholder, exactly as \code{module_energy_K1441.building_det_en_KOR} does for efficiency
#' tiers. Korea-specific end-use survey data (KEEI household/commercial energy consumption
#' surveys, KOSIS appliance ownership, Korea Energy Agency building statistics) should replace
#' it. Borrowing equipment EFFICIENCY across regions is defensible (globally traded equipment,
#' shared manufacturers); borrowing the service COMPOSITION is a stronger assumption, since it
#' encodes US appliance ownership and commercial building stock mix.
#'
#' Not yet covered (batch 2): comm ventilation/office/non-building, resid televisions,
#' computers, clothes washers, clothes dryers, dishwashers, furnace fans. Also not carried
#' over: \code{L244.GenericServiceAdder} (a region-specific base-year calibration residual, so
#' USA's values would be wrong for Korea) and \code{L244.SubsectorInterp_bld} (subsector
#' share-weights are fully specified here by SubsectorShrwtFllt's fillout, so no
#' uninitialized values remain).
#' @importFrom dplyr anti_join bind_rows distinct filter group_by inner_join left_join mutate rename select summarise ungroup
#' @author HCM 2026
module_energy_K1442.building_serv_KOR <- function(command, ...) {
  KOREA_REGION_NAME <- "South Korea"

  # Batch 1 detailed services. Commercial sectors are unsuffixed; residential ones carry a
  # dwelling-archetype suffix ("modern_dN") in both regions, so USA sector names map onto
  # Korea's archetypes one-for-one.
  SERVICES_COMM <- c("comm cooking", "comm hot water", "comm lighting",
                     "comm refrigeration", "comm other")
  SERVICES_RESID <- c("resid cooking", "resid freezers", "resid hot water",
                      "resid lighting", "resid other", "resid refrigerators")

  # Korea's aggregate services being split. Only the "modern" residential archetypes are
  # split: USA keeps its coal/TradBio dwelling aggregates lumped too, and those carry
  # solid-fuel cooking/lighting that the detailed services do not represent.
  KOR_AGG_COMM <- "comm others"
  KOR_AGG_RESID_PATTERN <- "^resid others modern_d[0-9]+$"

  # Strip the dwelling-archetype suffix to get a bare service name.
  base_service_name <- function(x) sub(" (modern|coal|TradBio)_d[0-9]+$", "", x)

  if(command == driver.DECLARE_INPUTS) {
    return(c("L244.StubTechCalInput_bld",
             "L244.StubTechEff_bld",
             "L244.Supplysector_bld",
             "L244.FinalEnergyKeyword_bld",
             "L244.SubsectorLogit_bld",
             "L244.SubsectorShrwtFllt_bld",
             "L244.FuelPrefElast_bld",
             "L244.StubTech_bld",
             "L244.StubTechIntGainOutputRatio",
             "L244.GenericBaseService",
             "L244.GenericServiceSatiation",
             "L244.GenericServiceImpedance",
             "L244.GenericServiceCoef",
             "L244.Floorspace",
             "L244.GenericServicePrice",
             "L244.GenericBaseDens",
             "L244.GenericServiceAdder"))
  } else if(command == driver.DECLARE_OUTPUTS) {
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
  } else if(command == driver.MAKE) {

    all_data <- list(...)[[1]]

    region <- supplysector <- subsector <- stub.technology <- technology <- year <-
      minicam.energy.input <- calibrated.value <- efficiency <- share <- svc <- consumer <-
      value <- total <- base.service <- building.service.input <- gcam.consumer <- base.building.size <-
      service.per.flsp <- satiation.level <-
      nodeInput <- building.node.input <- archetype <- kor_value <- alloc <- covered <-
      market.name <- share.weight <- all_gone <- price <- base.density <- bias.adder <-
      NULL

    L244.StubTechCalInput_bld <- get_data(all_data, "L244.StubTechCalInput_bld", strip_attributes = TRUE)
    L244.StubTechEff_bld <- get_data(all_data, "L244.StubTechEff_bld", strip_attributes = TRUE)
    L244.Supplysector_bld <- get_data(all_data, "L244.Supplysector_bld", strip_attributes = TRUE)
    L244.FinalEnergyKeyword_bld <- get_data(all_data, "L244.FinalEnergyKeyword_bld", strip_attributes = TRUE)
    L244.SubsectorLogit_bld <- get_data(all_data, "L244.SubsectorLogit_bld", strip_attributes = TRUE)
    L244.SubsectorShrwtFllt_bld <- get_data(all_data, "L244.SubsectorShrwtFllt_bld", strip_attributes = TRUE)
    L244.FuelPrefElast_bld <- get_data(all_data, "L244.FuelPrefElast_bld", strip_attributes = TRUE)
    L244.StubTech_bld <- get_data(all_data, "L244.StubTech_bld", strip_attributes = TRUE)
    L244.StubTechIntGainOutputRatio <- get_data(all_data, "L244.StubTechIntGainOutputRatio", strip_attributes = TRUE)
    L244.GenericBaseService <- get_data(all_data, "L244.GenericBaseService", strip_attributes = TRUE)
    L244.GenericServiceSatiation <- get_data(all_data, "L244.GenericServiceSatiation", strip_attributes = TRUE)
    L244.GenericServiceImpedance <- get_data(all_data, "L244.GenericServiceImpedance", strip_attributes = TRUE)
    L244.GenericServiceCoef <- get_data(all_data, "L244.GenericServiceCoef", strip_attributes = TRUE)
    L244.Floorspace <- get_data(all_data, "L244.Floorspace", strip_attributes = TRUE)
    L244.GenericServicePrice <- get_data(all_data, "L244.GenericServicePrice", strip_attributes = TRUE)
    L244.GenericBaseDens <- get_data(all_data, "L244.GenericBaseDens", strip_attributes = TRUE)
    L244.GenericServiceAdder <- get_data(all_data, "L244.GenericServiceAdder", strip_attributes = TRUE)

    # ---- 1. Which Korea sectors are being split, and which USA sectors are the targets ----

    kor_agg <- L244.StubTechCalInput_bld %>%
      filter(region == KOREA_REGION_NAME,
             supplysector == KOR_AGG_COMM | grepl(KOR_AGG_RESID_PATTERN, supplysector)) %>%
      mutate(archetype = if_else(supplysector == KOR_AGG_COMM, "",
                                 sub("^resid others", "", supplysector)),
             consumer = if_else(supplysector == KOR_AGG_COMM, "comm", "resid"))

    # Target sector names: commercial as-is, residential per dwelling archetype.
    target_sectors <- c(SERVICES_COMM,
                        paste0(rep(SERVICES_RESID, each = length(unique(kor_agg$archetype[kor_agg$consumer == "resid"]))),
                               unique(kor_agg$archetype[kor_agg$consumer == "resid"])))

    is_target <- function(x) x %in% target_sectors

    # ---- 2. USA service composition, by consumer and fuel ----
    # Shares are taken over ALL of USA's non-thermal services (not just batch 1), so a batch-1
    # service gets its true share of the non-thermal total and the uncovered remainder stays
    # in "others" rather than being silently inflated.
    # Shares are resolved all the way down to USA's individual TECHNOLOGIES, not just to the
    # service, because USA's detailed services are built from named equipment with efficiency
    # tiers ("electric heat pump water heater", "fluorescent", "refrigerator hi-eff", "gas
    # range", ...) rather than from fuel-named technologies. Korea's aggregate carries only
    # fuel-named technologies, so allocating in one step both splits the service and lands on
    # a technology name that actually exists in the global technology database. (The
    # exception is "resid other"/"comm other", which legitimately keep plain fuel names.)
    usa_shares <- L244.StubTechCalInput_bld %>%
      filter(region == gcam.USA_REGION,
             year == MODEL_FINAL_BASE_YEAR,
             !grepl("heating|cooling", supplysector)) %>%
      mutate(svc = base_service_name(supplysector),
             consumer = if_else(grepl("^resid", svc), "resid", "comm")) %>%
      group_by(consumer, subsector, svc, stub.technology, minicam.energy.input) %>%
      summarise(value = sum(calibrated.value), .groups = "drop") %>%
      group_by(consumer, subsector) %>%
      mutate(total = sum(value)) %>%
      ungroup() %>%
      filter(total > 0) %>%
      mutate(share = value / total) %>%
      # keep only batch-1 services; the rest of the share stays with "others"
      filter(svc %in% c(SERVICES_COMM, SERVICES_RESID)) %>%
      select(consumer, subsector, svc, stub.technology, minicam.energy.input, share)

    # ---- 3. Allocate Korea's aggregate energy to the detailed services ----
    # Only the plain fuel-named technologies are split (stub.technology == subsector). Korea's
    # aggregate also carries a "hydrogen" technology inside the gas subsector, which has no
    # counterpart among USA's non-thermal services; splitting it would silently turn hydrogen
    # into gas appliances, so it stays in "others" untouched.
    splittable <- kor_agg$stub.technology == kor_agg$subsector

    new_cal <- kor_agg[splittable, ] %>%
      select(-stub.technology, -minicam.energy.input) %>%
      inner_join(usa_shares, by = c("consumer", "subsector"),
                 relationship = "many-to-many") %>%
      mutate(supplysector = paste0(svc, archetype),
             calibrated.value = calibrated.value * share) %>%
      select(LEVEL2_DATA_NAMES[["StubTechCalInput"]])

    # "others" keeps whatever batch 1 does not cover, per consumer and fuel.
    covered_share <- usa_shares %>%
      group_by(consumer, subsector) %>%
      summarise(covered = sum(share), .groups = "drop")

    reduced_agg_all <- kor_agg %>%
      left_join(covered_share, by = c("consumer", "subsector")) %>%
      # non-splittable technologies (e.g. hydrogen) keep all of their energy
      mutate(covered = if_else(is.na(covered) | !splittable, 0, covered),
             calibrated.value = calibrated.value * (1 - covered)) %>%
      select(LEVEL2_DATA_NAMES[["StubTechCalInput"]])

    # Where a fuel is FULLY covered by the detailed services (commercial gas and refined
    # liquids are 100% covered), the aggregate is left holding exactly zero. Leaving that in
    # place produces a malformed technology -- GCAM logs "Mixed calibrated and variable
    # children or read a zero calibration value" thousands of times per run, and the emptied
    # husk destabilises the solve well beyond South Korea (traded gas and coal markets across
    # a dozen regions drift by ~0.2-1%). So the emptied technologies are DELETED rather than
    # zeroed: the detailed services replace them outright, which is what the USA region's own
    # structure does (its "resid others" does not exist at all).
    emptied <- reduced_agg_all %>%
      group_by(region, supplysector, subsector, stub.technology) %>%
      summarise(kor_value = max(abs(calibrated.value)), .groups = "drop") %>%
      filter(kor_value == 0) %>%
      select(region, supplysector, subsector, stub.technology)

    # Deleting every technology in a subsector leaves an EMPTY subsector, which GCAM cannot
    # handle -- it segfaults during initialisation with nothing written to main_log. So a
    # subsector that loses all of its technologies is deleted whole, and only partially
    # emptied subsectors delete individual technologies. The authoritative technology list
    # comes from L244.StubTech_bld rather than from the calibration table, because a
    # technology can exist without a calibration row (South Korea's "hydrogen" sits in the gas
    # subsector this way) and such a technology still keeps its subsector alive.
    kor_agg_techs <- L244.StubTech_bld %>%
      filter(region == KOREA_REGION_NAME,
             supplysector == KOR_AGG_COMM | grepl(KOR_AGG_RESID_PATTERN, supplysector)) %>%
      select(region, supplysector, subsector, stub.technology) %>%
      distinct()

    emptied_subsectors <- kor_agg_techs %>%
      left_join(emptied %>% mutate(covered = TRUE),
                by = c("region", "supplysector", "subsector", "stub.technology")) %>%
      group_by(region, supplysector, subsector) %>%
      summarise(all_gone = all(!is.na(covered)), .groups = "drop") %>%
      filter(all_gone) %>%
      select(region, supplysector, subsector)

    K1442.DeleteSubsector_bld_KOR <- emptied_subsectors %>%
      select(LEVEL2_DATA_NAMES[["DeleteSubsector"]])

    K1442.DeleteStubTech_bld_KOR <- emptied %>%
      anti_join(emptied_subsectors, by = c("region", "supplysector", "subsector")) %>%
      select(LEVEL2_DATA_NAMES[["DeleteStubTech"]])

    reduced_agg <- reduced_agg_all %>%
      anti_join(emptied, by = c("region", "supplysector", "subsector", "stub.technology"))

    K1442.StubTechCalInput_bld_KOR <- bind_rows(new_cal, reduced_agg)

    # ---- 4. Structural tables: copy USA's rows for the target sectors ----
    # Only the region label changes; sector/subsector/technology names already match, because
    # Korea's dwelling archetypes use the same "modern_dN" naming as USA's.
    usa_copy <- function(d) {
      d %>%
        filter(region == gcam.USA_REGION, is_target(supplysector)) %>%
        mutate(region = KOREA_REGION_NAME)
    }

    K1442.Supplysector_bld_KOR <- usa_copy(L244.Supplysector_bld)
    K1442.FinalEnergyKeyword_bld_KOR <- usa_copy(L244.FinalEnergyKeyword_bld)
    K1442.SubsectorLogit_bld_KOR <- usa_copy(L244.SubsectorLogit_bld)
    K1442.SubsectorShrwtFllt_bld_KOR <- usa_copy(L244.SubsectorShrwtFllt_bld)
    K1442.FuelPrefElast_bld_KOR <- usa_copy(L244.FuelPrefElast_bld)
    K1442.StubTech_bld_KOR <- usa_copy(L244.StubTech_bld)
    K1442.StubTechIntGainOutputRatio_KOR <- usa_copy(L244.StubTechIntGainOutputRatio)

    # Efficiency comes from USA as well, but the fuel market must be Korea's own.
    K1442.StubTechEff_bld_KOR <- usa_copy(L244.StubTechEff_bld) %>%
      mutate(market.name = KOREA_REGION_NAME)

    # ---- 5. Demand side ----
    # Base service is recomputed from the allocated energy and the service's own efficiency,
    # the same way L244 builds it (base.service = calibrated.value * efficiency), so energy
    # and service stay mutually consistent.
    eff_lookup <- K1442.StubTechEff_bld_KOR %>%
      select(supplysector, subsector, stub.technology, year, efficiency)

    new_base_service <- K1442.StubTechCalInput_bld_KOR %>%
      left_join(eff_lookup, by = c("supplysector", "subsector", "stub.technology", "year")) %>%
      # Korea's own "others" efficiency is not in the USA-derived lookup; fall back to it so
      # the retained remainder keeps a correct service value.
      left_join(L244.StubTechEff_bld %>%
                  filter(region == KOREA_REGION_NAME) %>%
                  select(supplysector, subsector, stub.technology, year,
                         kor_eff = efficiency),
                by = c("supplysector", "subsector", "stub.technology", "year")) %>%
      mutate(efficiency = if_else(is.na(efficiency), kor_eff, efficiency)) %>%
      group_by(supplysector, year) %>%
      summarise(base.service = sum(calibrated.value * efficiency, na.rm = TRUE),
                .groups = "drop")

    # Node columns (gcam.consumer / nodeInput / building.node.input) are taken from Korea's
    # OWN aggregate rows rather than from USA's, so the new services attach to Korea's
    # existing consumer nodes rather than importing USA's node naming.
    kor_nodes <- L244.GenericBaseService %>%
      filter(region == KOREA_REGION_NAME,
             building.service.input == KOR_AGG_COMM |
               grepl(KOR_AGG_RESID_PATTERN, building.service.input)) %>%
      mutate(archetype = if_else(building.service.input == KOR_AGG_COMM, "",
                                 sub("^resid others", "", building.service.input)),
             consumer = if_else(building.service.input == KOR_AGG_COMM, "comm", "resid")) %>%
      select(region, gcam.consumer, nodeInput, building.node.input, archetype, consumer) %>%
      distinct()

    service_nodes <- bind_rows(
      kor_nodes %>% filter(consumer == "comm") %>%
        tidyr::crossing(svc = SERVICES_COMM),
      kor_nodes %>% filter(consumer == "resid") %>%
        tidyr::crossing(svc = SERVICES_RESID)) %>%
      mutate(building.service.input = paste0(svc, archetype)) %>%
      select(region, gcam.consumer, nodeInput, building.node.input, building.service.input)

    # Retained aggregates keep their existing node rows unchanged.
    agg_nodes <- L244.GenericBaseService %>%
      filter(region == KOREA_REGION_NAME,
             building.service.input == KOR_AGG_COMM |
               grepl(KOR_AGG_RESID_PATTERN, building.service.input)) %>%
      select(region, gcam.consumer, nodeInput, building.node.input, building.service.input) %>%
      distinct()

    K1442.GenericBaseService_KOR <- bind_rows(service_nodes, agg_nodes) %>%
      inner_join(new_base_service,
                 by = c("building.service.input" = "supplysector")) %>%
      select(LEVEL2_DATA_NAMES[["GenericBaseService"]])

    # Demand-function parameters: USA's values, attached to Korea's nodes by service name.
    param_copy <- function(d) {
      service_nodes %>%
        inner_join(d %>%
                     filter(region == gcam.USA_REGION) %>%
                     select(-region, -gcam.consumer, -nodeInput, -building.node.input) %>%
                     distinct(),
                   by = "building.service.input")
    }

    # Satiation is a service-per-floorspace ceiling, so a borrowed USA value that sits BELOW
    # Korea's own base-year service per floorspace leaves the demand function ill-posed (the
    # service is already past its own satiation point). Core guards against exactly this when
    # it builds L244.GenericServiceSatiation -- pmax(satiation.level, service.per.flsp *
    # 1.0001) -- and the same guard has to be applied here, against KOREA's floorspace and
    # KOREA's newly allocated base service rather than USA's.
    kor_flsp <- L244.Floorspace %>%
      filter(region == KOREA_REGION_NAME, year == MODEL_FINAL_BASE_YEAR) %>%
      group_by(region, gcam.consumer, nodeInput, building.node.input) %>%
      summarise(base.building.size = sum(base.building.size), .groups = "drop")

    kor_service_per_flsp <- K1442.GenericBaseService_KOR %>%
      filter(year == MODEL_FINAL_BASE_YEAR) %>%
      left_join(kor_flsp,
                by = c("region", "gcam.consumer", "nodeInput", "building.node.input")) %>%
      mutate(service.per.flsp = if_else(is.na(base.building.size) | base.building.size == 0,
                                        0, base.service / base.building.size)) %>%
      select(region, gcam.consumer, nodeInput, building.node.input,
             building.service.input, service.per.flsp)

    K1442.GenericServiceSatiation_KOR <- param_copy(L244.GenericServiceSatiation) %>%
      left_join(kor_service_per_flsp,
                by = c("region", "gcam.consumer", "nodeInput", "building.node.input",
                       "building.service.input")) %>%
      mutate(service.per.flsp = if_else(is.na(service.per.flsp), 0, service.per.flsp),
             satiation.level = pmax(satiation.level, service.per.flsp * 1.0001)) %>%
      select(LEVEL2_DATA_NAMES[["GenericServiceSatiation"]])
    K1442.GenericServiceImpedance_KOR <- param_copy(L244.GenericServiceImpedance) %>%
      select(LEVEL2_DATA_NAMES[["GenericServiceImpedance"]])
    K1442.GenericServiceCoef_KOR <- param_copy(L244.GenericServiceCoef) %>%
      select(LEVEL2_DATA_NAMES[["GenericServiceCoef"]])

    # ---- 6. The remaining per-service demand parameters ----
    # Supplying the supply side plus satiation/impedance/coef is NOT enough: core also writes
    # a base-year service PRICE, a base DENSITY, a bias ADDER and the generic SHARES for every
    # building service. Omitting them leaves the consumer side unable to reproduce the
    # calibrated service, which shows up as a persistent service-market imbalance that leaks
    # into globally traded gas and coal markets (a dozen regions drifting ~0.2-1%), not as a
    # South Korea-only problem.
    #
    # These four come from SOUTH KOREA's own aggregate rows rather than from USA: they are
    # calibration quantities in Korea's own price and floorspace terms, so USA's values would
    # be simply wrong here (unlike equipment efficiency, which is globally traded and is
    # legitimately borrowed above).
    kor_agg_service_names <- c(KOR_AGG_COMM)

    # Share of each new service in the aggregate it replaces, by consumer, from the newly
    # allocated base service. Used to split the additive/extensive parameters.
    new_service_share <- K1442.GenericBaseService_KOR %>%
      filter(year == MODEL_FINAL_BASE_YEAR,
             !building.service.input %in% kor_agg_service_names,
             !grepl("^resid others", building.service.input)) %>%
      group_by(region, gcam.consumer, nodeInput, building.node.input) %>%
      # NB: elementwise guard, not if_else(sum(...) > 0, ...) -- dplyr::if_else requires the
      # condition and the branches to be the same length, and a group-level sum is length 1.
      mutate(share = base.service / sum(base.service),
             share = if_else(is.na(share) | is.infinite(share), 0, share)) %>%
      ungroup() %>%
      select(region, gcam.consumer, nodeInput, building.node.input,
             building.service.input, share)

    # Price is intensive ($/service), so the replacing services inherit the aggregate's price
    # directly rather than a split of it -- they are served by the same fuels at the same
    # Korean prices.
    K1442.GenericServicePrice_KOR <- new_service_share %>%
      left_join(L244.GenericServicePrice %>%
                  filter(region == KOREA_REGION_NAME,
                         building.service.input %in% kor_agg_service_names) %>%
                  select(region, gcam.consumer, nodeInput, building.node.input, price),
                by = c("region", "gcam.consumer", "nodeInput", "building.node.input")) %>%
      filter(!is.na(price)) %>%
      select(LEVEL2_DATA_NAMES[["GenericServicePrice"]])

    # Density and bias adder are extensive (per unit floorspace), so they are split across the
    # replacing services in proportion to base service, preserving the aggregate total.
    K1442.GenericBaseDens_KOR <- new_service_share %>%
      left_join(L244.GenericBaseDens %>%
                  filter(region == KOREA_REGION_NAME,
                         building.service.input %in% kor_agg_service_names) %>%
                  select(region, gcam.consumer, nodeInput, building.node.input, base.density),
                by = c("region", "gcam.consumer", "nodeInput", "building.node.input")) %>%
      filter(!is.na(base.density)) %>%
      mutate(base.density = base.density * share) %>%
      select(LEVEL2_DATA_NAMES[["GenericBaseDens"]])

    K1442.GenericServiceAdder_KOR <- new_service_share %>%
      left_join(L244.GenericServiceAdder %>%
                  filter(region == KOREA_REGION_NAME,
                         building.service.input %in% kor_agg_service_names) %>%
                  select(region, gcam.consumer, nodeInput, building.node.input,
                         year, bias.adder),
                by = c("region", "gcam.consumer", "nodeInput", "building.node.input"),
                relationship = "many-to-many") %>%
      filter(!is.na(bias.adder)) %>%
      mutate(bias.adder = bias.adder * share) %>%
      select(LEVEL2_DATA_NAMES[["GenericServiceAdder"]])


    # ===================================================

    K1442.StubTechCalInput_bld_KOR %>%
      add_title("South Korea detailed non-thermal building service calibration (batch 1)") %>%
      add_units("EJ") %>%
      add_comments("Korea's aggregate others energy reallocated across USA-style detailed services using USA's service composition by consumer and fuel; the aggregate keeps the uncovered remainder so total energy is unchanged") %>%
      add_legacy_name("K1442.StubTechCalInput_bld_KOR") %>%
      add_precursors("L244.StubTechCalInput_bld") ->
      K1442.StubTechCalInput_bld_KOR

    K1442.Supplysector_bld_KOR %>%
      add_title("South Korea detailed building service supplysectors (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region's detailed service sectors") %>%
      add_legacy_name("K1442.Supplysector_bld_KOR") %>%
      add_precursors("L244.Supplysector_bld") ->
      K1442.Supplysector_bld_KOR

    K1442.FinalEnergyKeyword_bld_KOR %>%
      add_title("South Korea detailed building service final energy keywords (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region") %>%
      add_legacy_name("K1442.FinalEnergyKeyword_bld_KOR") %>%
      add_precursors("L244.FinalEnergyKeyword_bld") ->
      K1442.FinalEnergyKeyword_bld_KOR

    K1442.SubsectorLogit_bld_KOR %>%
      add_title("South Korea detailed building service subsector logits (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region") %>%
      add_legacy_name("K1442.SubsectorLogit_bld_KOR") %>%
      add_precursors("L244.SubsectorLogit_bld") ->
      K1442.SubsectorLogit_bld_KOR

    K1442.SubsectorShrwtFllt_bld_KOR %>%
      add_title("South Korea detailed building service subsector share-weights (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region; fillout covers all years so no share-weight is left uninitialized") %>%
      add_legacy_name("K1442.SubsectorShrwtFllt_bld_KOR") %>%
      add_precursors("L244.SubsectorShrwtFllt_bld") ->
      K1442.SubsectorShrwtFllt_bld_KOR

    K1442.FuelPrefElast_bld_KOR %>%
      add_title("South Korea detailed building service fuel preference elasticities (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region") %>%
      add_legacy_name("K1442.FuelPrefElast_bld_KOR") %>%
      add_precursors("L244.FuelPrefElast_bld") ->
      K1442.FuelPrefElast_bld_KOR

    K1442.StubTech_bld_KOR %>%
      add_title("South Korea detailed building service stub technologies (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region") %>%
      add_legacy_name("K1442.StubTech_bld_KOR") %>%
      add_precursors("L244.StubTech_bld") ->
      K1442.StubTech_bld_KOR

    K1442.StubTechEff_bld_KOR %>%
      add_title("South Korea detailed building service technology efficiencies (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("USA efficiencies (globally traded equipment) pointed at South Korea's own fuel markets") %>%
      add_legacy_name("K1442.StubTechEff_bld_KOR") %>%
      add_precursors("L244.StubTechEff_bld") ->
      K1442.StubTechEff_bld_KOR

    K1442.StubTechIntGainOutputRatio_KOR %>%
      add_title("South Korea detailed building service internal gain output ratios (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("Copied from the USA region; these drive waste-heat feedback into heating and cooling load, which the lumped others service could not represent") %>%
      add_legacy_name("K1442.StubTechIntGainOutputRatio_KOR") %>%
      add_precursors("L244.StubTechIntGainOutputRatio") ->
      K1442.StubTechIntGainOutputRatio_KOR

    K1442.GenericBaseService_KOR %>%
      add_title("South Korea detailed building service base service output (batch 1)") %>%
      add_units("EJ") %>%
      add_comments("Recomputed as calibrated energy times each service's own efficiency, for both the new detailed services and the reduced aggregate") %>%
      add_legacy_name("K1442.GenericBaseService_KOR") %>%
      add_precursors("L244.GenericBaseService", "L244.StubTechCalInput_bld", "L244.StubTechEff_bld") ->
      K1442.GenericBaseService_KOR

    K1442.GenericServiceSatiation_KOR %>%
      add_title("South Korea detailed building service satiation levels (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("USA values attached to Korea's consumer nodes, consistent with core L244 which reads generic service satiation to all regions because they are the same") %>%
      add_legacy_name("K1442.GenericServiceSatiation_KOR") %>%
      add_precursors("L244.GenericServiceSatiation", "L244.GenericBaseService", "L244.Floorspace") ->
      K1442.GenericServiceSatiation_KOR

    K1442.GenericServiceImpedance_KOR %>%
      add_title("South Korea detailed building service satiation impedance (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("USA values attached to Korea's consumer nodes") %>%
      add_legacy_name("K1442.GenericServiceImpedance_KOR") %>%
      add_precursors("L244.GenericServiceImpedance", "L244.GenericBaseService") ->
      K1442.GenericServiceImpedance_KOR

    K1442.GenericServiceCoef_KOR %>%
      add_title("South Korea detailed building service demand coefficients (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("USA values attached to Korea's consumer nodes") %>%
      add_legacy_name("K1442.GenericServiceCoef_KOR") %>%
      add_precursors("L244.GenericServiceCoef", "L244.GenericBaseService") ->
      K1442.GenericServiceCoef_KOR

    K1442.DeleteStubTech_bld_KOR %>%
      add_title("South Korea aggregate building service technologies fully replaced by detailed services") %>%
      add_units("NA") %>%
      add_comments("Technologies whose energy is entirely reallocated to the detailed services are deleted rather than left at zero, which would leave a malformed zero-output technology") %>%
      add_legacy_name("K1442.DeleteStubTech_bld_KOR") %>%
      add_precursors("L244.StubTechCalInput_bld") ->
      K1442.DeleteStubTech_bld_KOR

    K1442.DeleteSubsector_bld_KOR %>%
      add_title("South Korea aggregate building service subsectors fully replaced by detailed services") %>%
      add_units("NA") %>%
      add_comments("Subsectors that lose every technology are deleted whole; leaving an empty subsector segfaults GCAM during initialisation") %>%
      add_legacy_name("K1442.DeleteSubsector_bld_KOR") %>%
      add_precursors("L244.StubTechCalInput_bld", "L244.StubTech_bld") ->
      K1442.DeleteSubsector_bld_KOR

    K1442.GenericServicePrice_KOR %>%
      add_title("South Korea detailed building service base-year prices (batch 1)") %>%
      add_units("1975$/GJ-service") %>%
      add_comments("Inherited from the South Korea aggregate service being replaced; price is intensive so it is not split") %>%
      add_legacy_name("K1442.GenericServicePrice_KOR") %>%
      add_precursors("L244.GenericServicePrice", "L244.GenericBaseService") ->
      K1442.GenericServicePrice_KOR

    K1442.GenericBaseDens_KOR %>%
      add_title("South Korea detailed building service base density (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("South Korea's aggregate base density split across the replacing services in proportion to base service") %>%
      add_legacy_name("K1442.GenericBaseDens_KOR") %>%
      add_precursors("L244.GenericBaseDens", "L244.GenericBaseService") ->
      K1442.GenericBaseDens_KOR

    K1442.GenericServiceAdder_KOR %>%
      add_title("South Korea detailed building service bias adders (batch 1)") %>%
      add_units("Unitless") %>%
      add_comments("South Korea's own calibrated aggregate bias adder split across the replacing services in proportion to base service, preserving the total correction") %>%
      add_legacy_name("K1442.GenericServiceAdder_KOR") %>%
      add_precursors("L244.GenericServiceAdder", "L244.GenericBaseService") ->
      K1442.GenericServiceAdder_KOR


    return_data(K1442.GenericServicePrice_KOR, K1442.GenericBaseDens_KOR,
                K1442.GenericServiceAdder_KOR,
                K1442.DeleteSubsector_bld_KOR, K1442.DeleteStubTech_bld_KOR, K1442.Supplysector_bld_KOR, K1442.FinalEnergyKeyword_bld_KOR,
                K1442.SubsectorLogit_bld_KOR, K1442.SubsectorShrwtFllt_bld_KOR,
                K1442.FuelPrefElast_bld_KOR, K1442.StubTech_bld_KOR,
                K1442.StubTechEff_bld_KOR, K1442.StubTechIntGainOutputRatio_KOR,
                K1442.StubTechCalInput_bld_KOR, K1442.GenericBaseService_KOR,
                K1442.GenericServiceSatiation_KOR, K1442.GenericServiceImpedance_KOR,
                K1442.GenericServiceCoef_KOR)
  } else {
    stop("Unknown command")
  }
}
