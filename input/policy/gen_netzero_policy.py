"""Write input/policy/netzero_co2_2100_ghg_2200.xml: a CO2-only global cap for the 2300 horizon.

Cap (MtC, written in MtCO2 here): linear from a 40,000 MtCO2 anchor in 2025 (no constraint
is written for 2025 itself, see below) to 0 in 2100 - net-zero fossil + industrial CO2 -
then linearly more negative to 2200 and flat afterwards. The negative target is
    -min(CAP_FLOOR_MTCO2, residual non-CO2 of a net-zero run in that year)
so CO2 removals offset the residual non-CO2 (approximate net-zero GHG) but never go
below the floor. Residual non-CO2 = CH4 + N2O + HFCs + PFCs + SF6 weighted with AR5 GWP100
(IPCC AR5 WG1 Table 8.A.1, no climate-carbon feedback), read from the net-zero run's own
"nonCO2 emissions by region" query (usage: python gen_netzero_policy.py [nonco2.csv]).
Non-CO2 gases are not capped or linked, but their MAC curves respond to the CO2 price (GCAM default), so they are abated anyway. LUC CO2 is outside the cap (demand-adjust 0)
but sees a small share of the carbon price to keep deforestation in check.
"""
import csv, collections, re, sys
# Default source is the REFERENCE run: both net-zero proxy runs collapsed after 2170 (deep cap), so no
# usable net-zero non-CO2 exists yet. It does not matter for the cap: the AR5 residual (~27 GtCO2e)
# is far above CAP_FLOOR_MTCO2, so the floor binds either way. Pass a net-zero nonCO2 CSV as argv[1].
NONCO2_CSV = next((a for a in sys.argv[1:] if not a.startswith("--")), None) or r"C:\gcam\gcam-core9\output\nonco2_ref.csv"
OUT = r"C:\gcam\gcam-core9\input\policy\netzero_co2_2100_ghg_2200.xml"
TEMPLATE = r"C:\gcam\gcam-core9\input\policy\linked_ghg_policy.xml"   # region list only
CAP_2025_MTCO2 = 40000.0       # ~ reference 2025 fossil+industrial CO2 (40.0 Gt); ramp anchor only
CAP_FLOOR_MTCO2 = 10000.0      # cap never below -10 GtCO2 (user choice; the 1 %-of-GDP negative-
                               # emissions budget could not pay for -15 Gt: CO2 price 3564 $/tC, 2170 unsolved)
# Post-2100 instrument (user 2026-09-18): a quantity cap gives a saw-tooth CO2 price (654 -> 498 -> 931 -> 605
# $/tC) because the tightening rate changes at 2100 and 2200, and fossil fuels creep back at each relief.
# Instead: cap to 2100 (net-zero CO2), then a FIXED TAX rising linearly from the 2100 solved price
# (--p2100, read from a stop-year-2100 run) to TAX_2300 in 2300. GHGPolicy uses the constraint where
# present and the fixed tax elsewhere; tax years between 2110 and 2300 are written explicitly.
# Without --p2100 the file carries the cap only (stage 1). Units: GCAM native 1990$/tC.
TAX_2300 = 490.0               # FINAL (2026-09-18): net GHG -0.5 (2190), -1.5 (2200), -1.2..-1.5 flat to 2300; no positive
                               # period after the crossing (acceptance rule). Iteration 3: 460 -> net GHG -0.4 (2200), 0.0 (2220), then
                               # +0.4/+0.3/+0.5/+0.9 (2240-2300): DAC recedes 5.6 -> 2.0 Gt at a near-flat price, so the
                               # response is non-linear (560 -> -6.8; 460 -> +0.9). Iteration 4: 490 (predicted ~ -1.4).
                               # History: Iteration 1: 800 held from 2260 gave net GHG -5.6 (2200),
                               # -13 (2260), -18.8 (2300). Iteration 2: 560 linear -> net GHG -2.4 (2200), -6.4/-6.6/-6.8
                               # (2260/80/2300): flat tail achieved, level too low. Response ~0.05 GtCO2e per $/tC at 2300
                               # -> iteration 3: 460 (predicted ~-2 in 2300). Earlier note:
                               # -13 (2260), -18.8 (2300) and CO2 still falling at constant price (DAC learning);
                               # iteration 2: 560, linear to 2300, no plateau. Tune so net GHG (CO2 + AR5 non-CO2) is
                               # ~0 and flat by 2300 ("stable net-zero GHG by 2300", user 2026-09-18)
TAX_PLATEAU_YEAR = 2300        # linear rise 2100 -> TAX_PLATEAU_YEAR, then held (2300 = no plateau: at a flat 800 the
                               # removals kept growing 5 Gt in 40 yr, so a plateau does not give a flat tail anyway)
                               # leave net GHG trending down; the plateau gives the flat tail the target asks for
P2100 = None
for a in sys.argv[1:]:
    if a.startswith("--p2100="): P2100 = float(a.split("=")[1])
