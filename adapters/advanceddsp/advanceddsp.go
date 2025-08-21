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
	ep := cfg.Endpoint
	if ep == "" {
		// fallback to your public edge function
		ep = "https://yvlwkmetpbbokutsqpfv.supabase.co/functions/v1/prebid-bidder-adapter"
	}
	return &Adapter{endpoint: ep}, nil
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

	// Build a quick index of imp types from the original request so we can infer bid media type
	impIndex := map[string]struct {
		Banner bool
		Video  bool
	}{}
	for _, imp := range request.Imp {
		impIndex[imp.ID] = struct {
			Banner bool
			Video  bool
		}{
			Banner: imp.Banner != nil,
			Video:  imp.Video != nil,
		}
	}

	for _, seat := range bidResp.SeatBid {
		for _, b := range seat.Bid {
			bid := b // capture
			// Infer media type from original imp
			mt := openrtb_ext.BidTypeBanner
			if info, ok := impIndex[bid.ImpID]; ok {
				if info.Video {
					mt = openrtb_ext.BidTypeVideo
				} else if info.Banner {
					mt = openrtb_ext.BidTypeBanner
				}
			}
			br.Bids = append(br.Bids, &adapters.TypedBid{
				Bid:     &bid,
				BidType: mt,
			})
		}
	}
	return br, nil
}
