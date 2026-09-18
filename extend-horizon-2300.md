# Extending GCAM to 2300 — feature prompt

What the 2300 horizon needs from the data system and the model, and what was
learned making it work. Read alongside `gcamontology.md`; this file is specific to
the horizon feature and lives with the feature, not in the ontology.

## Building it

`modeltime.EXTEND_HORIZON` is **off by default**; a default build is byte-identical to
one without the feature. Set `GCAM_EXTEND_HORIZON=TRUE` in the environment before
loading gcamdata (`Sys.setenv(GCAM_EXTEND_HORIZON = "TRUE")`, or `.Renviron`) to build
the 2300 horizon. Then regenerate `input/extra/post2100_shrwt_interp.xml` from the
built XML and run with a configuration that lists it.

## Design

- Model periods stay dense: 5-year steps to 2100, 10-year 2100–2200, 20-year
  2200–2300 (`MODEL_FUTURE_YEARS`, gated by `modeltime.EXTEND_HORIZON`).
- Only exogenous drivers extend: population and GDP from RFF-SP matched percentiles
  (`post2100_socioeconomics.csv`, growth ratios relative to 2100), assumptions held
  flat past 2100 (`extend_horizon_assumptions`, `approx_fun(extend_horizon=)`).
  Resource depletion is endogenous — nothing is written for it.
- Technologies are not written past 2100. GCAM clones the last parsed vintage
  forward (`TechnologyContainer::interpolateVintage`), inputs and outputs included.
  Share-weights are not part of the clone, so `input/extra/post2100_shrwt_interp.xml`
  (regenerate with `input/extra/gen_post2100_shrwt_interp.py`) gives every global
  technology a `fixed` share-weight rule from 2100 to 2300.

## The truncation rule (`truncate_post_horizon`, `xml.R`)

GCAM clones technologies forward and fills nothing else. That fixes what may and
may not be written past 2100:

1. A table whose ModelInterface header creates a technology vintage (a
   `{year}period` step — 190 headers, all under technology-type parents) is
   truncated at 2100. Any parsed post-2100 `<period>`, however little it holds,
   pre-empts the clone: the vintage is built from that fragment alone.
2. Every other per-year table (60 headers: population, national accounts, resource
   maxima, land ghost shares, elasticities, constraints, subsector share-weights) is
   written to 2300. Left unparsed, those `PeriodVector`s read as zero — bioenergy
   land collapsed and basins ran dry when they were truncated.
3. Files in `modeltime.XML_POST2100_ALLOWED` keep even their technology periods
   (complete definitions: `ag_storage` lifetimes, macro labour technologies).
4. `modeltime.XML_POST2100_TRUNCATE_HEADERS` truncates an adjustment table even
   inside an allowed file (`GlobalTechAccountOutputUseBasePrice`, which wrote 8,670
   bare periods into the global technology database from `socioeconomics_macro.xml`).
5. `add_xml_data_generate_levels` passes `"<header>,<command>"`; decide on the base
   name. An unknown header is truncated, with a one-time warning.
6. **No trend past 2100** (`zero_rates_post_horizon`,
   `modeltime.XML_POST2100_ZERO_RATE_HEADERS`): resource `techChange` is written with
   `fillout` at its last specified year (2005 for fossil reserves: 0.75 %/yr oil and
   gas, 0.5 %/yr coal) and would compound for two extra centuries while cloned
   technology costs stay frozen. Explicit zero rows at every model year past 2100
   override the fillout. Levels are held; only listed rates are zeroed.
   *Not covered:* rates inside technology periods ride the clone — `agProdChange` is
   already 0 at 2100 in the data; MAC-curve `tech-change` (`fillout` at 2030,
   0.17–0.25 %/yr) is not, and keeps compounding.

## Failure signatures and what they mean

- **Thousands of `does not have a matching input in the next period` at the first
  post-2100 period, then `input-driver could not find input`** — a parsed period
  pre-empted the clone. Find it per file, one year at a time:
  `grep -lE '<period[^>]*year="2110"' *.xml` (a range like `2[1-3][0-9]0` also matches
  2100). Never the C++.
- **Broad non-solve at 2110 led by `biomass` and crop markets, water withdrawals
  with zero supply** — a per-year non-technology table was truncated. Check
  `maxSubResource`, `ghost-unnormalized-share`, elasticities reach 2300.
- **`Found uninitialized share weight`** — a cloned vintage with no share-weight
  rule; regenerate the share-weight override after any XML rebuild.

## Verification gates

- Calibration invariance: rebuild with `EXTEND_HORIZON = FALSE` into another
  `xmldir` and diff every XML ≤ 2100 (alignment-aware, year-attributed). Anything
  above 0.01 % before 2100 is a horizon-anchored ramp — three were found
  (`approx_fun` carry-forward vs `fill_exp_decay_extrapolate`, L2042 harvest index,
  L244 shell elasticity), all anchored on `max(MODEL_FUTURE_YEARS)`.