LUC_PRICE_ADJUST = 0.01        # TODO: arbitrary - GCAM's ghg_link_global.xml default; user asked for "a small price adjust"
C_PER_CO2 = 12.0 / 44.0
# AR5 GWP100. GCAM units: CH4, N2O in Tg (-> MtCO2e = Tg x GWP); F-gases in Gg (-> Gg x GWP / 1000).
GWP_AR5 = {"CH4": 28, "CH4_AGR": 28, "CH4_AWB": 28, "N2O": 265, "N2O_AGR": 265, "N2O_AWB": 265,
           "HFC23": 12400, "HFC32": 677, "HFC125": 3170, "HFC134a": 1300, "HFC143a": 4800, "HFC152a": 138,
           "HFC227ea": 3350, "HFC236fa": 8060, "HFC245fa": 858, "HFC365mfc": 804, "HFC43": 1650,   # HFC43 = HFC-43-10mee
           "SF6": 23500, "CF4": 6630, "C2F6": 11100}
WEIGHT = {g: (w if g.startswith(("CH4", "N2O")) else w / 1000.0) for g, w in GWP_AR5.items()}

rows = list(csv.reader(open(NONCO2_CSV, encoding="utf-8", errors="replace")))
h = rows[1]; gi = h.index("GHG"); yi = {int(c): i for i, c in enumerate(h) if c.strip().isdigit()}
nonco2 = collections.defaultdict(float); bygrp = collections.defaultdict(lambda: collections.defaultdict(float))
for r in rows[2:]:
    if len(r) < len(h) or r[gi] not in WEIGHT: continue
    grp = r[gi][:3] if r[gi][:3] in ("CH4", "N2O") else "F"
    for y, i in yi.items():
        try: v = float(r[i]) * WEIGHT[r[gi]]
        except ValueError: continue
        nonco2[y] += v; bygrp[grp][y] += v
print("residual non-CO2 from", NONCO2_CSV.split("\\")[-1], "(GtCO2e, AR5): year CH4 N2O F total")
for y in (2050, 2100, 2150, 2200, 2250, 2300):
    if y in nonco2: print("  %d %5.1f %5.1f %5.1f %6.1f" % (y, bygrp["CH4"][y] / 1e3, bygrp["N2O"][y] / 1e3, bygrp["F"][y] / 1e3, nonco2[y] / 1e3))

# 2025 gets NO constraint: a cap that only grazes reference emissions (40.0 vs 40.0 Gt) left the
# CO2 market degenerate (slack cap, price stuck at 18 $/tC) and 1,037 markets unsolved. The
# first written cap is 2030 (37,333 MtCO2, 9% below the 41.1 Gt reference), which binds cleanly.
p1 = list(range(2030, 2101, 5)); p2 = list(range(2110, 2201, 10)); p3 = [2220, 2240, 2260, 2280, 2300]
target = lambda y: -min(CAP_FLOOR_MTCO2, nonco2[y])
cap = {y: CAP_2025_MTCO2 * (2100 - y) / 75.0 for y in p1}                     # MtCO2, -> 0 at 2100
# 2100 is written as -10 MtCO2, not 0: with a constraint of exactly 0 the solver's relative excess
# demand is 100 % for any residual (-0.0017 MtC was reported as 'unsolved'); -10 Mt is net-zero
# within 0.03 % of today's emissions and gives the market a finite target.
cap[2100] = -10.0
cap.update({y: target(2200) * (y - 2100) / 100.0 for y in p2})                 # 0 -> target(2200)
cap.update({y: target(y) for y in p3})                                          # hold
regions = sorted(set(re.findall(r'<region name="([^"]+)">', open(TEMPLATE, encoding="utf-8").read())))
out = ['<?xml version="1.0" encoding="UTF-8"?>', '<scenario>', '  <world>']
for reg in regions:
    out.append('    <region name="%s">' % reg)
    out.append('      <ghgpolicy name="CO2"><market>global</market>')
    for y in p1:
        out.append('        <constraint year="%d">%.1f</constraint>' % (y, cap[y] * C_PER_CO2))
    if P2100 is not None:
        for y in p2 + p3:
            out.append('        <fixedTax year="%d">%.2f</fixedTax>' % (y, P2100 + (TAX_2300 - P2100) * min(1.0, (y - 2100) / float(TAX_PLATEAU_YEAR - 2100))))
    out.append('      </ghgpolicy>')
    out.append('      <linked-ghg-policy name="CO2_FUG"><price-adjust fillout="1" year="1975">1</price-adjust><demand-adjust fillout="1" year="1975">1</demand-adjust><market>global</market><linked-policy>CO2</linked-policy><price-unit>1990$/tC</price-unit><output-unit>MtC</output-unit></linked-ghg-policy>')
    out.append('      <linked-ghg-policy name="CO2_LUC"><price-adjust fillout="1" year="1975">%s</price-adjust><demand-adjust fillout="1" year="1975">0</demand-adjust><market>global</market><linked-policy>CO2</linked-policy><price-unit>1990$/tC</price-unit><output-unit>MtC</output-unit></linked-ghg-policy>' % LUC_PRICE_ADJUST)
    out.append('    </region>')
out += ['  </world>', '</scenario>', '']
open(OUT, "w", encoding="utf-8").write("\n".join(out))
print("wrote", OUT, "regions:", len(regions))
print("cap path (MtCO2):", " ".join("%d:%.0f" % (y, cap[y]) for y in [2030, 2050, 2075, 2100]))
print("post-2100:", "cap only (stage 1)" if P2100 is None else "fixed tax %.0f (2100) -> %.0f (%d), held to 2300, 1990$/tC" % (P2100, TAX_2300, TAX_PLATEAU_YEAR))
