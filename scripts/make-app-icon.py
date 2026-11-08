#!/usr/bin/env python3
"""Generates the app icons: one per palette set (spec 66).

Every icon is the same design (spec 23): a centered circle on a flat
background, in two colors of its set, both read from App/Game/PaletteSets.swift
(each set's `colors` and its `icon` pair of indices into them).
The default set, the first one there, gets the primary icon (AppIcon); every
other set an alternate one, AppIcon-<set id>, which the app switches to along
with the set (App/Game/HomeScreenIcon.swift). Set colors are Display P3 coordinates, so the
PNGs carry the Display P3 profile and show exactly the colors of the bubbles.

Re-run after adding a set or changing its colors or icon pair. A set without
an icon pair stops the script; an alternate icon left over from a removed set
is deleted. The app draws the same icons itself in the sets sheet
(App/UI/AppIconView.swift), so keep the geometry here and there alike.
"""

import json
import re
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SETS_SOURCE = ROOT / "App" / "Game" / "PaletteSets.swift"
ASSETS = ROOT / "App" / "Assets.xcassets"
DISPLAY_P3_PROFILE = Path("/System/Library/ColorSync/Profiles/Display P3.icc")

# Canvas.
FINAL_SIZE = 1024
SUPERSAMPLE_FACTOR = 4
DRAW_SIZE = FINAL_SIZE * SUPERSAMPLE_FACTOR

# Circle geometry, expressed at final (1024x1024) scale.
CIRCLE_CENTER = (512, 512)
CIRCLE_DIAMETER = 672
CIRCLE_RADIUS = CIRCLE_DIAMETER / 2


def read_sets() -> dict:
    """Set id -> (six 0xRRGGBB colors, (background index, circle index)), in
    declaration order: the default set first."""
    text = SETS_SOURCE.read_text()
    sets = {}
    pattern = (
        r'id: "([^"]+)".*?colors: \[([^\]]+)\]'
        r'(?:,\s*(?://[^\n]*\s*)?icon: \.init\(background: (\d+), circle: (\d+)\))?'
    )
    for match in re.finditer(pattern, text, re.S):
        set_id = match.group(1)
        if match.group(3) is None:
            sys.exit(f"No icon pair for {set_id} in {SETS_SOURCE}")
        colors = [int(value, 16) for value in re.findall(r"0x([0-9A-Fa-f]{6})", match.group(2))]
        sets[set_id] = (colors, (int(match.group(3)), int(match.group(4))))
    if not sets:
        sys.exit(f"No sets found in {SETS_SOURCE}")
    return sets


def rgb(hex_value: int) -> tuple:
    return (hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF


def draw_icon(background: int, circle: int) -> Image.Image:
    scale = SUPERSAMPLE_FACTOR
    center = (CIRCLE_CENTER[0] * scale, CIRCLE_CENTER[1] * scale)
    radius = CIRCLE_RADIUS * scale

    image = Image.new("RGB", (DRAW_SIZE, DRAW_SIZE), rgb(background))
    draw = ImageDraw.Draw(image)
    bbox = (
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    )
    draw.ellipse(bbox, fill=rgb(circle))
    return image.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)


def write_icon_set(name: str, image: Image.Image, profile: bytes) -> Path:
    folder = ASSETS / f"{name}.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    filename = f"{name}-1024.png"
    image.save(folder / filename, icc_profile=profile, optimize=True)
    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")
    return folder / filename


def main() -> None:
    sets = read_sets()
    profile = DISPLAY_P3_PROFILE.read_bytes()

    primary = next(iter(sets))
    names = set()
    for set_id, (colors, (background, circle)) in sets.items():
        name = "AppIcon" if set_id == primary else f"AppIcon-{set_id}"
        names.add(name)
        path = write_icon_set(name, draw_icon(colors[background], colors[circle]), profile)
        print(f"{set_id:12} #{colors[circle]:06X} on #{colors[background]:06X} -> {path.relative_to(ROOT)}")

    for folder in ASSETS.glob("AppIcon-*.appiconset"):
        if folder.name.removesuffix(".appiconset") not in names:
            shutil.rmtree(folder)
            print(f"removed {folder.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
