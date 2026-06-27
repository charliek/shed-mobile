"""Generate shed-mobile app-icon assets from one owl SVG.

A small, self-contained pipeline (ported from the roost/lumen projects): recolor a
single owl SVG with cairosvg, compose the per-platform PNGs with Pillow, then let
`flutter_launcher_icons` deploy them into android/ and macos/.

All colors live in the CONSTANTS block below — that is the one place to tweak the
look over time. After editing, re-run:

    make icons
        # or, by hand:
    uv run --with cairosvg --with pillow python scripts/generate_app_icons.py
    dart run flutter_launcher_icons

Outputs (assets/icon/):
    app_icon.png             1024  Android base + adaptive bg : ORANGE owl on WHITE
    app_icon_foreground.png  1024  Android adaptive foreground: ORANGE owl, transparent
    app_icon_desktop.png     1024  macOS                      : WHITE owl on an ORANGE squircle

The owl geometry is assets/icon/reference/owl_logo_colored.svg: the body is
`fill="currentColor"` (swapped for the owl color) and the irises are the
EYE_SENTINEL hex (swapped for EYE_COLOR); the pupils stay white.
"""

import io
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw

# --- Colors — tweak me -------------------------------------------------------
# Mobile (Android), like lumen: a colored owl on a white field.
MOBILE_OWL = "#E8722A"  # orange head/body
MOBILE_BG = "#FFFFFF"  # white background

# Desktop (macOS), like roost: a white owl on a colored squircle.
DESKTOP_OWL = "#FFFFFF"  # white owl
DESKTOP_BG = "#E8722A"  # orange background

# Eyes (both icons): green irises, white pupils.
EYE_COLOR = "#3DAA5C"
# -----------------------------------------------------------------------------

# The iris fill baked into the SVG; swapped for EYE_COLOR at render time. (The
# body uses `currentColor`; the pupils stay #FFFFFF.)
EYE_SENTINEL = "#F4C430"

# Composition shape constants.
ICON_SIZE = 1024  # source PNG edge (flutter_launcher_icons downsizes from here)
RENDER_PX = 2048  # SVG raster width before downscale (crisp LANCZOS resize)
SQUIRCLE_CORNER_PCT = 0.2237  # macOS-ish corner radius, as a fraction of the side
DESKTOP_MARGIN_PCT = 0.10  # transparent margin around the macOS squircle
DESKTOP_OWL_PAD = 0.16  # owl inset inside the squircle
MOBILE_OWL_PAD = 0.10  # owl inset on the full-bleed Android square
MOBILE_FG_PAD = 0.12  # owl inset on the transparent adaptive foreground

ROOT = Path(__file__).resolve().parent.parent
SVG = ROOT / "assets" / "icon" / "reference" / "owl_logo_colored.svg"
OUT = ROOT / "assets" / "icon"


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def render_owl(owl_hex: str, eye_hex: str) -> Image.Image:
    """Rasterize the owl SVG with the body and irises recolored, on a transparent
    canvas (native aspect ratio preserved)."""
    svg = SVG.read_text()
    svg = svg.replace('fill="currentColor"', f'fill="{owl_hex}"')
    svg = svg.replace(f'fill="{EYE_SENTINEL}"', f'fill="{eye_hex}"')
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=RENDER_PX)
    assert isinstance(png, bytes)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def _fit(owl: Image.Image, box: int) -> Image.Image:
    """Resize the owl to fit a box×box square, preserving aspect ratio."""
    aspect = owl.width / owl.height
    if aspect >= 1:
        w, h = box, max(1, round(box / aspect))
    else:
        w, h = max(1, round(box * aspect)), box
    return owl.resize((w, h), Image.Resampling.LANCZOS)


def compose(
    owl: Image.Image,
    *,
    bg: tuple[int, int, int] | None,
    owl_pad: float,
    margin_pct: float = 0.0,
    rounded: bool = False,
    size: int = ICON_SIZE,
) -> Image.Image:
    """Place the owl on a square canvas. `bg=None` leaves it transparent; otherwise
    fill a (optionally rounded) square inset by `margin_pct`."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    margin = round(size * margin_pct)
    inner = size - 2 * margin

    if bg is not None:
        draw = ImageDraw.Draw(canvas)
        box = [margin, margin, margin + inner - 1, margin + inner - 1]
        if rounded:
            draw.rounded_rectangle(
                box, radius=round(inner * SQUIRCLE_CORNER_PCT), fill=(*bg, 255)
            )
        else:
            draw.rectangle(box, fill=(*bg, 255))

    resized = _fit(owl, round(inner * (1 - 2 * owl_pad)))
    canvas.paste(resized, ((size - resized.width) // 2, (size - resized.height) // 2), resized)
    return canvas


def write(img: Image.Image, name: str) -> None:
    path = OUT / name
    img.save(path)
    print(f"  {path.relative_to(ROOT)}  ({img.width}x{img.height})")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    eye = EYE_COLOR
    print(f"Generating shed-mobile icons (mobile={MOBILE_OWL} desktop bg={DESKTOP_BG} eyes={eye})")

    mobile_owl = render_owl(MOBILE_OWL, eye)
    write(
        compose(mobile_owl, bg=hex_to_rgb(MOBILE_BG), owl_pad=MOBILE_OWL_PAD),
        "app_icon.png",
    )
    write(
        compose(mobile_owl, bg=None, owl_pad=MOBILE_FG_PAD),
        "app_icon_foreground.png",
    )

    desktop_owl = render_owl(DESKTOP_OWL, eye)
    write(
        compose(
            desktop_owl,
            bg=hex_to_rgb(DESKTOP_BG),
            owl_pad=DESKTOP_OWL_PAD,
            margin_pct=DESKTOP_MARGIN_PCT,
            rounded=True,
        ),
        "app_icon_desktop.png",
    )
    print("Done.")


if __name__ == "__main__":
    main()
