package openrtb_ext

type ExtImpAdvanceddsp struct {
	PlacementID   string           `json:"placementId"`                     // required
	PublisherID   string           `json:"publisherId,omitempty"`
	SeatID        string           `json:"seatId,omitempty"`
	CampaignID    string           `json:"campaignId,omitempty"`
	LineItemID    string           `json:"lineItemId,omitempty"`
	AdUnitCode    string           `json:"adUnitCode,omitempty"`

	Floor         *float64         `json:"floor,omitempty"`
	Currency      string           `json:"currency,omitempty"`
	EnforceFloor  *bool            `json:"enforceFloor,omitempty"`

	CreativeTypes []string         `json:"creativeTypes,omitempty"`

	BannerSizes   []Format         `json:"bannerSizes,omitempty"` // helper struct below

	Video         *VideoParams     `json:"video,omitempty"`

	DealID        string           `json:"dealId,omitempty"`

	Tracking      *Tracking        `json:"tracking,omitempty"`

	ClickURL      string           `json:"clickUrlOverride,omitempty"`
	GPIDOverride  string           `json:"gpidOverride,omitempty"`

	TimeoutMs     *int             `json:"timeoutMs,omitempty"`
	EndpointOverride string        `json:"endpointOverride,omitempty"`
}

type Format struct {
	W int `json:"w"`
	H int `json:"h"`
}

type VideoParams struct {
	MIMEs          []string `json:"mimes,omitempty"`
	Protocols      []int    `json:"protocols,omitempty"`
	Placement      *int     `json:"placement,omitempty"`
	StartDelay     *int     `json:"startdelay,omitempty"`
	MinDuration    *int     `json:"minduration,omitempty"`
	MaxDuration    *int     `json:"maxduration,omitempty"`
	PlaybackMethod []int    `json:"playbackmethod,omitempty"`
	API            []int    `json:"api,omitempty"`
}

type Tracking struct {
	Imp      []string        `json:"imp,omitempty"`
	Click    []string        `json:"click,omitempty"`
	Quartiles *QuartileTrack `json:"quartiles,omitempty"`
}

type QuartileTrack struct {
	Start    []string `json:"start,omitempty"`
	First    []string `json:"first,omitempty"`
	Mid      []string `json:"mid,omitempty"`
	Third    []string `json:"third,omitempty"`
	Complete []string `json:"complete,omitempty"`
}
