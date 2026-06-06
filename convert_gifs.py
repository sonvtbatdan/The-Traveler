#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GIF to PNG sprite sheet converter (Python PIL/Pillow version)
Converts all multi-frame GIFs to horizontal sprite sheets + JSON metadata
"""

import os
import sys
import json
from pathlib import Path
from PIL import Image

# Fix encoding for Windows console
if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

SEARCH_ROOT = Path("D:/GitHub Projects/The Traveler/assets")

def find_gifs(folder):
    """Recursively find all .gif files"""
    gifs = []
    for root, dirs, files in os.walk(folder):
        for file in files:
            if file.lower().endswith('.gif'):
                gifs.append(Path(root) / file)
    return gifs

def convert_gif(gif_path):
    """Convert single GIF to sprite sheet"""
    try:
        # Open GIF
        img = Image.open(gif_path)

        # Check if multi-frame
        frame_count = getattr(img, 'n_frames', 1)
        if frame_count <= 1:
            print("    SKIP (single frame) " + gif_path.name)
            return True

        # Extract all frames + delays
        frames = []
        delays = []
        for i in range(frame_count):
            img.seek(i)
            frames.append(img.convert('RGBA'))
            duration = img.info.get('duration', 100)  # ms
            delays.append(duration / 1000.0)  # convert to seconds

        # Get frame dimensions
        fw, fh = frames[0].size

        # Create horizontal sprite sheet
        sheet = Image.new('RGBA', (fw * frame_count, fh), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            sheet.paste(frame, (i * fw, 0))

        # Save PNG
        base = gif_path.with_suffix('')
        png_path = str(base) + '.sheet.png'
        json_path = str(base) + '.sheet.json'

        sheet.save(png_path, 'PNG')

        # Save JSON metadata
        meta = {
            'cols': frame_count,
            'w': fw,
            'h': fh,
            'delays': delays
        }
        with open(json_path, 'w') as f:
            json.dump(meta, f, indent=2)

        print("    OK    " + gif_path.name + " (" + str(frame_count) + " frames, " + str(fw) + "x" + str(fh) + ")")
        return True

    except Exception as e:
        print("    FAIL  " + gif_path.name + " - " + str(e))
        return False

def main():
    print("=== GIF to PNG sprite sheet converter (Python) ===\n")

    gifs = sorted(find_gifs(SEARCH_ROOT))
    n_ok = 0
    n_skip = 0
    n_fail = 0

    for gif_path in gifs:
        base = gif_path.with_suffix('')
        png_path = str(base) + '.sheet.png'

        # Skip if already converted
        if os.path.exists(png_path):
            print(f"    SKIP  {gif_path.name}")
            n_skip += 1
            continue

        if convert_gif(gif_path):
            n_ok += 1
        else:
            n_fail += 1

    print(f"\n{n_ok} converted, {n_skip} skipped, {n_fail} failed.")
    if n_ok > 0:
        print("Open the Godot editor once to import the new .sheet.png files.")

if __name__ == '__main__':
    main()
