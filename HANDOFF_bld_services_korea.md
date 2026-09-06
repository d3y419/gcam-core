# Handoff — South Korea detailed building services (`K1442`)

**Branch:** `hcm/proj/bld_services_korea`, branched from `hcm/proj/bld_lifetime_korea` @ `49dc98eaa`.
**Status:** incomplete. Data pipeline works and conserves energy exactly; the model runs but the
result has not been validated, and there is an unresolved question about whether the solve
comparisons made so far mean anything at all (see "The trap" below — read it first).

---

## Goal

South Korea lumps all non-thermal building energy into two aggregate services, `comm others` and
`resid others modern_dN`. The USA region resolves ~20 distinct services. That lump is the
**largest** single piece of South Korea's building energy — 0.96 EJ of service output in 2021,
against 0.49 for heating and 0.17 for cooling — so leaving it aggregated blocks any end-use
analysis. It also suppresses internal gains, which are defined per detailed service
(`L244.StubTechIntGainOutputRatio`) and feed back into heating and cooling load, meaning the
heating/cooling results from branch 1 are not final until this lands.

Batch 1 scope (user-specified): **commercial** cooking, hot water, lighting, refrigeration, other;
**residential** cooking, freezers, hot water, lighting, other, refrigerators.

Deferred to batch 2: comm ventilation / office / non-building; resid televisions, computers,
clothes washers, clothes dryers, dishwashers, furnace fans.

---

## What exists

- `input/gcamdata/R/zenergy_K1442.building_serv_KOR.R` — the chunk
- `input/gcamdata/R/zenergy_xml_building_serv_KOR.R` — the XML writer, produces `building_serv_KOR.xml`
- `exe/configuration_ref.xml` — scenario component added, **loaded after** `korea_bld_retirement_scurve.xml` (order matters, see below)

**Energy conservation is exact** — 0.0000% difference against South Korea's original `others`
calibration in every base year and every fuel. This is the one thing that is solidly verified.
Re-check it with the same method after any change: compare
`sum(K1442.StubTechCalInput_bld_KOR)` against the original `L244.StubTechCalInput_bld` rows for
`comm others` + `resid others modern_dN`, per year and per subsector.

**Design.** Structure is copied from the USA region's own rows (sectors, logits, share-weights,
efficiencies, internal-gain ratios) and re-labelled to South Korea; quantities are South Korea's.
Energy is allocated to each detailed service using USA's service composition by consumer and fuel,
resolved all the way down to individual technologies. Coverage of the `others` energy: 100% of
commercial gas, ~97% of residential gas, ~75% of residential electricity, ~53% of commercial
electricity; the uncovered remainder legitimately stays in `others`.

---

## Four traps already paid for — do not rediscover these

1. **USA's detailed services use named equipment technologies with efficiency tiers**
   (`electric heat pump water heater`, `fluorescent`, `refrigerator hi-eff`, `gas range`), *not*
   fuel names. Only `resid other` / `comm other` use plain fuel names. Allocating South Korea's
   fuel-named energy onto a USA sector without mapping the technology name gives
   `ERROR: Could not find global technology for sector ... technology: electricity`. The chunk now
   resolves service and technology in one step.

2. **An emptied subsector must be deleted whole.** Batch 1 covers 100% of commercial gas, so
   `comm others / gas` and `/ refined liquids` fall to exactly zero. Leaving zeroed technologies in
   place produces thousands of `Mixed calibrated and variable children or read a zero calibration
   value` warnings. But deleting every technology in a subsector individually leaves an **empty
   subsector and GCAM segfaults during initialisation with nothing written to `main_log`**. The
   chunk emits `DeleteSubsector` when a subsector loses all technologies and `DeleteStubTech`
   only when it is partially emptied (`comm others / gas` keeps `hydrogen`, so that one is
   per-technology). Authoritative technology list comes from `L244.StubTech_bld`, not the
   calibration table — a technology can exist without a calibration row.

3. **Load order.** `input/extra/korea_bld_retirement_scurve.xml` references `comm others`
   technologies and would resurrect anything deleted. `building_serv_KOR.xml` must load **after**
   it. Already done in `configuration_ref.xml`; preserve this if you touch the config.

4. **`GenericShares` is not an XML table** — no ModelInterface header exists and core never writes
   it. It is an internal `L244` intermediate. Writing it produces
   `***Warning: skipping table: GenericShares!***`.

