# The Stream

A streaming simulation game built with Godot 4.

## Requirements

- [Godot 4.6+](https://godotengine.org/download)
- Windows 10/11 (64-bit)
- Internet connection (first-time setup only)
- ~6 GB free disk space (for AI models)

## Setup (first time only)

After cloning the repo, double-click **`setup.bat`** and wait for it to finish.

It will automatically:

| Step | What it does |
|------|-------------|
| **mpv.exe** | Downloads the media player (~30 MB) |
| **Ollama** | Installs the local AI server |
| **qwen2.5:7b** | Downloads the AI chat model (~4.7 GB) |
| **ggml-small.bin** | Downloads the Whisper voice model (~465 MB) |
| **yt-dlp.exe** | Updates the YouTube downloader if needed |

> The download total is roughly **5 GB**. It only runs once — all files are cached locally.

## Run the game

1. Open the project in **Godot 4.6+**
2. If prompted, click **"Reimport All"** (needed for the Whisper model)
3. Press **F5** or click **Play**

## Chatbot & voice recognition

The chatbot requires Ollama to be running in the background.  
`setup.bat` starts it automatically. If you restart your PC, run:

```
ollama serve
```

or simply run `setup.bat` again (it skips already-installed steps).

## Controls

| Key | Action |
|-----|--------|
| `F4` | Toggle edit mode (drag & resize HUD panels) |
| Mic button 🎤 | Start / stop voice input |

## Project structure

```
addons/godot_whisper/   — Voice recognition plugin (Whisper.cpp)
assets/                 — Sprites, audio, fonts
scenes/                 — Godot scene files
scripts/                — GDScript source code
tools/                  — mpv, yt-dlp, bridge script
setup.bat               — First-time setup launcher
tools/setup.ps1         — Setup script (called by setup.bat)
```
