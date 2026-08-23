"""Generates portrait 3:4 thumbnail images for the Hub Launch panel's map-select grid
(scripts/ui/hub/hub_screen.gd's _build_mapselect) from each map's own ground/background art — center-cropped
to 3:4 then downsized, no distortion. Re-run whenever a map's source art changes.

Usage: python tools/generate_map_thumbnails.py
"""

from pathlib import Path
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "hud" / "mapselect"
THUMB_W = 480
THUMB_H = 640   # 3:4 portrait

# (output filename, source image, brightness multiplier — background.png's raw starfield is too dark/flat to
# read as a thumbnail against the mapselect panel's own near-black background, so it gets a boost; the ground
# photos already have plenty of contrast/color and don't need one)
SOURCES = [
    ("space_thumb.png", ROOT / "assets" / "screen" / "background.png", 2.6),
    ("electric_thumb.png", ROOT / "assets" / "map" / "electric" / "maptile" / "green" / "canopy1.png", 1.0),
    ("volcanic_thumb.png", ROOT / "assets" / "map" / "volcanic" / "maptile" / "lava" / "lava1.png", 1.0),
    ("atlantic_thumb.png", ROOT / "assets" / "map" / "atlantic" / "maptile" / "ruins" / "canopy1.png", 1.0),
    ("mechanic_thumb.png", ROOT / "assets" / "map" / "mechanic" / "maptile" / "default" / "canopy1.png", 1.0),
    ("arctic_thumb.png", ROOT / "assets" / "map" / "arctic" / "maptile" / "default" / "canopy1.png", 1.0),
]


def make_thumb(src_path: Path, dst_path: Path, brightness: float) -> None:
    img = Image.open(src_path).convert("RGB")
    w, h = img.size
    target_ratio = THUMB_W / THUMB_H
    src_ratio = w / h
    if src_ratio > target_ratio:
        # source wider than target -> crop width, keep full height
        crop_h = h
        crop_w = int(h * target_ratio)
    else:
        # source taller/narrower -> crop height, keep full width
        crop_w = w
        crop_h = int(w / target_ratio)
    left = (w - crop_w) // 2
    top = (h - crop_h) // 2
    cropped = img.crop((left, top, left + crop_w, top + crop_h))
    thumb = cropped.resize((THUMB_W, THUMB_H), Image.LANCZOS)
    if brightness != 1.0:
        thumb = ImageEnhance.Brightness(thumb).enhance(brightness)
    thumb.save(dst_path)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, src, brightness in SOURCES:
        if not src.is_file():
            print(f"  SKIP {name}: source not found at {src}")
            continue
        dst = OUT_DIR / name
        make_thumb(src, dst, brightness)
        print(f"  {src.relative_to(ROOT)} -> {dst.relative_to(ROOT)}")
    print("done")


if __name__ == "__main__":
    main()
