// Orbit's tests for the xray outbound; they replace upstream's h_outbound_test.go, which checked the stub.
package xray

import (
	"bytes"
	"encoding/json"
	"github.com/xtls/xray-core/infra/conf/serial"
	"bufio"
	"context"
	"fmt"
	"net"
	"net/http"
	"strings"
	"testing"

	xcore "github.com/xtls/xray-core/core"
	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/transport/internet"
	M "github.com/sagernet/sing/common/metadata"
	N "github.com/sagernet/sing/common/network"
)

type plainDialer struct{ dialed *int }

func (p plainDialer) DialContext(ctx context.Context, network string, destination M.Socksaddr) (net.Conn, error) {
	*p.dialed++
	return (&net.Dialer{}).DialContext(ctx, network, destination.String())
}
func (p plainDialer) ListenPacket(ctx context.Context, destination M.Socksaddr) (net.PacketConn, error) {
	return net.ListenPacket("udp", "")
}

func TestXrayDialThroughFreedom(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "orbit-ok") }))

	dialed := 0
	cfg, err := buildConfig(map[string]any{
		"remarks":  "test",
		"inbounds": []any{map[string]any{"port": 10808, "protocol": "socks"}},
		"outbounds": []any{
			map[string]any{"tag": "proxy", "protocol": "freedom"},
		},
	}, false)
	if err != nil {
		t.Fatal(err)
	}
	inst, err := xcore.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if err := inst.Start(); err != nil {
		t.Fatal(err)
	}
	defer inst.Close()

	pd := plainDialer{&dialed}
	var nd N.Dialer = pd
	currentDialer.Store(&nd)
	internet.UseAlternativeSystemDialer(systemDialer{})

	port := ln.Addr().(*net.TCPAddr).Port
	conn, err := xcore.Dial(context.Background(), inst, xnet.TCPDestination(xnet.DomainAddress("localhost"), xnet.Port(port)))
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintf(conn, "GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatal(err)
	}
	buf := new(strings.Builder)
	b := make([]byte, 64)
	n, _ := resp.Body.Read(b)
	buf.Write(b[:n])
	if buf.String() != "orbit-ok" {
		t.Fatalf("body %q", buf.String())
	}
	if dialed == 0 {
		t.Fatal("xray did not dial through the sing-box dialer")
	}
	t.Logf("body=%s dialed=%d", buf.String(), dialed)
}

func TestXrayVlessXHTTP(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "via-xhttp") }))
	free, _ := net.Listen("tcp", "127.0.0.1:0")
	serverPort := free.Addr().(*net.TCPAddr).Port
	free.Close()

	uuid := "11111111-2222-3333-4444-555555555555"
	// a real xray server, built from JSON the same way
	serverJSON := map[string]any{
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": serverPort, "protocol": "vless",
			"settings":       map[string]any{"clients": []any{map[string]any{"id": uuid}}, "decryption": "none"},
			"streamSettings": map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{"path": "/xh", "mode": "packet-up"}},
		}},
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow"}}}}},
	}
	b, _ := jsonMarshal(serverJSON)
	sc, err := decodeAndBuild(b)
	if err != nil {
		t.Fatal(err)
	}
	server, err := xcore.New(sc)
	if err != nil {
		t.Fatal(err)
	}
	if err := server.Start(); err != nil {
		t.Fatal(err)
	}
	defer server.Close()

	dialed := 0
	var nd N.Dialer = plainDialer{&dialed}
	currentDialer.Store(&nd)
	internet.UseAlternativeSystemDialer(systemDialer{})

	clientCfg, err := buildConfig(map[string]any{
		"remarks": "cdn",
		"outbounds": []any{map[string]any{
			"tag": "proxy", "protocol": "vless",
			"settings": map[string]any{"vnext": []any{map[string]any{
				"address": "127.0.0.1", "port": serverPort,
				"users": []any{map[string]any{"id": uuid, "encryption": "none"}},
			}}},
			"streamSettings": map[string]any{"network": "xhttp", "xhttpSettings": map[string]any{
				"path": "/xh", "mode": "packet-up",
				"extra": map[string]any{"xPaddingBytes": "100-1000", "xmux": map[string]any{"maxConcurrency": "4-8"}},
			}},
		}},
	}, false)
	if err != nil {
		t.Fatal(err)
	}
	client, err := xcore.New(clientCfg)
	if err != nil {
		t.Fatal(err)
	}
	client.Start()
	defer client.Close()

	conn, err := xcore.Dial(context.Background(), client, xnet.TCPDestination(xnet.LocalHostIP, xnet.Port(ln.Addr().(*net.TCPAddr).Port)))
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintf(conn, "GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatal(err)
	}
	body := make([]byte, 64)
	n, _ := resp.Body.Read(body)
	if string(body[:n]) != "via-xhttp" {
		t.Fatalf("body %q", body[:n])
	}
	t.Logf("body=%s dialed=%d", body[:n], dialed)
}

func TestXrayVlessTCP(t *testing.T) {
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	go http.Serve(ln, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "via-xhttp") }))
	free, _ := net.Listen("tcp", "127.0.0.1:0")
	serverPort := free.Addr().(*net.TCPAddr).Port
	free.Close()

	uuid := "11111111-2222-3333-4444-555555555555"
	// a real xray server, built from JSON the same way
	serverJSON := map[string]any{
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": serverPort, "protocol": "vless",
			"settings":       map[string]any{"clients": []any{map[string]any{"id": uuid}}, "decryption": "none"},
			"streamSettings": map[string]any{"network": "tcp"},
		}},
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{"finalRules": []any{map[string]any{"action": "allow"}}}}},
		"log": map[string]any{"loglevel": "debug"},
	}
	b, _ := jsonMarshal(serverJSON)
	sc, err := decodeAndBuild(b)
	if err != nil {
		t.Fatal(err)
	}
	server, err := xcore.New(sc)
	if err != nil {
		t.Fatal(err)
	}
	if err := server.Start(); err != nil {
		t.Fatal(err)
	}
	defer server.Close()

	dialed := 0
	var nd N.Dialer = plainDialer{&dialed}
	currentDialer.Store(&nd)
	internet.UseAlternativeSystemDialer(systemDialer{})

	clientCfg, err := buildConfig(map[string]any{
		"remarks": "cdn",
		"outbounds": []any{map[string]any{
			"tag": "proxy", "protocol": "vless",
			"settings": map[string]any{"vnext": []any{map[string]any{
				"address": "127.0.0.1", "port": serverPort,
				"users": []any{map[string]any{"id": uuid, "encryption": "none"}},
			}}},
			"streamSettings": map[string]any{"network": "tcp"},
		}},
	}, true)
	if err != nil {
		t.Fatal(err)
	}
	client, err := xcore.New(clientCfg)
	if err != nil {
		t.Fatal(err)
	}
	client.Start()
	defer client.Close()

	conn, err := xcore.Dial(context.Background(), client, xnet.TCPDestination(xnet.LocalHostIP, xnet.Port(ln.Addr().(*net.TCPAddr).Port)))
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintf(conn, "GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatal(err)
	}
	body := make([]byte, 64)
	n, _ := resp.Body.Read(body)
	if string(body[:n]) != "via-xhttp" {
		t.Fatalf("body %q", body[:n])
	}
	t.Logf("body=%s dialed=%d", body[:n], dialed)
}

func jsonMarshal(v any) ([]byte, error) { return json.Marshal(v) }
func decodeAndBuild(b []byte) (*xcore.Config, error) {
	c, err := serial.DecodeJSONConfig(bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	return c.Build()
}
