#Requires -Version 5.1
<#
.SYNOPSIS
    First-time setup for "The Traveler" game.
    Run once after cloning the repository.
.DESCRIPTION
    Downloads and installs:
      - mpv.exe  (media player, >100 MB — too large for git)
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
# Done
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  1. Open project in Godot 4.6+" -ForegroundColor White
Write-Host "  2. Press Play" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
if ($Host.Name -eq "ConsoleHost") { pause }
