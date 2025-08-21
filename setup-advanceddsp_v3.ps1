# =========================
# AdvancedDSP one-shot setup for PBS v3 (Windows PowerShell)
# =========================

$ErrorActionPreference = "Stop"
Write-Host "== AdvancedDSP Setup (PBS v3) ==" -ForegroundColor Cyan

# --- 0) Sanity & folders ---
if (-not (Test-Path .\go.mod)) { throw "Run this from the PBS repo root (go.mod not found)." }
New-Item -ItemType Directory -Force .\bin | Out-Null
New-Item -ItemType Directory -Force .\adapters\advanceddsp | Out-Null
New-Item -ItemType Directory -Force .\openrtb_ext | Out-Null
New-Item -ItemType Directory -Force .\static\bidder-params | Out-Null
New-Item -ItemType Directory -Force .\static\bidder-info | Out-Null

# --- 1) Make sure go.mod is clean and pin PBS v3 imports to this repo ---
# 1a) strip BOM safely
$gomodPath = (Resolve-Path .\go.mod).Path
$text = Get-Content $gomodPath -Raw
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($gomodPath, $text, $utf8NoBom)

# 1b) ensure "replace github.com/prebid/prebid-server/v3 => ." so ALL v3 imports resolve locally
$gm = Get-Content .\go.mod -Raw
if ($gm -notmatch '(?m)^\s*replace\s+github\.com/prebid/prebid-server/v3\s*=>\s*\.\s*$') {
  Add-Content .\go.mod "`r`nreplace github.com/prebid/prebid-server/v3 => ."
  Write-Host "go.mod: added 'replace github.com/prebid/prebid-server/v3 => .'" -ForegroundColor Green
} else {
  Write-Host "go.mod: replace already set for v3 => ." -ForegroundColor DarkGray
}

# 1c) drop 51Degrees dependency if present (we’ve removed its use)
& go mod edit -droprequire github.com/51Degrees/device-detection-go/v4 2>$null | Out-Null

# --- 2) Adapter code (v3 imports + correct Builder signature) ---
$adapterGo = @'
package advanceddsp

import (
    "encoding/json"
    "fmt"
    "net/http"

    "github.com/prebid/openrtb/v20/openrtb2"
    "github.com/prebid/prebid-server/v3/adapters"
    "github.com/prebid/prebid-server/v3/config"
    "github.com/prebid/prebid-server/v3/openrtb_ext"
)

// Adapter is your bidder
type Adapter struct {
    endpoint string
}

// Builder for the bidder (v3 signature includes config.Server)
func Builder(bidderName openrtb_ext.BidderName, cfg config.Adapter, srv config.Server) (adapters.Bidder, error) {
    return &Adapter{
        endpoint: "https://yvlwkmetpbbokutsqpfv.supabase.co/functions/v1/prebid-bidder-adapter",
    }, nil
}

// MakeRequests – send bid request to your endpoint
func (a *Adapter) MakeRequests(request *openrtb2.BidRequest, reqInfo *adapters.ExtraRequestInfo) ([]*adapters.RequestData, []error) {
    body, err := json.Marshal(request)
    if err != nil {
        return nil, []error{fmt.Errorf("failed to marshal bid request: %w", err)}
    }
    req := &adapters.RequestData{
        Method:  http.MethodPost,
        Uri:     a.endpoint,
        Body:    body,
        Headers: http.Header{"Content-Type": []string{"application/json"}},
    }
    return []*adapters.RequestData{req}, nil
}

// MakeBids – process response from your DSP
func (a *Adapter) MakeBids(request *openrtb2.BidRequest, requestData *adapters.RequestData, responseData *adapters.ResponseData) (*adapters.BidderResponse, []error) {
    if responseData.StatusCode == http.StatusNoContent {
        return nil, nil
    }
    if responseData.StatusCode != http.StatusOK {
        return nil, []error{fmt.Errorf("unexpected status code: %d", responseData.StatusCode)}
    }

    var bidResp openrtb2.BidResponse
    if err := json.Unmarshal(responseData.Body, &bidResp); err != nil {
        return nil, []error{fmt.Errorf("bad server response: %w", err)}
    }

    br := adapters.NewBidderResponseWithBidsCapacity(5)
    if bidResp.Cur != "" {
        br.Currency = bidResp.Cur
    }
    for _, seat := range bidResp.SeatBid {
        for _, b := range seat.Bid {
            bid := b // capture loop var
            br.Bids = append(br.Bids, &adapters.TypedBid{
                Bid:     &bid,
                BidType: openrtb_ext.BidTypeBanner, // adjust if you add other media types
            })
        }
    }
    return br, nil
}
'@
[System.IO.File]::WriteAllText((Resolve-Path .\adapters\advanceddsp\advanceddsp.go).Path, $adapterGo, $utf8NoBom)
Write-Host "Wrote adapters/advanceddsp/advanceddsp.go" -ForegroundColor Green

# --- 3) OpenRTB ext (bidder params struct) ---
$impGo = @'
package openrtb_ext

// ExtImpAdvanceddsp matches the bidder params schema in static/bidder-params/advanceddsp.json
type ExtImpAdvanceddsp struct {
    PlacementID string `json:"placementId"`
    PublisherID string `json:"publisherId,omitempty"`
}
'@
[System.IO.File]::WriteAllText((Resolve-Path .\openrtb_ext\imp_advanceddsp.go).Path, $impGo, $utf8NoBom)
Write-Host "Wrote openrtb_ext/imp_advanceddsp.go" -ForegroundColor Green

