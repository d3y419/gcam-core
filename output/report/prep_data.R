# Tidy the ModelInterface batch CSVs into long tables for the report.
suppressPackageStartupMessages({library(dplyr); library(tidyr); library(readr); library(stringr)})
read_batch <- function(f, drop2020 = TRUE) {
  lines <- readLines(f, warn = FALSE); lines <- lines[nzchar(trimws(lines))]
  starts <- which(!grepl(",", lines)); ends <- c(starts[-1] - 1, length(lines))
  out <- list()
  for (i in seq_along(starts)) {
    title <- trimws(lines[starts[i]])
    tbl <- read_csv(I(lines[(starts[i] + 1):ends[i]]), show_col_types = FALSE, progress = FALSE)
    yrs <- names(tbl)[grepl("^[0-9]{4}$", names(tbl))]
    out[[title]] <- tbl %>% pivot_longer(all_of(yrs), names_to = "year", values_to = "value") %>%
      mutate(year = as.integer(year), scenario = str_replace(scenario, ",date=.*$", "")) %>%
      filter(!drop2020 | year != 2020)
  }
  out
}
fuel_map <- c("c coal" = "coal", "a oil" = "oil", "b natural gas" = "gas", "d biomass" = "biomass",
              "j traditional biomass" = "biomass", "f hydro" = "hydro", "e nuclear" = "nuclear",
              "i geothermal" = "geothermal", "g wind" = "wind", "h solar" = "solar")
tech_map <- function(t) case_when(
  str_detect(t, "^coal") ~ "coal", str_detect(t, "refined liquids") ~ "oil", str_detect(t, "^gas") ~ "gas",
  str_detect(t, "^biomass") ~ "biomass", t == "hydro" ~ "hydro",
  t %in% c("Gen_II_LWR", "large reactor", "SMR") ~ "nuclear", t == "geothermal" ~ "geothermal",
  str_detect(t, "^wind") ~ "wind", str_detect(t, "PV|CSP") ~ "solar", TRUE ~ "other")
fuel_levels <- c("coal", "oil", "gas", "biomass", "hydro", "nuclear", "geothermal", "wind", "solar")   # bottom -> top

load_scenario <- function(spot_csv, elec_csv, label) {
  b <- read_batch(spot_csv)
  pop <- b[["population by region"]] %>% group_by(year) %>% summarise(pop_bn = sum(value) / 1e6)
  gdp <- b[["GDP MER by region"]] %>% group_by(year) %>% summarise(gdp_trn = sum(value) / 1e6)     # million 1990$ -> trn
  pe  <- b[["primary energy consumption by region (direct equivalent)"]] %>%
    mutate(fuel = fuel_map[fuel]) %>% filter(!is.na(fuel)) %>% group_by(year, fuel) %>% summarise(EJ = sum(value), .groups = "drop")
  co2 <- b[["CO2 emissions by region"]] %>% group_by(year) %>% summarise(co2_gt = sum(value) * 44 / 12 / 1000)
  kaya <- pop %>% inner_join(gdp, "year") %>% inner_join(pe %>% group_by(year) %>% summarise(pe_EJ = sum(EJ)), "year") %>%
    inner_join(co2, "year") %>%
    mutate(gdp_per_cap = gdp_trn * 1e3 / pop_bn,             # thousand 1990$ per person
           energy_int = pe_EJ / gdp_trn,                      # EJ per trn 1990$
           carbon_int = co2_gt * 1e3 / pe_EJ,                 # MtCO2 per EJ
           scenario = label)
  e <- read_batch(elec_csv)[[1]] %>% mutate(fuel = tech_map(technology)) %>% filter(fuel != "other") %>%
    group_by(year, fuel) %>% summarise(EJ = sum(value), .groups = "drop") %>% mutate(scenario = label)
  list(kaya = kaya, pe = pe %>% mutate(scenario = label), elec = e)
}

# Climate outputs. CO2 concentration, total forcing and surface temperature come from the
# database (ClimateQuery, annual). Sea level rise is not written to the database, only to
# Hector's output stream CSV; GCAM re-runs Hector from spin-up every period, so the stream
# holds one trajectory per period and the LAST row for each year is the finished run.
load_climate <- function(clim_csv, hector_csv, label) {
  b <- read_batch(clim_csv, drop2020 = FALSE)
  pick <- function(title, name) if (!is.null(b[[title]])) b[[title]] %>% transmute(year, metric = name, value)
  out <- bind_rows(pick("CO2 concentrations", "CO2 concentration (ppm)"),
                   pick("total climate forcing", "Total radiative forcing (W/m2)"),
                   pick("global mean temperature", "Global mean surface temperature (degC vs 1850-1900)"))
  if (!is.null(hector_csv) && file.exists(hector_csv)) {
    h <- read_csv(hector_csv, comment = "#", show_col_types = FALSE, progress = FALSE) %>%
      filter(spinup == 0, component == "slr", variable == "slr") %>%
      mutate(row = row_number()) %>% arrange(desc(row)) %>% distinct(year, .keep_all = TRUE) %>%
      transmute(year, metric = "Sea level rise (cm vs 1990)", value)
    h <- h %>% mutate(value = value - h$value[h$year == 1990][1])
    out <- bind_rows(out, h)
  }
  out %>% filter(year >= 1976) %>% mutate(scenario = label)
}

# Non-CO2 (AR5 GWP100) and CO2 sequestration, for the net-GHG balance and removals panels.
gwp_ar5 <- c(CH4 = 28, CH4_AGR = 28, CH4_AWB = 28, N2O = 265, N2O_AGR = 265, N2O_AWB = 265,
             HFC23 = 12400, HFC32 = 677, HFC125 = 3170, HFC134a = 1300, HFC143a = 4800, HFC152a = 138,
             HFC227ea = 3350, HFC236fa = 8060, HFC245fa = 858, HFC365mfc = 804, HFC43 = 1650,
             SF6 = 23500, CF4 = 6630, C2F6 = 11100)
load_nonco2 <- function(csv, label) {                       # CH4/N2O in Tg, F-gases in Gg -> GtCO2e
  read_batch(csv)[["nonCO2 emissions by region"]] %>% filter(GHG %in% names(gwp_ar5)) %>%
    mutate(w = gwp_ar5[GHG] / ifelse(grepl("^(CH4|N2O)", GHG), 1, 1000),
           group = case_when(grepl("^CH4", GHG) ~ "CH4", grepl("^N2O", GHG) ~ "N2O", TRUE ~ "F-gases")) %>%
    group_by(year, group) %>% summarise(gt = sum(value * w) / 1e3, .groups = "drop") %>% mutate(scenario = label)
}
load_seq <- function(csv, label) {                          # MtC -> GtCO2
  read_batch(csv)[["CO2 sequestration by sector"]] %>%
    mutate(sector = case_when(grepl("elec", sector) ~ "electricity", grepl("H2|hydrogen", sector) ~ "hydrogen",
                              grepl("refining|liquids", sector) ~ "liquids", grepl("feedstock", sector) ~ "feedstocks (non-energy)",
                              grepl("cement|iron|steel|chemical|alumin|industr|N fertil", sector) ~ "industry", grepl("DAC|CO2 removal|air", sector) ~ "DAC",
                              TRUE ~ "other")) %>%
    group_by(year, sector) %>% summarise(gt = sum(value) * 44 / 12 / 1e3, .groups = "drop") %>% mutate(scenario = label)
}
