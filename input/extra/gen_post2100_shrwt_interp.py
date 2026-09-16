"""Generate post2100_shrwt_interp.xml, a share-weight rule for every global technology.

gcamdata writes no technology data past 2100 (see truncate_post_horizon in
input/gcamdata/R/xml.R) and GCAM clones the last vintage forward, inputs included.
Cloning does not populate techShareWeights, though - that is a separate PeriodVector
fed only by parsed values and interpolation rules - so a technology with no explicit
rule has no share-weight past 2100 and TechnologyContainer::interpolateShareWeights
aborts with "Found uninitialized share weight".

A 'fixed' interpolation rule from 2100 to the horizon end fills them from the 2100
value without creating a parsed period, so the vintage clone and its complete input
set are left intact. Rules fill share-weights; cloning fills the technology.

Reads the built XML in input/gcamdata/xml, so run it after the data system. Writes
input/extra/post2100_shrwt_interp.xml, which is deliberately untracked - it is a
derived artifact, regenerate it rather than committing it.

    python input/extra/gen_post2100_shrwt_interp.py [to_year]
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # <workspace>
XML = os.path.join(ROOT, "input", "gcamdata", "xml")
OUT = os.path.join(HERE, "post2100_shrwt_interp.xml")
FROM_YEAR = "2100"
TO_YEAR = sys.argv[1] if len(sys.argv) > 1 else "2300"

RULE = ('<interpolation-rule apply-to="share-weight" from-year="%s" to-year="%s">'
        '<interpolation-function name="fixed"/></interpolation-rule>' % (FROM_YEAR, TO_YEAR))

TECH = r'(?:technology|intermittent-technology|tranTechnology)'
loc_re = re.compile(r'<location-info sector-name="([^"]*)" subsector-name="([^"]*)">(.*?)</location-info>', re.S)
tech_re = re.compile(r'<%s name="([^"]*)">(.*?)</%s>' % (TECH, TECH), re.S)

glob_tech = {}   # sector -> subsector -> set(technology)

for f in sorted(glob.glob(os.path.join(XML, "*.xml"))):
    try:
        src = open(f, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    if "global-technology-database" not in src:
        continue
    for m in loc_re.finditer(src):
        sec, sub, body = m.group(1), m.group(2), m.group(3)
        for tm in tech_re.finditer(body):
            tname, tbody = tm.group(1), tm.group(2)
            # Only technologies that carry a parsed share-weight at the from-year.
            # A 'fixed' rule interpolates FROM that value, and
            # InterpolationRule::applyInterpolations aborts with "Could not find a
            # value to interpolate from" when it is absent.
            pm = re.search(r'<period year="%s">(.*?)</period>' % FROM_YEAR, tbody, re.S)
            if pm and "<share-weight>" in pm.group(1):
                glob_tech.setdefault(sec, {}).setdefault(sub, set()).add(tname)

n = sum(len(t) for s in glob_tech.values() for t in s.values())
print("global technologies with a %s share-weight: %d across %d sectors" % (FROM_YEAR, n, len(glob_tech)))

parts = ['<?xml version="1.0" encoding="UTF-8"?>', "<scenario>", "  <world>",
         "    <global-technology-database>"]
for sec in sorted(glob_tech):
    for sub in sorted(glob_tech[sec]):
        parts.append('      <location-info sector-name="%s" subsector-name="%s">' % (sec, sub))
        for t in sorted(glob_tech[sec][sub]):
            parts.append('        <technology name="%s">%s</technology>' % (t, RULE))
        parts.append("      </location-info>")
parts += ["    </global-technology-database>", "  </world>", "</scenario>", ""]

with open(OUT, "w", encoding="utf-8") as fh:
    fh.write("\n".join(parts))
print("wrote %s (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1048576.0))
