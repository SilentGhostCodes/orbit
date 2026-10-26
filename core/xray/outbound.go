// Orbit: a working "xray" outbound for hiddify-sing-box, replacing protocol/hiddify/xray/outbound.go
// (upstream returns "Xray is not implemented yet").
//
// Each outbound runs its own xray-core instance from a full Xray JSON config (the "xconfig" option),
// so everything Xray supports — XHTTP with extra/xmux/downloadSettings, CDN fronting, fragment chains,
// finalmask — works as written by the panel. Inbounds are dropped: traffic enters xray through
// core.Dial, and xray's own sockets go out through sing-box's dialer, which on Android protects them
// from the tunnel and resolves through sing-box's DNS.
package xray

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/adapter/outbound"
	"github.com/sagernet/sing-box/common/dialer"
	C "github.com/sagernet/sing-box/constant"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
	E "github.com/sagernet/sing/common/exceptions"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service"

	xnet "github.com/xtls/xray-core/common/net"
	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	"github.com/xtls/xray-core/transport/internet"
)

func RegisterOutbound(registry *outbound.Registry) {
	outbound.Register[option.XrayOutboundOptions](registry, C.TypeXray, New)
}

var _ adapter.Outbound = (*Outbound)(nil)

type Outbound struct {
	outbound.Adapter
	logger   logger.ContextLogger
	instance *xcore.Instance
}

func New(ctx context.Context, router adapter.Router, logger log.ContextLogger, tag string, options option.XrayOutboundOptions) (adapter.Outbound, error) {
	raw := options.XConfig
	if raw == nil {
		raw = options.DeprecatedXrayOutboundJson
	}
	if raw == nil {
		return nil, E.New("xray: missing xconfig")
	}
	config, err := buildConfig(*raw, options.XDebug)
	if err != nil {
		return nil, E.Cause(err, "xray: config")
	}
	instance, err := xcore.New(config)
	if err != nil {
		return nil, E.Cause(err, "xray: create")
	}

	outboundDialer, err := dialer.New(ctx, options.DialerOptions, true)
	if err != nil {
		return nil, err
	}
	useSingBoxNetwork(ctx, outboundDialer)

	return &Outbound{
		Adapter:  outbound.NewAdapterWithDialerOptions(C.TypeXray, tag, []string{N.NetworkTCP, N.NetworkUDP}, options.DialerOptions),
		logger:   logger,
		instance: instance,
	}, nil
}

// buildConfig accepts a full Xray config or a bare outbound object.
func buildConfig(raw map[string]any, debug bool) (*xcore.Config, error) {
	cfg := make(map[string]any, len(raw))
	for k, v := range raw {
		cfg[k] = v
	}
	if _, ok := cfg["outbounds"]; !ok {
		if _, isOutbound := cfg["protocol"]; !isOutbound {
			return nil, E.New("neither an Xray config nor an outbound")
		}
		cfg = map[string]any{"outbounds": []any{raw}}
	}
	// traffic comes in through core.Dial; local listeners would only clash with each other
	delete(cfg, "inbounds")
	delete(cfg, "api")
	delete(cfg, "stats")
	delete(cfg, "metrics")
	level := "warning"
	if debug {
		level = "debug"
	}
	cfg["log"] = map[string]any{"loglevel": level}

	content, err := json.Marshal(cfg)
	if err != nil {
		return nil, err
	}
	jsonConfig, err := serial.DecodeJSONConfig(bytes.NewReader(content))
	if err != nil {
		return nil, err
	}
	return jsonConfig.Build()
}

func (h *Outbound) Start(stage adapter.StartStage) error {
	if stage != adapter.StartStateStart {
		return nil
	}
	return h.instance.Start()
}

func (h *Outbound) Close() error {
	return h.instance.Close()
}

func toXrayDestination(network string, destination M.Socksaddr) xnet.Destination {
	var address xnet.Address
	if destination.IsFqdn() {
		address = xnet.DomainAddress(destination.Fqdn)
	} else {
		address = xnet.IPAddress(destination.Addr.AsSlice())
	}
	port := xnet.Port(destination.Port)
	if N.NetworkName(network) == N.NetworkUDP {
		return xnet.UDPDestination(address, port)
	}
	return xnet.TCPDestination(address, port)
}

func (h *Outbound) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	ctx, metadata := adapter.ExtendContext(ctx)
	metadata.Outbound = h.Tag()
	metadata.Destination = destination
	h.logger.InfoContext(ctx, "outbound connection to ", destination)
	return xcore.Dial(ctx, h.instance, toXrayDestination(network, destination))
}

func (h *Outbound) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	ctx, metadata := adapter.ExtendContext(ctx)
	metadata.Outbound = h.Tag()
	metadata.Destination = destination
	h.logger.InfoContext(ctx, "outbound packet connection to ", destination)
	return xcore.DialUDP(ctx, h.instance)
}

// --- xray's own sockets go out through sing-box ---

// The sing-box dialer and socket protector of the running box. xray-core keeps one global system
// dialer, so every xray outbound shares these; a reconnect builds a new box and replaces them.
var (
	currentDialer  atomic.Pointer[N.Dialer]
	currentProtect atomic.Pointer[func(network, address string, conn syscall.RawConn) error]
	registerOnce   sync.Once
)

func useSingBoxNetwork(ctx context.Context, d N.Dialer) {
	currentDialer.Store(&d)
	if networkManager := service.FromContext[adapter.NetworkManager](ctx); networkManager != nil {
		if protect := networkManager.ProtectFunc(); protect != nil {
			f := (func(network, address string, conn syscall.RawConn) error)(protect)
			currentProtect.Store(&f)
		}
	}
	registerOnce.Do(func() {
		internet.UseAlternativeSystemDialer(systemDialer{})
		// sockets xray opens itself (QUIC listeners and the like) are protected too
		control := func(network, address string, conn syscall.RawConn) error {
			if f := currentProtect.Load(); f != nil {
				return (*f)(network, address, conn)
			}
			return nil
		}
		_ = internet.RegisterDialerController(control)
		_ = internet.RegisterListenerController(control)
	})
}

type systemDialer struct{}

func (systemDialer) Dial(ctx context.Context, _ xnet.Address, destination xnet.Destination, _ *internet.SocketConfig) (net.Conn, error) {
	d := currentDialer.Load()
	if d == nil {
		return (&internet.DefaultSystemDialer{}).Dial(ctx, nil, destination, nil)
	}
	network := N.NetworkTCP
	if destination.Network == xnet.Network_UDP {
		network = N.NetworkUDP
	}
	var target M.Socksaddr
	if destination.Address.Family().IsDomain() {
		target = M.ParseSocksaddrHostPort(destination.Address.Domain(), uint16(destination.Port))
	} else {
		target = M.SocksaddrFrom(M.AddrFromIP(destination.Address.IP()), uint16(destination.Port))
	}
	return (*d).DialContext(ctx, network, target)
}

func (systemDialer) DestIpAddress() net.IP { return nil }
