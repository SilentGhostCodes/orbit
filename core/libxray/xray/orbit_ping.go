package xray

// Orbit: pingBatch with the request method and mode Orbit's ping settings offer. Copied into
// libXray's xray package by CI (core/libxray), next to ping_batch.go, whose helpers it uses.

import (
	"context"
	"fmt"
	"io"
	"math"
	"net"
	"net/http"
	"time"

	"github.com/xtls/libxray/nodep"
	xrayNet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/session"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf"
)

// Ping modes: one request; the better of two on fresh connections; the better of two over one
// kept-alive connection, where the second shows the response time without the handshakes.
const (
	OrbitPingModeDefault   = "default"
	OrbitPingModeDouble    = "double"
	OrbitPingModeKeepAlive = "keepalive"
)

// OrbitPingBatch is PingBatch with a choice of HTTP method ("GET" or "HEAD") and mode.
func OrbitPingBatch(
	items []PingBatchItem,
	timeout int,
	targetURL string,
	method string,
	mode string,
) ([]PingBatchResult, error) {
	if err := validatePingBatchRequest(items, timeout, targetURL); err != nil {
		return nil, err
	}
	if method != http.MethodGet && method != http.MethodHead {
		return nil, fmt.Errorf("unsupported ping method %q", method)
	}
	coreServerMu.Lock()
	defer coreServerMu.Unlock()
	if coreServer != nil {
		return nil, fmt.Errorf("pingBatch requires an isolated process without a managed Xray instance")
	}

	results := make([]PingBatchResult, len(items))
	prepared := make([]preparedPingItem, 0, len(items))
	merged := make([]conf.OutboundDetourConfig, 0, len(items))
	for index, item := range items {
		outbounds, err := readPingOutbounds(item.XrayJSON)
		if err != nil {
			results[index] = failedPingBatchResult(nodep.PingDelayError, err)
			continue
		}
		namespaced, tag, err := preparePingOutbounds(outbounds, item.OutboundTag, index)
		if err != nil {
			results[index] = failedPingBatchResult(nodep.PingDelayError, err)
			continue
		}
		prepared = append(prepared, preparedPingItem{resultIndex: index, outboundTag: tag})
		merged = append(merged, namespaced...)
	}
	if len(prepared) == 0 {
		return results, nil
	}

	server, err := startPingBatchServer(merged)
	if err != nil {
		return nil, err
	}
	defer server.Close()

	done := make(chan struct{}, len(prepared))
	for _, item := range prepared {
		go func(item preparedPingItem) {
			results[item.resultIndex] = orbitProbe(server, item.outboundTag, timeout, targetURL, method, mode)
			done <- struct{}{}
		}(item)
	}
	for range prepared {
		<-done
	}
	return results, nil
}

func orbitProbe(server *core.Instance, outboundTag string, timeout int, targetURL, method, mode string) PingBatchResult {
	keepAlive := mode == OrbitPingModeKeepAlive
	transport := &http.Transport{
		DisableKeepAlives: !keepAlive,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" && network != "tcp4" && network != "tcp6" {
				return nil, fmt.Errorf("unsupported ping network %q", network)
			}
			destination, err := xrayNet.ParseDestination("tcp:" + address)
			if err != nil {
				return nil, err
			}
			ctx = session.SetForcedOutboundTagToContext(ctx, outboundTag)
			return core.Dial(ctx, server, destination)
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: time.Second * time.Duration(timeout)}

	rounds := 1
	if mode == OrbitPingModeDouble || keepAlive {
		rounds = 2
	}
	best := int64(-1)
	var lastDelay int64
	var lastErr error
	for i := 0; i < rounds; i++ {
		delay, err := orbitRequest(client, targetURL, method, timeout)
		if err != nil {
			lastDelay, lastErr = delay, err
			// a server that timed out once will time out again; do not wait twice
			if delay == nodep.PingDelayTimeout {
				break
			}
			continue
		}
		if best < 0 || delay < best {
			best = delay
		}
	}
	if best >= 0 {
		return PingBatchResult{Success: true, Delay: best}
	}
	return failedPingBatchResult(lastDelay, lastErr)
}

// orbitRequest times one request. The body is read to the end so a kept-alive connection can
// carry the next request.
func orbitRequest(client *http.Client, targetURL, method string, timeout int) (int64, error) {
	req, err := http.NewRequest(method, targetURL, nil)
	if err != nil {
		return nodep.PingDelayError, err
	}
	start := time.Now()
	response, err := client.Do(req)
	if err == nil {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 1<<20))
		response.Body.Close()
	}
	delay := time.Since(start).Milliseconds()
	if err != nil {
		if math.Abs(float64(delay-int64(timeout)*1000)) < 50 {
			return nodep.PingDelayTimeout, err
		}
		return nodep.PingDelayError, err
	}
	return delay, nil
}
