"""Generates a REAL tangent-space normal map for every canopy color photo under assets/map/electric/maptile/*/
— replaces the old flat "bump" (fake-depth multiply, tools/generate_canopy_bump.py) approach. This normal map
is sampled in electric_ground.gdshader and lit with an actual per-pixel N.L (+ specular) computation against a
tunable light direction (Terrain Edit panel), instead of a single baked EMBOSS direction hard-multiplied into
the color — a real normal + light gives consistent, tunable directional highlights/shadows across the whole
tile, and lets the "sun angle" be changed live without re-baking.

Technique (pure PIL, no numpy available in this environment):
1. Grayscale the photo (luminance as a height proxy), light Gaussian blur to denoise (same precedent as the
   old bump script — raw photo grain would otherwise become visible per-pixel normal noise).
2. Sobel-filter for dx/dy (ImageFilter.Kernel, native C convolution) -> 8-bit gradient images centered at 128.
3. ImageMath (also native C, no numpy needed) reconstructs a proper (nx, ny, nz) surface normal from those
   gradients + a fixed "flatness" (nz) constant, normalizes it, and encodes to standard tangent-space normal
   map RGB (R=nx, G=ny, B=nz, each *0.5+0.5 -> 0..255).

Re-run whenever a maptile set's color photos change. Skips any file that's already itself a "_normal" output.
Also deletes any leftover "*_bump.png" from the old technique in the same folder (superseded).

Usage: python tools/generate_canopy_normal.py [maptile_root]
  maptile_root defaults to assets/map/electric/maptile — pass another map's maptile folder (e.g.
  assets/map/volcanic/maptile) to bake that map's normals instead.
"""

import sys
from pathlib import Path
from PIL import Image, ImageFilter, ImageMath

BLUR_RADIUS = 1.0       # denoise pass before taking the gradient (same as the old bump script)
GRADIENT_SCALE = 6.0    # divisor on the raw Sobel sum before the +128 offset — lower = more sensitive/steeper
FLATNESS = 1.5          # "nz" before normalizing — lower = more dramatic relief, higher = subtler/flatter
DEFAULT_MAPTILE_ROOT = Path(__file__).resolve().parent.parent / "assets" / "map" / "electric" / "maptile"

SOBEL_X = (-1, 0, 1, -2, 0, 2, -1, 0, 1)
SOBEL_Y = (-1, -2, -1, 0, 0, 0, 1, 2, 1)


def make_normal(src_path: Path, dst_path: Path) -> None:
    img = Image.open(src_path).convert("L")
    if BLUR_RADIUS > 0:
        img = img.filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
    gx = img.filter(ImageFilter.Kernel((3, 3), SOBEL_X, scale=GRADIENT_SCALE, offset=128)).convert("F")
    gy = img.filter(ImageFilter.Kernel((3, 3), SOBEL_Y, scale=GRADIENT_SCALE, offset=128)).convert("F")

    nx = ImageMath.eval("(g - 128) / 128.0", g=gx)
    ny = ImageMath.eval("(g - 128) / 128.0", g=gy)
    nz = Image.new("F", img.size, FLATNESS)

    length = ImageMath.eval("((x * x) + (y * y) + (z * z)) ** 0.5", x=nx, y=ny, z=nz)
    r = ImageMath.eval("convert((x / l * 0.5 + 0.5) * 255, 'L')", x=nx, l=length)
    g = ImageMath.eval("convert((y / l * 0.5 + 0.5) * 255, 'L')", y=ny, l=length)
    b = ImageMath.eval("convert((z / l * 0.5 + 0.5) * 255, 'L')", z=nz, l=length)

    Image.merge("RGB", (r, g, b)).save(dst_path)


def main() -> None:
    maptile_root = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_MAPTILE_ROOT
    if not maptile_root.is_dir():
        print(f"no maptile folder at {maptile_root}")
        return
    count = 0
    for set_dir in sorted(maptile_root.iterdir()):
        if not set_dir.is_dir():
            continue
        for old_bump in sorted(set_dir.glob("*_bump.png")):
            old_bump.unlink()
            print(f"  removed superseded {old_bump.relative_to(maptile_root.parent)}")
        for src in sorted(set_dir.glob("*.png")):
            if "_normal" in src.stem:
                continue
            dst = src.with_name(src.stem + "_normal.png")
            make_normal(src, dst)
            print(f"  {src.relative_to(maptile_root.parent)} -> {dst.name}")
            count += 1
    print(f"done: {count} normal map(s) generated")


if __name__ == "__main__":
    main()
