# tools/check.ps1 - Dead Corps local safety gate (run on demand before committing).
#
#   1. PARSE-ERROR GATE (hard fail, exit 1): headless Godot --check-only over every
#      script in scripts/. Catches real GDScript syntax errors - notably the
#      "empty block after a partially-commented print()" parse error that CLAUDE.md
#      warns about and that gdlint does NOT catch.
#   2. SEMANTIC NOTES (advisory): non-autoload compile errors, with the known
#      WorldBounds-autoload false-positive filtered out (see note below).
#   3. gdlint (advisory): style findings using ./gdlintrc (noise rules disabled there).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools/check.ps1   # Windows PowerShell 5.1
#   pwsh tools/check.ps1                                        # PowerShell 7+
#
# Godot path resolution: -Godot arg  >  env GODOT_BIN  >  the default below.
# Use the *_console.exe build so CLI output is captured.
#
# Why per-file --check-only (not --import): a full --import does NOT report parse
# errors in scene-attached scripts, and --check-only --script can't see the
# WorldBounds autoload (not registered for a single-script check) so it emits a
# benign "Identifier not found: WorldBounds" compile error. A real *syntax* error is
# reported as "Parse Error:" BEFORE identifier resolution, so gating on that string
# is immune to the autoload false-positive.

[CmdletBinding()]
param(
    [string]$Godot = ""
)

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if ($Godot -eq "") {
    if ($env:GODOT_BIN) {
        $Godot = $env:GODOT_BIN
    }
    else {
        $Godot = "C:\Users\bengo\Documents\Godot\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
    }
}

if (-not (Test-Path $Godot)) {
    Write-Host "Godot binary not found at: $Godot" -ForegroundColor Red
    Write-Host "Set env GODOT_BIN or pass -Godot <path to the _console.exe>." -ForegroundColor Yellow
    exit 2
}

$scripts = Get-ChildItem -Path (Join-Path $repo "scripts") -Filter *.gd -Recurse
$parseFailures = @()
$semanticNotes = @()

Write-Host "== Parse-error gate -- $($scripts.Count) scripts ==" -ForegroundColor Cyan
foreach ($s in $scripts) {
    $rel = "scripts/" + $s.Name
    # cmd /c merges stderr->stdout as plain text (avoids PS 5.1 NativeCommandError wrapping).
    $cmdLine = '"' + $Godot + '" --headless --check-only --script "' + $s.FullName + '" 2>&1'
    $lines = & cmd /c $cmdLine
    foreach ($line in $lines) {
        if ($line -match "Parse Error:") {
            $parseFailures += $rel + ": " + $line.Trim()
        }
        elseif ($line -match "Compile Error:" -and
                $line -notmatch "Identifier not found: WorldBounds" -and
                $line -notmatch "Identifier not found: GameConfig" -and
                $line -notmatch "Failed to compile depended scripts") {
            $semanticNotes += $rel + ": " + $line.Trim()
        }
    }
}

if ($parseFailures.Count -gt 0) {
    Write-Host "PARSE ERRORS -- gate FAILED:" -ForegroundColor Red
    $parseFailures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
else {
    Write-Host "  No parse errors." -ForegroundColor Green
}

if ($semanticNotes.Count -gt 0) {
    Write-Host ""
    Write-Host "== Semantic notes -- advisory, WorldBounds autoload chain filtered ==" -ForegroundColor Yellow
    $semanticNotes | Select-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

Write-Host ""
Write-Host "== gdlint -- advisory, rules per ./gdlintrc ==" -ForegroundColor Cyan
if (Get-Command gdlint -ErrorAction SilentlyContinue) {
    & gdlint @($scripts.FullName)
    if ($LASTEXITCODE -eq 0) { Write-Host "  No lint findings." -ForegroundColor Green }
}
else {
    Write-Host "  gdlint not installed (pip install gdtoolkit) -- skipping." -ForegroundColor Yellow
}

if ($parseFailures.Count -gt 0) { exit 1 } else { exit 0 }