# --- 4) Static files (params schema + bidder info) ---
$paramsJson = @'
{
  "$schema": "http://json-schema.org/draft-04/schema#",
  "title": "AdvancedDSP Params",
  "type": "object",
  "properties": {
    "placementId": { "type": "string" },
    "publisherId": { "type": "string" }
  },
  "required": ["placementId"],
  "additionalProperties": true
}
'@
[System.IO.File]::WriteAllText((Resolve-Path .\static\bidder-params\advanceddsp.json).Path, $paramsJson, $utf8NoBom)

$infoYaml = @'
name: "advanceddsp"
maintainer:
  email: "dev@ad-vanced.media"
capabilities:
  app:
    mediaTypes: ["banner"]
  site:
    mediaTypes: ["banner"]
  dooh:
    mediaTypes: []
usersync:
  supportsCORS: false
  iframe:
    enabled: false
  redirect:
    enabled: false
endpointCompression: false
disabled: false
'@
[System.IO.File]::WriteAllText((Resolve-Path .\static\bidder-info\advanceddsp.yaml).Path, $infoYaml, $utf8NoBom)
Write-Host "Wrote static bidder files" -ForegroundColor Green

# --- 5) Minimal runtime config ---
$pbsJson = @'
{
  "host": {
    "external_url": "http://localhost:8000",
    "port": 8000
  },
  "request_limits": {
    "max_request_size_bytes": 1048576
  },
  "account_required": false,

  "adapters": {
    "advanceddsp": {
      "endpoint": "https://yvlwkmetpbbokutsqpfv.supabase.co/functions/v1/prebid-bidder-adapter",
      "endpoint-compression": false,
      "disabled": false
    }
  },

  "currency": { "converter_fetch_interval_seconds": 0 },
  "metrics": { "disabled": false },

  "stored_requests": { "in_memory_cache": { "ttl_seconds": 600 } },

  "accounts": {
    "in_memory": {
      "accounts": [
        { "id": "test-acct", "disabled": false }
      ]
    }
  }
}
'@
[System.IO.File]::WriteAllText((Resolve-Path .\pbs.json).Path, $pbsJson, $utf8NoBom)
Write-Host "Wrote pbs.json" -ForegroundColor Green

# --- 6) Register adapter in exchange/adapter_builders.go (idempotent) ---
$abPath = ".\exchange\adapter_builders.go"
if (-not (Test-Path $abPath)) { throw "Missing $abPath" }
$content = Get-Content $abPath -Raw

# Ensure import exists (v3 path)
if ($content -notmatch 'github\.com/prebid/prebid-server/v3/adapters/advanceddsp') {
  $content = $content -replace '(?s)(import\s*\()', '$1' + "`r`n`"github.com/prebid/prebid-server/v3/adapters/advanceddsp`"`r`n"
}

# Ensure registration exists once (near adtrgtme)
if ($content -notmatch '"advanceddsp"\s*:\s*advanceddsp\.Builder') {
  $content = $content -replace '(?m)^\s*"adtrgtme"\s*:\s*adtrgtme\.Builder,', "        `"advanceddsp`": advanceddsp.Builder,`r`n        `"adtrgtme`": adtrgtme.Builder,"
}

[System.IO.File]::WriteAllText((Resolve-Path $abPath).Path, $content, $utf8NoBom)
Write-Host "exchange/adapter_builders.go updated" -ForegroundColor Green

# --- 7) Remove 51Degrees from modules/builder.go (imports and map block) ---
$mbPath = ".\modules\builder.go"
if (Test-Path $mbPath) {
  $orig = Get-Content $mbPath -Raw
  $clean = $orig -replace '(?m)^\s*"github\.com/prebid/prebid-server/v3/modules/fiftyonedegrees/devicedetection"\s*$', ''
  $clean = $clean -replace '(?s)^\s*"fiftyonedegrees"\s*:\s*\{.*?\},\s*\r?\n', ''
  if ($clean -ne $orig) {
    [System.IO.File]::WriteAllText((Resolve-Path $mbPath).Path, $clean, $utf8NoBom)
    Write-Host "modules/builder.go: removed 51Degrees import/block" -ForegroundColor Yellow
  } else {
    Write-Host "modules/builder.go: 51Degrees not present (ok)" -ForegroundColor DarkGray
  }
} else {
  Write-Host "modules/builder.go missing (ok on some forks) — skipping module cleanup." -ForegroundColor DarkGray
}

# --- 8) Final tidy + build ---
& go clean -modcache | Out-Null
& go mod tidy | Out-Null

# Kill any previous PBS processes (ignore errors)
Get-Process pbs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item .\bin\pbs.exe -ErrorAction SilentlyContinue
& go build -trimpath -o .\bin\pbs.exe . 2>&1 | Tee-Object -FilePath build.log | Out-Null

if (-not (Test-Path .\bin\pbs.exe)) {
  Write-Host "`n❌ Build failed — last 160 lines:" -ForegroundColor Red
  Get-Content .\build.log -Tail 160
  throw "Build failed. See errors above."
} else {
  Write-Host "✅ Build OK -> .\bin\pbs.exe" -ForegroundColor Green
}

Write-Host "`nRun PBS in the foreground to see logs:" -ForegroundColor Cyan
Write-Host '$env:PB_LOG_LEVEL = "debug"; .\bin\pbs.exe --config .\pbs.json'
Write-Host "`nWhen PBS shows Listening on :8000, test with:" -ForegroundColor Cyan
Write-Host 'Invoke-WebRequest -Uri "http://localhost:8000/status" -UseBasicParsing'
