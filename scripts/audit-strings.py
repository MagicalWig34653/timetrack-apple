#!/usr/bin/env python3
"""Report xcstrings keys without a literal reference in Sources/ Swift files.

The report is a candidate list: runtime-composed keys and system-extracted strings
need manual review before removal.
"""
import json
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
source = "\n".join(path.read_text() for directory in (root / "Sources", root / "Packages") for path in directory.rglob("*.swift"))
literals = set(re.findall(r'"((?:[^"\\]|\\.)*)"', source))
dynamic_prefixes = set(re.findall(r'"([A-Za-z0-9_.-]+)\\\(', source))
dynamic_prefixes.update(re.findall(r'"([A-Za-z0-9_.-]+)"\s*\+\s*rawValue', source))
plural_bases = set(re.findall(r'PA\.plural\("([A-Za-z0-9_.-]+)"', source))
catalogs = sorted((root / "Sources").rglob("*.xcstrings"))
confirmed = {
    "ux3.now.open_today", "ux3.sheet.details", "wk.segment.list", "wk.segment.week",
    "today.delta", "today.of_target %@", "time.week_range %@ %@", "time.week_total %@ %@",
    "vacation.tile_adjustments", "vacation.tile_booked_text", "vacation.tile_carry_text",
    "vacation.tile_entitlement", "vacation.tile_planned_text", "vacation.tile_replaced",
    "vacation.tile_snapshot", "vacation.tile_snapshot_text %@",
}

for catalog in catalogs:
    data = json.loads(catalog.read_text())
    unused = []
    for key in data.get("strings", {}):
        # Interpolated localization keys contain a placeholder; Swift source has
        # an interpolation instead of the generated format token.
        prefix = re.split(r"%(?:\d+\$)?[@dlf]", key, maxsplit=1)[0]
        used = key in source or (prefix != key and prefix in source)
        used = used or any(key.startswith(value) for value in dynamic_prefixes)
        used = used or any(key in (value + ".one", value + ".other") for value in plural_bases)
        if key.startswith("wk."):
            short = key[3:]
            short_prefix = re.split(r"%(?:\d+\$)?[@dlf]", short, maxsplit=1)[0]
            used = used or f'"{short}"' in source or (short_prefix != short and short_prefix in source)
            used = used or any(short.startswith(value) for value in dynamic_prefixes)
            # W.s receives a selected string in a few conditional expressions.
            used = used or short in literals and short.startswith(("plan.", "sum.", "days."))
        if not used:
            unused.append(key)
    if unused:
        print(f"{catalog.relative_to(root)} ({len(unused)} candidates)")
        for key in unused:
            print(f"  {key}")
    if "--prune-confirmed" in sys.argv or "--prune-unused" in sys.argv:
        removed = set(unused) if "--prune-unused" in sys.argv else confirmed.intersection(unused)
        for key in removed:
            del data["strings"][key]
        if removed:
            catalog.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
