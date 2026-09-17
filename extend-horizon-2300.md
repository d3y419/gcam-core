# Extending GCAM to 2300 — feature prompt

What the 2300 horizon needs from the data system and the model, and what was
learned making it work. Read alongside `gcamontology.md`; this file is specific to
the horizon feature and lives with the feature, not in the ontology.

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
