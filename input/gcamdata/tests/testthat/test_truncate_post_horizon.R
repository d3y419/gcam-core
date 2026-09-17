# Decision table for truncate_post_horizon under an extended horizon. See the
# comments on modeltime.XML_POST2100_ALLOWED and modeltime.XML_POST2100_TRUNCATE_HEADERS.
context("truncate_post_horizon")

# The horizon flag is off by default. These tests turn it on in the loaded namespace
# for their own duration, with the extended MODEL_FUTURE_YEARS the flag would produce,
# so they exercise the extended-horizon paths regardless of the build setting.
with_extended_horizon <- function() {
  ns <- asNamespace("gcamdata")
  set_const <- function(name, value) {
    was_locked <- bindingIsLocked(name, ns)
    if(was_locked) unlockBinding(name, ns)
    old <- get(name, envir = ns)
    assign(name, value, envir = ns)
    if(was_locked) lockBinding(name, ns)
    withr::defer({
      if(was_locked) unlockBinding(name, ns)
      assign(name, old, envir = ns)
      if(was_locked) lockBinding(name, ns)
    }, envir = parent.frame(3))
  }
  set_const("modeltime.EXTEND_HORIZON", TRUE)
  set_const("MODEL_FUTURE_YEARS", c(seq(2025, 2100, 5), seq(2110, 2200, 10), seq(2220, 2300, 20)))
}


test_that("only technology-period tables are truncated past the standard horizon", {
  with_extended_horizon()
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

test_that("resource rate tables are zeroed past the standard horizon", {
  with_extended_horizon()
  d <- tibble::tibble(region = c("USA", "USA", "China"), resource = "crude oil", subresource = "crude oil",
                      year.fillout = c(1975L, 2005L, 2005L), techChange = c(0.005, 0.0075, 0.0075))
  later <- c(seq(2110, 2200, 10), seq(2220, 2300, 20))  # the extended horizon's post-2100 model years
  z <- zero_rates_post_horizon(d, "RsrcTechChange")
  expect_equal(nrow(z), nrow(d) + 2 * length(later))
  expect_true(all(z$techChange[z$year.fillout > modeltime.STANDARD_HORIZON_END] == 0))
  expect_identical(z[z$year.fillout <= modeltime.STANDARD_HORIZON_END, ], d)
  # levels are left alone
  expect_identical(zero_rates_post_horizon(d, "GrdRenewRsrcMaxNoFillOut"), d)
})
