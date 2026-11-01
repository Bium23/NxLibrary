#!/usr/bin/env python3
"""Usage: import_selene_palettes.py <selene-repo> <out.json>
Parses theme/Palettes/*.xaml from a Selene checkout into palettes.json (stdlib only)."""
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

X = "{http://schemas.microsoft.com/winfx/2006/xaml}Key"
COLOR_KEYS = {
    "focus": "SeleneFocusColor", "onFocus": "SeleneOnFocusColor", "ink": "SeleneInkColor",
    "scrim": "SeleneScrimColor", "glass": "SeleneGlassColor", "glyph": "GlyphColor",
    "success": "SeleneSuccessColor",
}


def rgb(text):
    m = re.fullmatch(r"#([0-9A-Fa-f]{2})?([0-9A-Fa-f]{6})", text.strip())
    if not m:
        raise ValueError(f"bad color {text!r}")
    return int(m.group(2), 16)


def parse(path):
    root = ET.parse(path).getroot()
    strings, colors, base = {}, {}, None
    for el in root:
        key = el.get(X)
        tag = el.tag.split("}")[-1]
        if tag == "String":
            strings[key] = (el.text or "").strip()
        elif tag == "Color":
            colors[key] = el.text
        elif tag in ("RadialGradientBrush", "LinearGradientBrush") and key == "SeleneBaseBrush":
            stops = [{"color": rgb(s.get("Color")), "location": float(s.get("Offset"))}
                     for s in el if s.tag.endswith("GradientStop")]
            base = {"kind": "radial" if tag.startswith("Radial") else "linear", "stops": stops}
    if base is None:
        raise ValueError(f"{path}: no SeleneBaseBrush gradient")
    out = {"id": strings["SeleneThemeId"], "name": strings["SeleneThemeName"],
           "mode": strings["SeleneThemeMode"]}
    for field, key in COLOR_KEYS.items():
        out[field] = rgb(colors[key])
    out["base"] = base
    return out


def main():
    repo, out = Path(sys.argv[1]), Path(sys.argv[2])
    files = sorted((repo / "theme" / "Palettes").glob("*.xaml"))
    palettes = [parse(f) for f in files]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(palettes, indent=2) + "\n")
    print(f"wrote {len(palettes)} palettes to {out}")


if __name__ == "__main__":
    main()
