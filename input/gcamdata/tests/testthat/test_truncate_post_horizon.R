# Decision table for truncate_post_horizon under an extended horizon. See the
# comments on modeltime.XML_POST2100_ALLOWED and modeltime.XML_POST2100_TRUNCATE_HEADERS.
context("truncate_post_horizon")

test_that("only technology-period tables are truncated past the standard horizon", {
  skip_if_not(modeltime.EXTEND_HORIZON, "horizon not extended")
  d <- tibble::tibble(region = "USA", year = c(2100L, 2110L, 2300L), value = 1:3)
  n <- function(file, header) nrow(truncate_post_horizon(d, file, header))

  # technology periods: truncated
  expect_equal(n("building_det.xml", "StubTechEff"), 1)
  # adjustment table inside an allowed file: truncated
  expect_equal(n("socioeconomics_macro.xml", "GlobalTechAccountOutputUseBasePrice"), 1)
  # complete technology definitions in an allowed file: kept
  expect_equal(n("ag_storage.xml", "FoodTech"), 3)
  # exogenous per-year quantities GCAM does not fill for itself: kept
  expect_equal(n("water_supply_constrained.xml", "GrdRenewRsrcMaxNoFillOut"), 3)
  expect_equal(n("land_input_4_IRR_MGMT.xml", "LN4_LeafGhostShare"), 3)
  expect_equal(n("building_agg.xml", "PriceElasticity"), 3)
  expect_equal(n("electricity.xml", "SubsectorShrwt"), 3)
  expect_equal(n("socioeconomics_CORE.xml", "Pop"), 3)
  # add_xml_data_generate_levels passes "<header>,<command>": decided on the base name
  expect_equal(n("ag_an_demand_input.xml", "StubCalorieContent,add_levels x"), 1)
  # unknown header: truncated, with a warning
  expect_warning(expect_equal(n("x.xml", "NotARealHeader"), 1))
})
