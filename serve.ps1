<#
.SYNOPSIS
  Local edit server for the Finnovest site. Serves index.html on 127.0.0.1 and
  accepts one-click commits from the in-page editor.

.DESCRIPTION
  GET  /            -> index.html, with the Commit UI injected on the fly
  POST /commit      -> writes index.html, then git add/commit/push
  GET  /ping        -> liveness probe

  The Commit UI is injected at serve time and stripped by the client before the
  payload is sent, so no commit code is ever written into the repo.

  Single-instance: exits immediately if the port is already listening, which
  makes it safe to run from a repeating scheduled task.

.EXAMPLE
  .\serve.ps1
  .\serve.ps1 -Port 8787 -NoPush
#>

[CmdletBinding()]
param(
  [int]    $Port   = 8787,
  [string] $Branch = 'main',
  [switch] $NoPush,
  [switch] $Quiet
)

$ErrorActionPreference = 'Stop'
$repo   = $PSScriptRoot
$target = Join-Path $repo 'index.html'
$logDir = Join-Path $repo '.serve'
$logFile= Join-Path $logDir 'serve.log'

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Log($msg, $color='Gray') {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
  Add-Content -Path $logFile -Value $line -Encoding utf8
  if (-not $Quiet) { Write-Host "  $line" -ForegroundColor $color }
}

# ---------------------------------------------------------------- single instance
$inUse = $false
try {
  $probe = New-Object System.Net.Sockets.TcpClient
  $probe.Connect('127.0.0.1', $Port)
  $inUse = $true
  $probe.Close()
} catch { $inUse = $false }

if ($inUse) { Log "Port $Port already serving - this instance exits." 'DarkGray'; exit 0 }
if (-not (Test-Path $target)) { Log "index.html not found in $repo" 'Red'; exit 1 }

# ---------------------------------------------------------------- session token
$bytes = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$TOKEN = [Convert]::ToBase64String($bytes).Replace('+','-').Replace('/','_').TrimEnd('=')

# ---------------------------------------------------------------- injected client
$injected = @'
<script data-injected="1">
/* Injected by serve.ps1 - never written back to the repo. */
(function(){
  var TOKEN = "__TOKEN__";
  var bar = document.getElementById('edit-bar');
  if(!bar) return;

  var btn = document.createElement('button');
  btn.className = 'btn btn-mint btn-sm';
  btn.id = 'ed-commit';
  btn.setAttribute('data-injected','1');
  btn.textContent = 'Commit';

  var msg = document.createElement('span');
  msg.className = 'cnt';
  msg.setAttribute('data-injected','1');
  msg.style.marginLeft = '8px';

  var save = document.getElementById('ed-save');
  bar.insertBefore(btn, save ? save.nextSibling : null);
  bar.appendChild(msg);

  function serialize(){
    var clone = document.documentElement.cloneNode(true);
    /* strip everything this server injected */
    Array.prototype.forEach.call(clone.querySelectorAll('[data-injected]'), function(el){ el.remove(); });
    /* mirror the page's own export policy exactly */
    Array.prototype.forEach.call(clone.querySelectorAll('[data-edit]'), function(el){
      el.removeAttribute('data-edit'); el.removeAttribute('contenteditable');
      el.removeAttribute('spellcheck'); el.classList.remove('dirty');
      if(el.getAttribute('class')==='') el.removeAttribute('class');
    });
    Array.prototype.forEach.call(clone.querySelectorAll('.page'), function(p,i){
      if(i===0) p.classList.add('live'); else p.classList.remove('live');
    });
    Array.prototype.forEach.call(clone.querySelectorAll('.rev.in'), function(el){ el.classList.remove('in'); });
    var cb=clone.querySelector('body'); if(cb) cb.className='';
    clone.classList.remove('js');
    return '<!DOCTYPE html>\n' + clone.outerHTML;
  }

  var busy=false;
  btn.addEventListener('click', function(e){
    e.stopPropagation();
    if(busy) return;
    var m = window.prompt('Commit message:', 'Copy edit');
    if(m === null) return;
    if(!m.trim()) m = 'Copy edit via in-page editor';

    busy=true; btn.disabled=true; msg.textContent='Committing...';
    fetch('/commit', {
      method:'POST',
      headers:{'Content-Type':'text/plain;charset=utf-8','X-Edit-Token':TOKEN,'X-Commit-Message':encodeURIComponent(m)},
      body: serialize()
    })
    .then(function(r){ return r.json().then(function(j){ return {ok:r.ok, j:j}; }); })
    .then(function(res){
      if(!res.ok) throw new Error(res.j.error || 'commit failed');
      msg.textContent = res.j.nochange ? 'No change to commit.'
                      : ('Committed ' + res.j.sha + (res.j.pushed ? ' - pushed' : ' - not pushed'));
    })
    .catch(function(err){ msg.textContent = 'Error: ' + err.message; })
    .then(function(){ busy=false; btn.disabled=false; });
  });
})();
</script>
'@ -replace '__TOKEN__', $TOKEN

