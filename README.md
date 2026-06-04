# The Traveler

A space travel idle/clicker game built with Godot 4.

## Requirements

- [Godot 4.6+](https://godotengine.org/download)
- Windows 10/11 (64-bit)
- Internet connection (first-time setup only)
- ~100 MB free disk space (for media players)

## Setup (first time only)

After cloning the repo, double-click **`setup.bat`** and wait for it to finish.

It will automatically:

| Step | What it does |
|------|-------------|
| **mpv.exe** | Downloads the media player (~30 MB) |
| **yt-dlp.exe** | Updates the YouTube downloader if needed |

## Run the game

1. Open the project in **Godot 4.6+**
2. Press **F5** or click **Play**

## Controls

| Key | Action |
|-----|--------|
| `F4` | Toggle edit mode (drag & resize HUD panels) |

## Project structure

```
assets/                 — Sprites, audio, fonts
scenes/                 — Godot scene files
scripts/                — GDScript source code
tools/                  — mpv, yt-dlp, bridge script
setup.bat               — First-time setup launcher
tools/setup.ps1         — Setup script (called by setup.bat)
```