- Before swapping a rebuilt tree in: no leaked technology periods, exogenous data to
  2300, macro periods truncated, no NA/Inf past 2100.
- Any `driver()` call unlinks its `xmldir`; always build into an isolated one.

## Disproven — do not redo

- Carrying inputs forward in C++ (`FunctionUtils::copyInputParamsForward`).
- Finding the vintage creator by reading code; instrument `Technology::copy` with
  object addresses and list `mVintages` at `completeInit` entry instead.

## Net-zero scenario (`input/policy/netzero_co2_2100_ghg_2200.xml`)

CO2-only global cap (`ghgpolicy CO2`, MtC): anchored at 40,000 MtCO2 in 2025, linear to 0 in
2100, then linearly to minus the reference non-CO2 CO2e in 2200 (-21.2 Gt, SAR GWPs via the
demand-adjusts in `linked_ghg_policy.xml`), tracking -nonCO2_ref(t) to 2300. Non-CO2 gases are
neither capped nor priced (approximate net-zero GHG, by design). `CO2_FUG` linked 1/1;
`CO2_LUC` outside the cap (demand-adjust 0) with a small price-adjust 0.01 (TODO arbitrary).
Includes `negative_emissions_budget.xml`. Generator: `gen_netzero_policy.py` (scratchpad,
to be committed with the scenario). Runs from 1975: adding markets invalidates restart files.

**Lesson - never write a cap that only grazes the reference.** The first launch wrote a 2025
constraint of 40,000 MtCO2 against reference emissions of 39,958. The CO2 market went
degenerate (supply 10,909 > demand 10,783 MtC yet price stuck at 17.9 $/tC: demand is flat
near zero price and the solver cannot find the zero) and dragged 1,037 markets into a
Part-1 non-solve at 2025 with 3,189 iterations. Fix: omit the constraint for that year
(market unsolved, price 0) and let the first written cap bind clearly (2030: 37.3 vs 41.1 Gt,
-9%). Signature: `Tax, globalCO2` row in the unsolved list with supply > demand and a
positive price; hundreds of unrelated resource markets at 1-50% RED.

**Lesson - a net-negative cap collides with the negative-emissions budget.** The budget
(`negative_emissions_budget.xml`, `negative-emiss-budget-fraction` = 1 % of GDP, a single
scalar per region: supply = fraction x GDP) was slack until 2095, then bound from 2100 on as
the cap went negative. The CO2 price ran 653 $/tC (2100) -> 1198 (2150) -> 2272 (2160) ->
3564 (2170); at 2170 subsidy demand exceeded the budget by 13 % and 942 markets failed.
Fix for this scenario: `input/extra/neg_emiss_budget_fraction_5pct.xml` (generator next to
it; 0.05 is arbitrary, TODO). Unchanged before 2095 because the 1 % budget was slack there.
Read CO2/budget market prices per period from the debug XML (`<market name="globalCO2">`),
the main log only prints unsolved markets.

**Final design (user, 2026-09-17 23:40):** AR5 GWP100 for the residual non-CO2 (CH4 28,
N2O 265, all HFCs/PFCs/SF6), budget kept at 1 % of GDP, cap floor -10 GtCO2 (0 in 2100 ->
-10 Gt in 2200, flat after), residual non-CO2 taken from a net-zero run's own nonCO2 query
(`output/nonco2_nz.csv`), not the reference. Generator lives in
`input/policy/gen_netzero_policy.py`. The 5 %-budget run is only a proxy to harvest that
non-CO2 (its outputs kept as `*_b5.csv`, `summary_2300_b5.html`); its database is deleted.
Residual non-CO2 (reference, AR5) is ~27 GtCO2e in 2100-2300, so with the -10 Gt floor
net GHG stays ~+17 GtCO2e: "approximate" by design.

