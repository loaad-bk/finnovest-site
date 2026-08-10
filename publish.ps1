<#
.SYNOPSIS
  Apply the newest "Download edited site" export over index.html, review the diff,
  then commit and push.

.DESCRIPTION
  Workflow this supports:
    1. Open index.html from this folder in your browser (local file).
    2. Click "Edit page", change copy, click "Download edited site".
    3. Run this script. It shows you exactly what changed before anything is committed.

  Nothing is committed until you type "yes".

.EXAMPLE
  .\publish.ps1
  .\publish.ps1 -Message "Update FIBI case study headline"
#>

[CmdletBinding()]
param(
  [string] $DownloadDir = (Join-Path $HOME 'Downloads'),
  [string] $Message,
  [switch] $NoPush
)

$ErrorActionPreference = 'Stop'
$repo   = $PSScriptRoot
$target = Join-Path $repo 'index.html'

function Fail($msg) { Write-Host "`n  $msg`n" -ForegroundColor Red; exit 1 }
function Note($msg) { Write-Host "  $msg" -ForegroundColor DarkGray }
function Good($msg) { Write-Host "  $msg" -ForegroundColor Green }

Write-Host "`n  Finnovest publish" -ForegroundColor Cyan
Write-Host "  -----------------" -ForegroundColor Cyan

# --- 0. sanity ---------------------------------------------------------------
if (-not (Test-Path $target)) { Fail "index.html not found in $repo" }

Push-Location $repo
try {
  $dirty = git status --porcelain
  if ($dirty) {
    Write-Host "`n  Working tree is not clean:" -ForegroundColor Yellow
    $dirty | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Note "Commit or stash these first so the copy edit lands as its own commit."
    Fail "Aborted."
  }

  # --- 1. locate the newest export ------------------------------------------
  if (-not (Test-Path $DownloadDir)) { Fail "Download folder not found: $DownloadDir" }

  $export = Get-ChildItem -Path $DownloadDir -Filter 'finnovest-site-*.html' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $export) { Fail "No finnovest-site-*.html found in $DownloadDir" }

  $ageMin = [math]::Round(((Get-Date) - $export.LastWriteTime).TotalMinutes)
  Note "Export : $($export.Name)"
  Note "Saved  : $($export.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) ($ageMin min ago)"
  Note "Size   : $([math]::Round($export.Length/1KB,1)) KB"

  if ($ageMin -gt 120) {
    Write-Host "`n  That export is over 2 hours old." -ForegroundColor Yellow
    Note "If you edited more recently, re-download first - this would publish stale copy."
    if ((Read-Host "  Use it anyway? (yes/no)") -ne 'yes') { Fail "Aborted." }
  }

  # --- 2. plausibility check -------------------------------------------------
  $raw = Get-Content $export.FullName -Raw -Encoding UTF8
  if ($raw.Length -lt 100000)        { Fail "Export is only $($raw.Length) chars - looks truncated. Aborted." }
  if ($raw -notmatch 'Finnovest')    { Fail "Export does not mention Finnovest - wrong file? Aborted." }
  if ($raw -notmatch 'id="edit-bar"'){ Fail "Export has no edit bar - it would become uneditable. Aborted." }

  # --- 3. apply + diff -------------------------------------------------------
  Copy-Item $export.FullName $target -Force

  $stat = git diff --stat -- index.html
  if (-not $stat) {
    Note "No difference from what is already committed. Nothing to do."
    git checkout -- index.html
    exit 0
  }

  Write-Host "`n  Changes" -ForegroundColor Cyan
  git diff --color=always --word-diff=color --unified=0 -- index.html |
    Select-Object -First 120
  Write-Host ""
  Note ($stat -join "`n  ")
  Note "(showing at most 120 lines; run 'git diff' for the full text)"

  # --- 4. confirm ------------------------------------------------------------
  Write-Host ""
  $answer = Read-Host "  Commit and push this? (yes/no)"
  if ($answer -ne 'yes') {
    git checkout -- index.html
    Note "Reverted. index.html is untouched."
    exit 0
  }

  if (-not $Message) {
    $Message = Read-Host "  Commit message"
    if (-not $Message.Trim()) { $Message = "Copy edit via in-page editor" }
  }

  git add index.html
  git commit -m $Message
  if (-not $?) { Fail "Commit failed." }

  if ($NoPush) {
    Good "Committed. Not pushed (-NoPush)."
  } else {
    git push origin main
    if (-not $?) { Fail "Push failed - commit is still safe locally." }
    Good "Pushed. Live at https://loaad-bk.github.io/finnovest-site/ in about a minute."
  }

  Note "Tidy up: the export is still in $DownloadDir"
}
finally { Pop-Location }