# ---------------------------------------------------------------- http plumbing
function Find-HeaderEnd([byte[]]$a, [int]$len) {
  for ($i = 0; $i -lt $len - 3; $i++) {
    if ($a[$i] -eq 13 -and $a[$i+1] -eq 10 -and $a[$i+2] -eq 13 -and $a[$i+3] -eq 10) { return $i }
  }
  return -1
}

function Read-Request($stream) {
  $buf = New-Object byte[] 16384
  $ms  = New-Object System.IO.MemoryStream
  $headerEnd = -1
  while ($headerEnd -lt 0) {
    $n = $stream.Read($buf, 0, $buf.Length)
    if ($n -le 0) { return $null }
    $ms.Write($buf, 0, $n)
    $arr = $ms.ToArray()
    $headerEnd = Find-HeaderEnd $arr $arr.Length
    if ($ms.Length -gt 2MB -and $headerEnd -lt 0) { return $null }
  }
  $arr     = $ms.ToArray()
  $headTxt = [Text.Encoding]::ASCII.GetString($arr, 0, $headerEnd)
  $lines   = $headTxt -split "`r`n"
  $parts   = $lines[0] -split ' '

  $headers = @{}
  foreach ($l in $lines[1..($lines.Count-1)]) {
    $ix = $l.IndexOf(':'); if ($ix -gt 0) { $headers[$l.Substring(0,$ix).Trim().ToLower()] = $l.Substring($ix+1).Trim() }
  }

  $bodyStart = $headerEnd + 4
  $have      = $arr.Length - $bodyStart
  $need      = 0
  if ($headers.ContainsKey('content-length')) { $need = [int]$headers['content-length'] }

  $body = New-Object System.IO.MemoryStream
  if ($have -gt 0) { $body.Write($arr, $bodyStart, [Math]::Min($have, $need)) }
  while ($body.Length -lt $need) {
    $n = $stream.Read($buf, 0, [Math]::Min($buf.Length, $need - $body.Length))
    if ($n -le 0) { break }
    $body.Write($buf, 0, $n)
  }

  [pscustomobject]@{
    Method  = $parts[0]
    Path    = $parts[1]
    Headers = $headers
    Body    = $body.ToArray()
  }
}

function Send-Response($stream, [int]$status, [string]$type, [byte[]]$body) {
  $reason = switch ($status) { 200 {'OK'} 400 {'Bad Request'} 403 {'Forbidden'} 404 {'Not Found'} 500 {'Internal Server Error'} default {'OK'} }
  $head = "HTTP/1.1 $status $reason`r`n" +
          "Content-Type: $type`r`n" +
          "Content-Length: $($body.Length)`r`n" +
          "Cache-Control: no-store`r`n" +
          "Connection: close`r`n`r`n"
  $hb = [Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($hb, 0, $hb.Length)
  if ($body.Length) { $stream.Write($body, 0, $body.Length) }
  $stream.Flush()
}

function Json([hashtable]$o) { [Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json -Compress)) }

