"""Generates a fake-depth "bump" overlay for every canopy color photo under assets/map/rubicon/maptile/*/ —
a grayscale PNG (128 = neutral, darker = shadow side, lighter = highlight side) meant to be MULTIPLIED into
the color in rubicon_ground.gdshader, not a real normal map (no Light2D / dynamic lighting involved — see the
"fake AO overlay" approach chosen over true normal-mapped lighting).

Technique: grayscale the photo (luminance as a height proxy) -> light Gaussian blur (denoise so per-pixel
photo grain doesn't become visual static) -> PIL's built-in EMBOSS filter (single-direction Sobel-like kernel,
diagonal upper-left light, offset 128) -> blend toward flat 128 by `strength` so the effect stays subtle.

Re-run whenever a maptile set's color photos change (canopy1.png/canopy1a.png/etc). Skips any file that's
already itself a "_bump" output. Keep this tool — new tile sets (see rubicon_asset_scan.gd's
maptile_set_names()) will need it run again.

Usage: python tools/generate_canopy_bump.py
"""

from pathlib import Path
from PIL import Image, ImageFilter

STRENGTH = 0.45
BLUR_RADIUS = 1.0
MAPTILE_ROOT = Path(__file__).resolve().parent.parent / "assets" / "map" / "rubicon" / "maptile"


def make_bump(src_path: Path, dst_path: Path) -> None:
    img = Image.open(src_path).convert("L")
    if BLUR_RADIUS > 0:
        img = img.filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
    embossed = img.filter(ImageFilter.EMBOSS)
    flat = Image.new("L", img.size, 128)
    bump = Image.blend(flat, embossed, STRENGTH)
    bump.save(dst_path)


def main() -> None:
    if not MAPTILE_ROOT.is_dir():
        print(f"no maptile folder at {MAPTILE_ROOT}")
        return
    count = 0
    for set_dir in sorted(MAPTILE_ROOT.iterdir()):
        if not set_dir.is_dir():
            continue
        for src in sorted(set_dir.glob("*.png")):
            if "_bump" in src.stem:
                continue
            dst = src.with_name(src.stem + "_bump.png")
            make_bump(src, dst)
            print(f"  {src.relative_to(MAPTILE_ROOT.parent)} -> {dst.name}")
            count += 1
    print(f"done: {count} bump map(s) generated")


if __name__ == "__main__":
    main()