**Macro (KLEAM) off for the net-zero run (user, 2026-09-18).** Fixed-GDP mode keeps every
macro trial/tracking market (per-region TFP solve, `energy net export`, `energy service`,
`capital`) alive; they dominated the post-2100 failing lists. Off = comment out only
`<Value name="macro">socioeconomics_macro.xml`; keep `FixedGDP-Path=1` (the code aborts
otherwise) and KEEP `capital_Ag` (`ag_capital_tracking.xml`): it is a plain `Capital_Ag`
supply sector that `ag_input_laborcapital_IRR_MGMT.xml` feeds; removing it floods main_log
(742 MB by 1990) with "Called for price of non-existent market Capital_Ag". Solver for this
scenario: `input/solution/cal_broyden_config_2x.xml` (all iteration budgets doubled).
Second macro-off trap: `socioeconomics_CORE.xml` defines a `Labor_Materials` resource per
region whose only demand is the macro materials sector. Without macro it has supply and zero
demand; it is an *unsolvable* market, but `SolutionInfoSet::isAllSolved()` also requires
unsolvable markets to be cleared, so EVERY period is reported unsolved after exhausting the
full iteration budget (1990: 2004 iterations, Part 1 empty, Part 2 = 32 Labor_Materials).
Fix: `input/extra/delete_labor_materials.xml` (`<resource name="Labor_Materials" delete="1"/>`
per region), read after socioeconomics_CORE.xml. `Labor_Ag` is fine (ag/animal inputs demand it).
Third macro-off trap (the decisive one): every technology's capital cost is scaled by
`SectorUtils::calcPriceRatio()` of its tracking market (`capital-energy`, `capital-ag`,
`consumer durable`; ~155,000 `<tracking-market>` references), which the macro file links to the
solved `capital` market (price = interest rate; reference 0.12 in 2021 -> 0.087 (2050) -> 0.084
(2100) -> 0.049 (2300)). Without the market the ratio is 0/0 = NaN: calibration periods pass
(ratio forced to 1), 2030 never converges and main_log grows GBs of "non-existent market
capital-energy". So macro-on with fixed GDP is NOT results-neutral: the falling interest rate
cuts capital costs ~30 % by 2050 and ~60 % by 2300 relative to base-year financing.
Macro-off recipe = `input/extra/macro_off.xml` (delete Labor_Materials + fixed-price 0.1
ghgpolicy markets for the three tracking names -> ratio exactly 1) + drop the macro Value +
keep FixedGDP-Path=1 + keep capital_Ag. Compare macro-off only with macro-off: the reference
is re-run that way (`exe_ref/configuration_2300_ref_nomacro.xml`, DB
`database_basexdb_2300full_nomacro`, CSVs `*_ref_nomacro.csv`). Two gcam.exe in parallel need
separate working dirs (shared logs/ otherwise); `exe_ref/` holds a copy of gcam.exe + dlls +
XMLDBDriver + log_conf.

**Zero-cap artefact and its proper fix.** Solved = relative excess demand |ED|/max(|demand|, 1e-6)
< tolerance (0.001), unless |ED| < the absolute `solution-floor` (default 0.0001 in market units).
A cap of exactly 0 therefore reads 100 % unsolved for any residual (-0.0017 MtC at 2100). Two
fixes: write the cap as -10 MtCO2 (done in the generator), or set a per-market floor in the solver
config: `<solution-floor fillout="1" good="CO2" market-type="Tax" period="1">1</solution-floor>`
inside `<solution-info-param-parser>` (added to cal_broyden_config_2x.xml; effective from the next
run). No C++ change needed. The same ratio explains large % on near-zero trial-value markets
(energy net export).

**Scale-aware convergence rule (C++) - PINNED FOR LATER as a separate branch off master (user 2026-09-18). Patch saved at C:\gcam\patches\scale_aware_relative_ed.patch; source reverted on this branch.** `SolutionInfo::getRelativeED()`
now divides |ED| by `getScale()` = max(|D_t|, |S_t|, |D_{t-1}|, |S_{t-1}|) of the same market
(`mPeriod` set from `SolutionInfoSet::init`), instead of |D_t| alone. Removes the
small-denominator failure class (zero cap, phased-out fuel, balanced trade account) without
per-market floors. Trade-off: a market that shrinks 90 % in one period is judged against its
previous size, so a residual of 5 % of last period's volume counts as solved. Files:
solution_info.h/.cpp, solution_info_set.cpp. Built with `build_gcam_scale.bat` into
`exe/Release_scale/` (exe/gcam.exe is locked while a run is going); copy over after the run.
Validate: reference run must reproduce results within tolerance; net-zero 2100 with cap 0 solves.

**Net-zero v2 design (user, 2026-09-18 13:30).** Cap to 2100 (net-zero CO2), then a FIXED TAX rising
linearly from the solved 2100 price to a terminal value in 2300, chosen so that net GHG (CO2 + AR5
non-CO2) is near zero in 2300 - "a bit negative is fine, never positive". The point of the tax is
consistent, slowly increasing pressure 2100-2300 with no discontinuity, so coal/gas/oil never return
(the cap gave 654 -> 498 -> 931 -> 605 $/tC). 800 $/tC (1990$/tC) is only a first guess: iterate the
terminal value on stage-2 reruns (restart at 2110 from stage-1 files, ~40 min each) until net GHG 2300
is within ~1 Gt of zero. DAC SSP1 included in the scenario (idle in the reference).