# ---------------------------------------------------------------- commit handler
function Invoke-Commit([string]$html, [string]$message) {
  if ($html.Length -lt 100000)         { return @{ error = "Payload only $($html.Length) chars - refusing to write." } }
  if ($html -notmatch 'Finnovest')     { return @{ error = 'Payload does not mention Finnovest - refusing.' } }
  if ($html -notmatch 'id="edit-bar"') { return @{ error = 'Payload has no edit bar - would become uneditable.' } }
  if ($html -match 'data-injected')    { return @{ error = 'Payload still contains injected markup - refusing.' } }

  Push-Location $repo
  # git writes normal progress to stderr. Under $ErrorActionPreference = 'Stop'
  # that surfaces as a terminating NativeCommandError, which previously made a
  # SUCCESSFUL push get reported to the browser as a failure. Never redirect
  # native stderr with 2>&1 here - trust $LASTEXITCODE instead.
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($target, $html, $utf8)

    $changed = git status --porcelain -- index.html
    if (-not $changed) { return @{ nochange = $true } }

    git add index.html | Out-Null
    if ($LASTEXITCODE -ne 0) { return @{ error = 'git add failed' } }

    git commit -m $message | Out-Null
    if ($LASTEXITCODE -ne 0) { return @{ error = 'git commit failed' } }
    $sha = (git rev-parse --short HEAD).Trim()

    $pushed = $false
    if (-not $NoPush) {
      git push origin $Branch | Out-Null
      $pushed = ($LASTEXITCODE -eq 0)
    }
    return @{ sha = $sha; pushed = $pushed; committed = $true }
  }
  catch  { return @{ error = $_.Exception.Message } }
  finally { $ErrorActionPreference = $prevEAP; Pop-Location }
}

# ---------------------------------------------------------------- serve
# Bind BOTH loopback stacks. "localhost" resolves to ::1 before 127.0.0.1 on
# Windows, so an IPv4-only listener makes clients race and intermittently abort.
# Loopback addresses only - never IPv6Any/IPv4Any, which would expose the
# commit endpoint to the network.
$listeners = @()
foreach ($ip in @([System.Net.IPAddress]::Loopback, [System.Net.IPAddress]::IPv6Loopback)) {
  try {
    $l = New-Object System.Net.Sockets.TcpListener($ip, $Port)
    $l.Start()
    $listeners += $l
  } catch { Log "could not bind $($ip): $($_.Exception.Message)" 'Yellow' }
}
if (-not $listeners.Count) { Log "no loopback address could be bound on $Port" 'Red'; exit 1 }
Log "Serving $repo on http://localhost:$Port/  ($($listeners.Count) stack(s), branch $Branch$(if($NoPush){', no push'}))" 'Green'

try {
  while ($true) {
    $ready = $null
    foreach ($l in $listeners) { if ($l.Pending()) { $ready = $l; break } }
    if (-not $ready) { Start-Sleep -Milliseconds 40; continue }
    $client = $ready.AcceptTcpClient()
    $stream = $client.GetStream()
    try {
      $req = Read-Request $stream
      if (-not $req) { continue }

      switch -Regex ($req.Method + ' ' + ($req.Path -replace '\?.*$','')) {

        '^GET /ping$' {
          Send-Response $stream 200 'application/json' (Json @{ ok = $true; port = $Port })
          break
        }

        '^GET /(index\.html)?$' {
          $html = Get-Content $target -Raw -Encoding UTF8
          if ($html -match '(?i)</body>') { $html = $html -replace '(?i)</body>', ($injected + "`n</body>") }
          else                            { $html = $html + $injected }
          Send-Response $stream 200 'text/html; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes($html))
          Log "GET / -> $([math]::Round($html.Length/1KB,1)) KB"
          break
        }

        '^POST /commit$' {
          if ($req.Headers['x-edit-token'] -ne $TOKEN) {
            Send-Response $stream 403 'application/json' (Json @{ error = 'bad token' })
            Log "POST /commit REJECTED - bad token" 'Yellow'
            break
          }
          $html = [Text.Encoding]::UTF8.GetString($req.Body)
          $msg  = 'Copy edit via in-page editor'
          if ($req.Headers.ContainsKey('x-commit-message')) {
            $msg = [System.Uri]::UnescapeDataString($req.Headers['x-commit-message'])
          }
          $res = Invoke-Commit $html $msg
          if ($res.error) {
            Send-Response $stream 400 'application/json' (Json $res)
            Log "POST /commit FAILED - $($res.error)" 'Red'
          } else {
            Send-Response $stream 200 'application/json' (Json $res)
            if ($res.nochange) { Log "POST /commit - no change" 'DarkGray' }
            else { Log "POST /commit -> $($res.sha) pushed=$($res.pushed) : $msg" 'Green' }
          }
          break
        }

        default {
          Send-Response $stream 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Not found'))
        }
      }
    }
    catch   { Log "request error: $($_.Exception.Message)" 'Red' }
    finally { $stream.Dispose(); $client.Close() }
  }
}
finally {
  foreach ($l in $listeners) { try { $l.Stop() } catch {} }
  Log 'Stopped.' 'DarkGray'
}
