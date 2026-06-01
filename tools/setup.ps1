#Requires -Version 5.1
<#
.SYNOPSIS
    First-time setup for "The Stream" game.
    Run once after cloning the repository.
.DESCRIPTION
    Downloads and installs:
      - mpv.exe  (media player, >100 MB — too large for git)
      - Ollama   (local AI server)
      - qwen2.5:7b  (AI chat model, ~4.7 GB)
      - ggml-small.bin  (Whisper voice model, ~465 MB)
    yt-dlp.exe is already included in the repository.
#>

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"   # speeds up Invoke-WebRequest

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR

function Write-Header { param([string]$t) Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Write-OK     { param([string]$t) Write-Host "  [OK] $t"  -ForegroundColor Green  }
function Write-Info   { param([string]$t) Write-Host "  [..] $t"  -ForegroundColor Yellow }
function Write-Fail   { param([string]$t) Write-Host "  [!!] $t"  -ForegroundColor Red    }

# ─────────────────────────────────────────────────────────────────────────────
# 1. mpv.exe
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "mpv (media player)"

$mpvPath = Join-Path $SCRIPT_DIR "mpv.exe"

if ((Test-Path $mpvPath) -and (Get-Item $mpvPath).Length -gt 10MB) {
    Write-OK "mpv.exe already present ($([int]((Get-Item $mpvPath).Length/1MB)) MB)"
} else {
    Write-Info "Fetching latest mpv release URL from GitHub..."
    try {
        $release = Invoke-RestMethod `
            "https://api.github.com/repos/zhongfly/mpv-winbuild/releases/latest" `
            -Headers @{ Accept = "application/vnd.github.v3+json" }

        $asset = $release.assets |
                 Where-Object { $_.name -match "x86_64" -and $_.name -match "\.zip$" -and $_.name -notmatch "bootstrapped" } |
                 Select-Object -First 1

        if (-not $asset) { throw "No suitable zip asset found in release." }

        Write-Info "Downloading $($asset.name) ($([int]($asset.size/1MB)) MB)..."
        $zipTemp = "$env:TEMP\mpv-win.zip"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipTemp

        Write-Info "Extracting mpv.exe..."
        $extractDir = "$env:TEMP\mpv-extract"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $zipTemp -DestinationPath $extractDir -Force

        # Copy mpv.exe and any bundled DLLs to tools/
        $foundExe = Get-ChildItem $extractDir -Filter "mpv.exe" -Recurse | Select-Object -First 1
        if (-not $foundExe) { throw "mpv.exe not found in archive." }

        $sourceDir = $foundExe.DirectoryName
        Get-ChildItem $sourceDir -File |
            Where-Object { $_.Extension -in ".exe", ".dll", ".com" } |
            ForEach-Object { Copy-Item $_.FullName -Destination $SCRIPT_DIR -Force }

        Remove-Item $zipTemp, $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "mpv.exe installed ($([int]((Get-Item $mpvPath).Length/1MB)) MB)"
    } catch {
        Write-Fail "mpv download failed: $_"
        Write-Fail "Manual install: https://mpv.io  — copy mpv.exe to tools\"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. yt-dlp.exe  (included in repo; optionally update)
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "yt-dlp"

$ytPath = Join-Path $SCRIPT_DIR "yt-dlp.exe"
if (Test-Path $ytPath) {
    Write-OK "yt-dlp.exe present in repo"
    Write-Info "Checking for updates..."
    try {
        $latest = (Invoke-RestMethod "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest").tag_name
        $current = (& $ytPath --version 2>&1) -join ""
        if ($current.Trim() -ne $latest.Trim()) {
            Write-Info "Updating yt-dlp ($current -> $latest)..."
            $asset = (Invoke-RestMethod "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest").assets |
                     Where-Object { $_.name -eq "yt-dlp.exe" } | Select-Object -First 1
            if ($asset) {
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ytPath
                Write-OK "yt-dlp updated to $latest"
            }
        } else {
            Write-OK "yt-dlp is up-to-date ($current)"
        }
    } catch {
        Write-OK "yt-dlp version check skipped (offline?)"
    }
} else {
    Write-Info "yt-dlp.exe missing — downloading..."
    try {
        $asset = (Invoke-RestMethod "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest").assets |
                 Where-Object { $_.name -eq "yt-dlp.exe" } | Select-Object -First 1
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ytPath
        Write-OK "yt-dlp.exe downloaded"
    } catch {
        Write-Fail "yt-dlp download failed: $_"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Ollama
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Ollama (local AI server)"

$ollamaExe = @(
    (Get-Command ollama -ErrorAction SilentlyContinue)?.Source,
    "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($ollamaExe) {
    Write-OK "Ollama already installed: $ollamaExe"
} else {
    Write-Info "Downloading Ollama installer..."
    try {
        $installer = "$env:TEMP\OllamaSetup.exe"
        Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $installer
        Write-Info "Installing Ollama silently..."
        Start-Process -FilePath $installer -ArgumentList "/S" -Wait -NoNewWindow
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $ollamaExe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
        if (Test-Path $ollamaExe) {
            Write-OK "Ollama installed"
        } else {
            throw "Executable not found after install."
        }
    } catch {
        Write-Fail "Ollama install failed: $_"
        Write-Fail "Manual install: https://ollama.com"
        $ollamaExe = $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Start Ollama service & pull model
# ─────────────────────────────────────────────────────────────────────────────
if ($ollamaExe) {
    Write-Header "Ollama service + qwen2.5:7b model"

    # Start service if not running
    $serviceUp = $false
    try {
        Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -TimeoutSec 3 | Out-Null
        $serviceUp = $true
        Write-OK "Ollama service already running"
    } catch {
        Write-Info "Starting Ollama service..."
        Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 2
            try {
                Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 | Out-Null
                $serviceUp = $true
                break
            } catch {}
        }
        if ($serviceUp) { Write-OK "Ollama service started" }
        else             { Write-Fail "Ollama service failed to start" }
    }

    if ($serviceUp) {
        $tags     = Invoke-RestMethod "http://127.0.0.1:11434/api/tags" -ErrorAction SilentlyContinue
        $hasModel = $tags.models | Where-Object { $_.name -like "qwen2.5:7b*" }
        if ($hasModel) {
            Write-OK "qwen2.5:7b already downloaded"
        } else {
            Write-Info "Pulling qwen2.5:7b (~4.7 GB) — this will take a while..."
            & $ollamaExe pull qwen2.5:7b
            Write-OK "qwen2.5:7b ready"
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Whisper model  (ggml-small.bin)
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "Whisper voice model (ggml-small.bin)"

$modelDir  = Join-Path $PROJECT_DIR "addons\godot_whisper\models"
$modelPath = Join-Path $modelDir "ggml-small.bin"

if ((Test-Path $modelPath) -and (Get-Item $modelPath).Length -gt 400MB) {
    Write-OK "ggml-small.bin already present ($([int]((Get-Item $modelPath).Length/1MB)) MB)"
} else {
    if (Test-Path $modelPath) { Remove-Item $modelPath -Force }
    if (-not (Test-Path $modelDir)) { New-Item -ItemType Directory -Path $modelDir -Force | Out-Null }
    Write-Info "Downloading ggml-small.bin (~465 MB)..."
    try {
        Invoke-WebRequest `
            -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin" `
            -OutFile $modelPath
        Write-OK "ggml-small.bin downloaded ($([int]((Get-Item $modelPath).Length/1MB)) MB)"
        Write-Info "NOTE: Open the project in Godot editor once to re-import this file."
    } catch {
        Write-Fail "Download failed: $_"
        Write-Fail "Manual: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
        Write-Fail "Save to: $modelPath"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  1. Open project in Godot 4.6+" -ForegroundColor White
Write-Host "  2. If prompted, reimport all resources" -ForegroundColor White
Write-Host "  3. Press Play" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
if ($Host.Name -eq "ConsoleHost") { pause }
