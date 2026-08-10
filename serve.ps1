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

    /* Extensions also inject <script src="chrome-extension://..."> into the
       live DOM. Serializing those publishes a dead reference, leaks the
       extension id, and - because the injection happens again on every load -
       accumulates one more copy per save. */
    Array.prototype.forEach.call(
      clone.querySelectorAll('script[src^="chrome-extension://"], link[href^="chrome-extension://"], script[src^="moz-extension://"], [id^="PING_"]'),
      function(el){ el.remove(); });

    /* class="" left behind by removing .dirty is pure diff noise. Done before
       the chrome reset below, which deliberately restores class="". */
    Array.prototype.forEach.call(clone.querySelectorAll('[class=""]'), function(el){ el.removeAttribute('class'); });

    /* Reset the editor chrome to its idle state. Without this the saved file
       reopens with the edit bar already showing and the toggle reading
       "Editing", because the DOM is cloned while edit mode is active. */
    var cbar = clone.querySelector('#edit-bar');    if(cbar) cbar.className = '';
    var ctog = clone.querySelector('#edit-toggle'); if(ctog){ ctog.className = ''; ctog.textContent = 'Edit page'; }
    var ccnt = clone.querySelector('#ed-count');    if(ccnt) ccnt.textContent = 'No changes yet';

    /* Browser extensions decorate the live DOM (form fillers add
       fdprocessedid, password managers add their own attributes). Those are
       runtime artefacts and must never be serialized into the repo. */
    Array.prototype.forEach.call(clone.querySelectorAll('*'), function(el){
      for(var i=el.attributes.length-1; i>=0; i--){
        var n = el.attributes[i].name;
        if(/^(fdprocessedid|data-lastpass|data-lp-|data-1p|data-bw|data-dashlane|data-form-type)/.test(n)){
          el.removeAttribute(n);
        }
      }
    });

    return '<!DOCTYPE html>\n' + clone.outerHTML;
  }

  /* ---------------- autosave to disk (no git) ---------------- */
  var SAVE_DELAY = 800, POLL_DELAY = 1000;
  var saveTimer=null, saving=false, queued=false, composing=false, pendingSave=false;
  var lastSaved = null;   /* payload already on disk - skips redundant writes */
  var knownV = null;      /* fingerprint of index.html as this page last knew it */

  function stamp(){
    var d=new Date(), p=function(n){ return (n<10?'0':'')+n; };
    return p(d.getHours())+':'+p(d.getMinutes())+':'+p(d.getSeconds());
  }

  function doSave(){
    if(composing){ schedule(); return; }        /* mid-IME: wait for compositionend */
    var html = serialize();
    if(html === lastSaved){ pendingSave = false; return; }   /* nothing changed */
    if(saving){ queued = true; return; }        /* coalesce into one trailing save */

    saving = true;
    msg.textContent = 'Saving...';
    fetch('/save', {
      method:'POST',
      headers:{'Content-Type':'text/plain;charset=utf-8','X-Edit-Token':TOKEN},
      body: html
    })
    .then(function(r){ return r.json().then(function(j){ return {ok:r.ok, j:j}; }); })
    .then(function(res){
      if(!res.ok) throw new Error(res.j.error || 'save failed');
      lastSaved = html;
      knownV = res.j.v || knownV;   /* our own write must not look external */
      msg.textContent = 'Saved to disk ' + stamp();
    })
    .catch(function(err){ msg.textContent = 'NOT saved: ' + err.message; })
    .then(function(){
      saving = false;
      if(queued){ queued = false; schedule(); }
      else if(lastSaved === html) pendingSave = false;  /* failed saves stay pending,
                                                           which blocks auto-reload */
    });
  }

  function schedule(){
    pendingSave = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(doSave, SAVE_DELAY);
  }

  document.addEventListener('input', function(e){
    var el = e.target.closest && e.target.closest('[data-edit]');
    if(!el) return;
    msg.textContent = 'Editing...';
    schedule();
  });

  /* Hebrew and other IME input arrives as composition events - saving mid
     composition would persist a half-formed word. */
  document.addEventListener('compositionstart', function(){ composing = true; });
  document.addEventListener('compositionend',   function(){ composing = false; schedule(); });

  /* Leaving a block is a natural commit point - save straight away. */
  document.addEventListener('blur', function(e){
    var el = e.target.closest && e.target.closest('[data-edit]');
    if(el){ clearTimeout(saveTimer); doSave(); }
  }, true);

  /* "Revert all" restores innerHTML without firing input, so the disk copy
     would otherwise keep the edited text. */
  var rev = document.getElementById('ed-revert');
  if(rev) rev.addEventListener('click', function(){ setTimeout(schedule, 50); });

  /* ---------------- live reload on external change ---------------- */
  /* Picks up edits made outside this page - by Claude, git checkout, an
     editor. Polls a cheap fingerprint rather than holding a connection open:
     the server handles one request at a time, so an SSE stream would block it. */
  fetch('/version').then(function(r){ return r.json(); })
                   .then(function(j){ knownV = j.v; })
                   .catch(function(){});

  setInterval(function(){
    /* Never reload over unsaved work - a failed or in-flight save keeps
       pendingSave true, so the page waits rather than discarding edits. */
    if(saving || queued || pendingSave) return;

    fetch('/version').then(function(r){ return r.json(); }).then(function(j){
      if(!j.v) return;
      if(!knownV){ knownV = j.v; return; }
      if(j.v === knownV) return;

      knownV = j.v;
      msg.textContent = 'Changed on disk - reloading...';
      try{
        sessionStorage.setItem('fnv_scroll', String(window.scrollY));
        if(bar.classList.contains('on')) sessionStorage.setItem('fnv_editing','1');
      }catch(e){}
      setTimeout(function(){ location.reload(); }, 120);
    }).catch(function(){});
  }, POLL_DELAY);

  /* Restore scroll position and edit mode after a live reload, so an external
     change does not knock you back to the top of page one. */
  try{
    var sy = sessionStorage.getItem('fnv_scroll');
    if(sy !== null){
      sessionStorage.removeItem('fnv_scroll');
      setTimeout(function(){ window.scrollTo(0, parseInt(sy,10)||0); }, 60);
    }
    if(sessionStorage.getItem('fnv_editing')){
      sessionStorage.removeItem('fnv_editing');
      setTimeout(function(){
        var tg = document.getElementById('edit-toggle');
        if(tg && !bar.classList.contains('on')) tg.click();
      }, 80);
    }
  }catch(e){}

  /* ---------------- commit ---------------- */
  var busy=false;
  btn.addEventListener('click', function(e){
    e.stopPropagation();
    if(busy) return;
    var m = window.prompt('Commit message:', 'Copy edit');
    if(m === null) return;
    if(!m.trim()) m = 'Copy edit via in-page editor';

    clearTimeout(saveTimer);
    busy=true; btn.disabled=true; msg.textContent='Committing...';
    var html = serialize();
    fetch('/commit', {
      method:'POST',
      headers:{'Content-Type':'text/plain;charset=utf-8','X-Edit-Token':TOKEN,'X-Commit-Message':encodeURIComponent(m)},
      body: html
    })
    .then(function(r){ return r.json().then(function(j){ return {ok:r.ok, j:j}; }); })
    .then(function(res){
      if(!res.ok) throw new Error(res.j.error || 'commit failed');
      lastSaved = html;   /* /commit writes the same bytes to disk */
      knownV = res.j.v || knownV;
      pendingSave = false;
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
# Shared guards. Autosave writes far more often than commit, so a bad payload
# must never be able to land on disk through the cheaper path.
function Test-Payload([string]$html) {
  if ($html.Length -lt 100000)         { return "Payload only $($html.Length) chars - refusing to write." }
  if ($html -notmatch 'Finnovest')     { return 'Payload does not mention Finnovest - refusing.' }
  if ($html -notmatch 'id="edit-bar"') { return 'Payload has no edit bar - would become uneditable.' }
  if ($html -match 'data-injected')    { return 'Payload still contains injected markup - refusing.' }

  # Backstop against browser-extension contamination. These artefacts are
  # re-injected on every page load, so a client-side miss accumulates one more
  # copy per save and has already reached the published site twice. Refusing is
  # better than silently publishing them; if a new extension appears, add it to
  # the strip list in the injected serialize().
  if ($html -match 'chrome-extension://|moz-extension://') { return 'Payload contains browser-extension markup (extension URL) - refusing.' }
  if ($html -match 'id="PING_')                            { return 'Payload contains browser-extension markup (PING) - refusing.' }
  if ($html -match 'fdprocessedid=')                       { return 'Payload contains browser-extension markup (fdprocessedid) - refusing.' }

  return $null
}

function Save-Payload([string]$html) {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($target, $html, $utf8)
}

# Cheap fingerprint of index.html. The page polls this to notice edits made
# outside the browser (by Claude, git checkout, an editor) and reloads itself.
function Get-Version {
  try { $fi = Get-Item $target; return "$($fi.LastWriteTimeUtc.Ticks)-$($fi.Length)" }
  catch { return '' }
}

function Invoke-Commit([string]$html, [string]$message) {
  $bad = Test-Payload $html
  if ($bad) { return @{ error = $bad } }

  Push-Location $repo
  # git writes normal progress to stderr. Under $ErrorActionPreference = 'Stop'
  # that surfaces as a terminating NativeCommandError, which previously made a
  # SUCCESSFUL push get reported to the browser as a failure. Never redirect
  # native stderr with 2>&1 here - trust $LASTEXITCODE instead.
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    Save-Payload $html

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

        '^GET /version$' {
          Send-Response $stream 200 'application/json' (Json @{ v = (Get-Version) })
          # Not logged: polled once a second per open tab.
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

        '^POST /save$' {
          if ($req.Headers['x-edit-token'] -ne $TOKEN) {
            Send-Response $stream 403 'application/json' (Json @{ error = 'bad token' })
            Log "POST /save REJECTED - bad token" 'Yellow'
            break
          }
          $html = [Text.Encoding]::UTF8.GetString($req.Body)
          $bad  = Test-Payload $html
          if ($bad) {
            Send-Response $stream 400 'application/json' (Json @{ error = $bad })
            Log "POST /save REFUSED - $bad" 'Yellow'
          } else {
            Save-Payload $html
            Send-Response $stream 200 'application/json' (Json @{ saved = $true; bytes = $req.Body.Length; v = (Get-Version) })
            # Successful saves are deliberately not logged - autosave fires on
            # every typing pause and would flood serve.log.
          }
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
            $res.v = Get-Version   # so the page does not treat its own write as external
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
