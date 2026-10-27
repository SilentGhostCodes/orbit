package libXray

// Orbit: an entry point for OrbitPingBatch (core/libxray/xray/orbit_ping.go), beside Invoke.
// Copied into libXray's root package by CI.

import (
	"encoding/json"

	"github.com/xtls/libxray/xray"
)

type orbitPingRequest struct {
	Configs []PingBatchItemRequest `json:"configs"`
	Timeout int                    `json:"timeout"`
	URL     string                 `json:"url"`
	Method  string                 `json:"method"`
	Mode    string                 `json:"mode"`
}

// OrbitPing takes {configs, timeout, url, method, mode} and answers like Invoke's pingBatch.
func OrbitPing(requestJSON string) string {
	var request orbitPingRequest
	if err := json.Unmarshal([]byte(requestJSON), &request); err != nil {
		return encodeInvokeResponse(nil, err)
	}
	items := make([]xray.PingBatchItem, len(request.Configs))
	for i, c := range request.Configs {
		items[i] = xray.PingBatchItem{XrayJSON: c.XrayJson, OutboundTag: c.OutboundTag}
	}
	results, err := xray.OrbitPingBatch(items, request.Timeout, request.URL, request.Method, request.Mode)
	if err != nil {
		return encodeInvokeResponse(nil, err)
	}
	response := PingBatchResponse{Results: make([]PingBatchItemResponse, len(results))}
	for i, r := range results {
		response.Results[i] = PingBatchItemResponse{Success: r.Success, Delay: r.Delay, Error: r.Error}
	}
	return encodeInvokeResponse(response, nil)
}
