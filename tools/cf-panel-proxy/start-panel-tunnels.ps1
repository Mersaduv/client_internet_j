# Keep Cloudflare quick tunnels alive and sync Worker ORIGIN_BASE bindings.
# App HTTPS fronts (stable):
#   https://jb-herat.mersadkarimi001.workers.dev/users/
#   https://jb-nimroz.mersadkarimi001.workers.dev/
# Farah uses the Herat worker. There is no jb-farah front.
#
# The Nimroz tunnel must run on a PC that can reach that LAN panel.

$ErrorActionPreference = "Continue"
$acct = "44b7611a56bcec74bdd22356e05ec271"
$jsPath = Join-Path $PSScriptRoot "workers\shared\panel-proxy.js"
$sibPath = Join-Path $PSScriptRoot "workers\shared\sib-subscriber.js"
$cfgPath = Join-Path $env:APPDATA "xdg.config\.wrangler\config\default.toml"
$cfg = Get-Content $cfgPath -Raw
if ($cfg -notmatch 'oauth_token\s*=\s*"([^"]+)"') {
  throw "Wrangler OAuth token not found. Run: npx wrangler login"
}
$tok = $Matches[1]

$panels = @(
  @{ Name = "jb-herat";  OriginTarget = "http://165.99.189.40:9394"; DefaultPath = "/users/" },
  @{ Name = "jb-nimroz"; OriginTarget = "http://149.54.23.54:9999"; DefaultPath = "/users/" }
)

function Deploy-Worker([string]$name, [string]$origin, [string]$defaultPath) {
  # jb-herat and jb-nimroz are full code-panel workers (D1 + admin).
  # This thin proxy upload would drop those bindings.
  if ($name -eq "jb-herat" -or $name -eq "jb-nimroz") {
    Write-Host "[SKIP] $name keeps its code-panel worker (origin $origin)"
    return
  }
  $tmp = Join-Path $env:TEMP "cf-panel-sync"
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $meta = '{"main_module":"worker.js","compatibility_date":"2024-09-23","bindings":[{"type":"plain_text","name":"ORIGIN_BASE","text":"'+$origin+'"},{"type":"plain_text","name":"DEFAULT_PATH","text":"'+$defaultPath+'"}]}'
  $metaFile = Join-Path $tmp "$name.json"
  [System.IO.File]::WriteAllText($metaFile, $meta)
  $up = curl.exe -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$acct/workers/scripts/$name" `
    -H "Authorization: Bearer $tok" `
    -F "metadata=@${metaFile};type=application/json" `
    -F "worker.js=@${jsPath};filename=worker.js;type=application/javascript+module" `
    -F "sib-subscriber.js=@${sibPath};filename=sib-subscriber.js;type=application/javascript+module"
  $enFile = Join-Path $tmp "$name-en.json"
  [System.IO.File]::WriteAllText($enFile, '{"enabled":true}')
  curl.exe -s -X POST "https://api.cloudflare.com/client/v4/accounts/$acct/workers/scripts/$name/subdomain" `
    -H "Authorization: Bearer $tok" -H "Content-Type: application/json" --data-binary "@$enFile" | Out-Null
  if ($up -match '"success":\s*true') {
    Write-Host "[OK] $name -> $origin"
  } else {
    Write-Host "[FAIL] $name : $up"
  }
}

function Start-QuickTunnel([string]$target) {
  $log = Join-Path $env:TEMP ("cf-tunnel-" + [Guid]::NewGuid().ToString("N") + ".log")
  $p = Start-Process -FilePath "cloudflared" -ArgumentList @("tunnel","--url",$target) `
    -RedirectStandardError $log -RedirectStandardOutput $log -PassThru -WindowStyle Hidden
  $url = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $log) {
      $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
      if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') {
        $url = $Matches[0]
        break
      }
    }
  }
  return @{ Process = $p; Url = $url; Log = $log; Target = $target }
}

Write-Host "Starting quick tunnels..."
$running = @()
foreach ($panel in $panels) {
  $t = Start-QuickTunnel $panel.OriginTarget
  if (-not $t.Url) {
    Write-Host "[WARN] No trycloudflare URL yet for $($panel.OriginTarget). Log: $($t.Log)"
  } else {
    Write-Host "[TUNNEL] $($panel.Name) origin $($panel.OriginTarget) => $($t.Url)"
    Deploy-Worker $panel.Name $t.Url $panel.DefaultPath
  }
  $running += [pscustomobject]@{ Panel = $panel; Tunnel = $t }
}

Write-Host ""
Write-Host "Stable HTTPS fronts:"
Write-Host "  Herat and Farah: https://jb-herat.mersadkarimi001.workers.dev/users/"
Write-Host "  Nimroz: https://jb-nimroz.mersadkarimi001.workers.dev/"
Write-Host ""
Write-Host "Keep this window open. Press Ctrl+C to stop tunnels."

try {
  while ($true) {
    Start-Sleep -Seconds 30
    foreach ($item in $running) {
      if ($item.Tunnel.Process.HasExited) {
        Write-Host "[RESTART] $($item.Panel.Name)"
        $item.Tunnel = Start-QuickTunnel $item.Panel.OriginTarget
        if ($item.Tunnel.Url) {
          Deploy-Worker $item.Panel.Name $item.Tunnel.Url $item.Panel.DefaultPath
        }
      }
    }
  }
} finally {
  foreach ($item in $running) {
    if ($item.Tunnel.Process -and -not $item.Tunnel.Process.HasExited) {
      Stop-Process -Id $item.Tunnel.Process.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
