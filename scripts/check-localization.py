#!/usr/bin/env python3
"""Validate Chinese coverage and printf argument compatibility after upstream sync."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Thaw/Resources/Localizable.xcstrings"
TOKEN = re.compile(r"%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|[hlLzjtq])?([@diuoxXfFeEgGaAcCsSp%])")


def arguments(text):
    result = []
    implicit_index = 0
    for token in TOKEN.finditer(text):
        position, length, kind = token.groups()
        if kind == "%":
            result.append((0, "%"))
            continue
        implicit_index += 1
        result.append((int(position) if position else implicit_index, (length or "") + kind))
    return sorted(result)


def units(value):
    if isinstance(value, dict):
        if "stringUnit" in value:
            yield value["stringUnit"]
        for key, child in value.items():
            if key != "stringUnit":
                yield from units(child)


def main():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    errors = []
    checked = 0
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        translations = list(units(entry.get("localizations", {}).get("zh-Hans", {})))
        if not translations:
            errors.append(f"Missing zh-Hans: {key}")
        for unit in translations:
            checked += 1
            if unit.get("state") != "translated":
                errors.append(f"Unreviewed zh-Hans: {key}")
            if arguments(key) != arguments(unit.get("value", "")):
                errors.append(f"Format arguments differ: {key}")
    for error in errors:
        print(error)
    print(f"Checked {checked} Chinese string units; {len(errors)} error(s).")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
