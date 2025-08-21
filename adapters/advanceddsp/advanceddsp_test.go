package advanceddsp

import (
    "net/http"
    "testing"

    "github.com/prebid/prebid-server/v3/adapters"
    "github.com/prebid/prebid-server/v3/config"
    "github.com/prebid/prebid-server/v3/openrtb_ext"
    "github.com/prebid/openrtb/v20/openrtb2"
)

func TestBuilder(t *testing.T) {
    bidder, err := Builder(openrtb_ext.BidderName("advanceddsp"), config.Adapter{}, config.Server{})
    if err != nil {
        t.Fatalf("builder error: %v", err)
    }
    if bidder == nil {
        t.Fatalf("builder returned nil bidder")
    }
}

func TestMakeBids(t *testing.T) {
    a := &Adapter{endpoint: "http://example.com"}
    respBody := []byte(`{"cur":"USD","seatbid":[{"bid":[{"impid":"1","price":1.23,"adm":"<html/>","crid":"creative-1"}]}]}`)

    br, errs := a.MakeBids(&openrtb2.BidRequest{}, &adapters.RequestData{}, &adapters.ResponseData{
        StatusCode: http.StatusOK,
        Body:       respBody,
    })
    if len(errs) != 0 {
        t.Fatalf("unexpected error(s): %v", errs)
    }
    if br == nil || len(br.Bids) != 1 {
        t.Fatalf("expected 1 bid, got %#v", br)
    }
    if br.Currency != "USD" {
        t.Fatalf("expected currency USD, got %q", br.Currency)
    }
}
