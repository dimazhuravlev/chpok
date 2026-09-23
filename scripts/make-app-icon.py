#!/usr/bin/env python3
"""Generates App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.

Flat terracotta background with a centered light-blue circle, using the same
palette as the in-game bubbles (see App/Game/Palette.swift). Re-run this
script whenever the palette changes.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# Output.
OUTPUT_PATH = (
    Path(__file__).resolve().parent.parent
    / "App"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon-1024.png"
)

# Canvas.
FINAL_SIZE = 1024
SUPERSAMPLE_FACTOR = 4
DRAW_SIZE = FINAL_SIZE * SUPERSAMPLE_FACTOR

# Colors (from the bubble palette).
BACKGROUND_COLOR = (0xB3, 0x63, 0x21)  # terracotta, #B36321
CIRCLE_COLOR = (0x22, 0xBD, 0xFF)  # light blue, #22BDFF

# Circle geometry, expressed at final (1024x1024) scale.
CIRCLE_CENTER = (512, 512)
CIRCLE_DIAMETER = 672
CIRCLE_RADIUS = CIRCLE_DIAMETER / 2


def main() -> None:
    scale = SUPERSAMPLE_FACTOR
    center = (CIRCLE_CENTER[0] * scale, CIRCLE_CENTER[1] * scale)
    radius = CIRCLE_RADIUS * scale

    image = Image.new("RGB", (DRAW_SIZE, DRAW_SIZE), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(image)
    bbox = (
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    )
    draw.ellipse(bbox, fill=CIRCLE_COLOR)

    image = image.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT_PATH)
    print(f"Wrote {OUTPUT_PATH} ({image.size[0]}x{image.size[1]}, mode={image.mode})")


if __name__ == "__main__":
    main()
