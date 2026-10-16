#!/usr/bin/env python3
"""Adds German source strings to an .xcstrings catalog: add-strings.py <catalog> '{"key": "value"}'. Existing keys are kept."""
import json, sys

path, payload = sys.argv[1], json.loads(sys.argv[2])
catalog = json.load(open(path))
for key, value in payload.items():
    catalog["strings"].setdefault(key, {"extractionState": "manual", "localizations": {"de": {"stringUnit": {"state": "translated", "value": value}}}})
catalog["strings"] = dict(sorted(catalog["strings"].items()))
with open(path, "w") as handle:
    json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=False)
    handle.write("\n")
