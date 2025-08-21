# =========================
# ONE-SHOT SETUP: AdvancedDSP + PBS v3 (Windows/PowerShell)
# =========================

$ErrorActionPreference = "Stop"
Write-Host "== AdvancedDSP full setup starting ==" -ForegroundColor Cyan

# --- 0) Sanity & folders ---
if (-not (Test-Path .\go.mod)) { throw "Run this from the PBS repo root (go.mod not found)." }
New-Item -ItemType Directory -Force .\bin | Out-Null
New-Item -ItemType Directory -Force .\adapters\advanceddsp | Out-Null
New-Item -ItemType Directory -Force .\openrtb_ext | Out-Null
New-Item -ItemType Directory -Force .\static\bidder-params | Out-Null
New-Item -ItemType Directory -Force .\static\bidder-info | Out-Null

# --- 1) Fix go.mod (remove BOM, pin v3 imports to this repo) ---
# 1a) strip BOM safely
$gomodPath = (Resolve-Path .\go.mod).Path
$text = Get-Content $gomodPath -Raw
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($gomodPath, $text, $utf8NoBom)

# 1b) ensure replace => . so ALL v3 imports resolve locally (critical)
$gm = Get-Content .\go.mod -Raw
if ($gm -notmatch '(?m)^\s*replace\s+github\.com/prebid/prebid-server/v3\s*=>\s*\.\s*$') {
  Add-Content .\go.mod "`r`nreplace github.com/prebid/prebid-server/v3 => ."
  Write-Host "go.mod: added 'replace github.com/prebid/prebid-server/v3 => .'" -ForegroundColor Green
} else {
  Write-Host "go.mod: replace already set for v3 => ." -ForegroundColor DarkGray
}

# 1c) proactively drop 51Degrees dependency if present
try {
  go mod edit -droprequire github.com/51Degrees/device-detection-go/v4 2>$null
} catch { }
# Tidy to prune anything unused
go mod tidy

# --- 2) AdvancedDSP adapter code (v3 imports + correct Builder signature) ---
@'
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
'@ | Set-Content .\adapters\advanceddsp\advanceddsp.go -Encoding UTF8

# --- 3) OpenRTB ext (bidder params struct) ---
@'
package openrtb_ext

// ExtImpAdvanceddsp matches the bidder params schema in static/bidder-params/advanceddsp.json
type ExtImpAdvanceddsp struct {
    PlacementID string `json:"placementId"`
    PublisherID string `json:"publisherId,omitempty"`
}
'@ | Set-Content .\openrtb_ext\imp_advanceddsp.go -Encoding UTF8

# --- 4) Static files (params schema + bidder info) ---
@'
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
'@ | Set-Content .\static\bidder-params\advanceddsp.json -Encoding UTF8

@'
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
'@ | Set-Content .\static\bidder-info\advanceddsp.yaml -Encoding UTF8

# --- 5) Minimal runtime config ---
@'
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

  "currency": {
    "converter_fetch_interval_seconds": 0
  },

  "metrics": {
    "disabled": false
  },

  "stored_requests": {
    "in_memory_cache": { "ttl_seconds": 600 }
  },

  "accounts": {
    "in_memory": {
      "accounts": [
        { "id": "test-acct", "disabled": false }
      ]
    }
  }
}
'@ | Set-Content .\pbs.json -Encoding UTF8

# --- 6) Register adapter in exchange/adapter_builders.go (idempotent) ---
$ab = ".\exchange\adapter_builders.go"
if (-not (Test-Path $ab)) { throw "Missing $ab" }
$content = Get-Content $ab -Raw

# ensure import (v3 path)
if ($content -notmatch 'github\.com/prebid/prebid-server/v3/adapters/advanceddsp') {
  $importReplacement = '$1' + "`r`n`"github.com/prebid/prebid-server/v3/adapters/advanceddsp`"`r`n"
  $content = $content -replace '(?s)(import\s*\()', $importReplacement
}

# ensure registration (near adtrgtme to keep ordering)
if ($content -notmatch '"advanceddsp"\s*:\s*advanceddsp\.Builder') {
  $regReplacement = "        `"advanceddsp`": advanceddsp.Builder,`r`n        `"adtrgtme`": adtrgtme.Builder,"
  $content = $content -replace '(?m)^\s*"adtrgtme"\s*:\s*adtrgtme\.Builder,', $regReplacement
}
Set-Content $ab $content -Encoding UTF8
Write-Host "exchange/adapter_builders.go updated (import + registration ensured)." -ForegroundColor Green

# --- 7) Remove 51Degrees from modules/builder.go (imports and map block) ---
$mb = ".\modules\builder.go"
if (Test-Path $mb) {
  $orig = Get-Content $mb -Raw
  $clean = $orig -replace '(?m)^\s*"github\.com/prebid/prebid-server/v3/modules/fiftyonedegrees/devicedetection"\s*$', ''
  $clean = $clean -replace '(?s)^\s*"fiftyonedegrees"\s*:\s*\{.*?\},\s*\r?\n', ''
  if ($clean -ne $orig) {
    Set-Content $mb $clean -Encoding UTF8
    Write-Host "modules/builder.go: removed 51Degrees import and block." -ForegroundColor Yellow
  } else {
    Write-Host "modules/builder.go: 51Degrees not present (ok)." -ForegroundColor DarkGray
  }
} else {
  Write-Host "modules/builder.go missing (ok on some forks) — skipping module cleanup." -ForegroundColor DarkGray
}

# --- 8) Final tidy + build ---
go clean -modcache
go mod tidy

# Kill any previous PBS processes on Windows (optional, ignore errors)
Get-Process pbs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item .\bin\pbs.exe -ErrorAction SilentlyContinue
go build -trimpath -o .\bin\pbs.exe . 2>&1 | Tee-Object -FilePath build.log

if (-not (Test-Path .\bin\pbs.exe)) {
  Write-Host "`n❌ Build failed — last 160 lines:" -ForegroundColor Red
  Get-Content .\build.log -Tail 160
  throw "Build failed. See errors above."
} else {
  Write-Host "✅ Build OK -> .\bin\pbs.exe" -ForegroundColor Green
}

# --- 9) Start PBS (instructions) ---
Write-Host "`nRun PBS now with verbose logs in THIS window:" -ForegroundColor Cyan
Write-Host '$env:PB_LOG_LEVEL = "debug"; .\bin\pbs.exe --config .\pbs.json' -ForegroundColor White

# --- 10) Test call instructions (run in a second PS window AFTER PBS is listening) ---
Write-Host "`nWhen PBS shows Listening on :8000, test the auction in a second PowerShell window with:" -ForegroundColor Cyan
Write-Host @'
$auction = @'
{
  "id": "req-1",
  "tmax": 500,
  "site": { "page": "https://example.com" },
  "device": { "ua": "test", "ip": "192.168.0.1" },
  "imp": [
    {
      "id": "1",
      "banner": { "format": [ { "w": 300, "h": 250 } ] },
      "ext": {
        "bidder": {
          "advanceddsp": {
            "placementId": "demo-placement",
            "publisherId": "pub-123"
          }
        }
      }
    }
  ],
  "ext": { "prebid": { "accountid": "test-acct" } }
}
'@

Invoke-WebRequest -Uri "http://localhost:8000/openrtb2/auction" -Method POST -ContentType "application/json" -Body $auction | Select-Object -ExpandProperty Content
'@

Write-Host "`n== Setup complete ==" -ForegroundColor Cyan