Also: `dplyr::if_else` requires condition and branches to be the same length, so
`if_else(sum(x) > 0, x/sum(x), 0)` inside a grouped mutate fails — use an elementwise guard.

---

## The trap — read before trusting any solve comparison

Substantial time was lost chasing a "global solve instability" (a dozen regions' gas and coal
markets failing) attributed to this work. It was investigated through four hypotheses — residential
bias adder, satiation floor, zero-calibration husks, missing demand tables — **all four wrong**.

The control run, with `building_serv_KOR.xml` disabled entirely, reproduced the failures. And the
already-committed baseline (`49dc98eaa`) itself fails 13 markets at period 2 and 10 at period 3.
The regression was mostly pre-existing and had been mis-recorded as "~4 markets" by counting a
solver listing that ended in `...(truncated)`.

Completed-run counts:

| run | p1 | p2 | p3 | p4 | p5 |
|---|---|---|---|---|---|
| committed baseline (2100 run) | OK | 13 | 10 | 5 | 2 |
| control — services disabled | 18 | 22 | 21 | 12 | 6 |
| 11 services enabled | 22 | 22 | 20 | 17 | 10 |

Note the control is already far worse than the baseline **with the services switched off**, while
the only XML difference between them is the disabled file. That is not explicable by this work.
The open suspicion is **nondeterminism**: `max-parallelism = -1` in the config, another GCAM job
competing for CPU on the same machine, and every failing market sitting at ~0.2-1% RED right at
tolerance, so parallel summation order can flip markets between pass and fail. A rerun of the
identical config was launched to test this and did not finish.

**Do this first:** run the same config twice unchanged and compare failure counts. If they differ,
every comparison above is noise and should be discarded; set `max-parallelism = 1` before drawing
any conclusion about solve quality. The user's instruction was that solve failures are **not** to
be fixed as part of this work.

Two further evidence rules learned the hard way: `grep`/`Read` on a running GCAM log returns a
stale view while `tail -f` sees live content, so a period's failure block often is not yet written;
and only judge a period after the run has moved *past* it.

---

## Known incomplete

- **Not validated.** No check has been made that the detailed services produce sensible output —
  only that the input data conserves energy. Query the new sectors' `physical-output` and compare
  the sum against the original aggregate.
- **Service output is intentionally not conserved** even though energy is: detailed services carry
  their own efficiencies rather than the lumped `others` efficiency, so service is recomputed as
  energy x efficiency. That is the point of resolving them, but it should be sanity-checked.
- **Batch-wise splitting leaves a hybrid.** The user's explicit direction is *"don't try to keep
  korean tech, mostly replace with usa tech"*. Because batch 1 covers only 11 of ~20 services,
  `others` survives holding the remainder with Korea-native fuel technologies — exactly the
  half-replaced state to avoid. Covering all services at once makes `resid others modern_dN`
  disappear entirely, as it does in USA. Consider doing that rather than continuing batch-wise.
- **Demand-side parameters borrowed vs derived.** `GenericServicePrice`, `GenericBaseDens` and
  `GenericServiceAdder` are derived from South Korea's own `comm others` values (price inherited,
  the extensive ones split by base-service share). Satiation, impedance and coef are USA values
  attached to Korea's nodes — consistent with core, which computes generic-service satiation from
  USA data and reads it to all regions "because they're all the same". The satiation floor
  `pmax(satiation.level, service.per.flsp * 1.0001)` that core applies is replicated.
  `L244.GompFnParam` and `L244.Floorspace` do exist for South Korea if a proper bias-adder
  calculation is wanted instead of the proportional split.
- **USA service composition is a placeholder**, same class of assumption as the tier shares in
  `K1441`. Replace with KEEI / KOSIS / Korea Energy Agency end-use data when available. Note the
  user has accepted borrowing equipment *efficiency* across regions (globally traded equipment,
  shared manufacturers) but service *composition* is a stronger assumption.

---

## Context from branch 1 worth carrying

`K1441` (branch 1, now in PR #2) established the pattern this chunk follows. Two findings there
that generalise: input share-weights are never evidence — GCAM overwrites them via interpolation
rules with `overwrite-policy ALWAYS`, so verify from the output database; and gcamdata's
`final-calibration-year` / `end-year` keywords are recoded by `set_years()` on CSV read, so writing
them into XML makes GCAM segfault parsing them as integers — emit numeric years.
