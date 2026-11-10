package core

import (
	"io"
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
)

func startEchoServer(t *testing.T, addr string) {
	t.Helper()
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		t.Fatalf("listen %s: %v", addr, err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				io.Copy(c, c)
			}(conn)
		}
	}()
}

func forwardEcho(t *testing.T, addr, msg string) string {
	t.Helper()
	conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		t.Fatalf("dial %s: %v", addr, err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := conn.Write([]byte(msg)); err != nil {
		t.Fatalf("write to %s: %v", addr, err)
	}
	buf := make([]byte, len(msg))
	if _, err := io.ReadFull(conn, buf); err != nil {
		t.Fatalf("read from %s: %v", addr, err)
	}
	return string(buf)
}

func forwarderAddrs(t *testing.T) map[string]forwardTarget {
	t.Helper()
	portForwardersMu.Lock()
	defer portForwardersMu.Unlock()
	out := make(map[string]forwardTarget, len(portForwarders))
	for key, fw := range portForwarders {
		out[key] = forwardTarget{listen: fw.listenAddr, target: fw.targetAddr}
	}
	return out
}

func TestPortForwarderRelaysTCP(t *testing.T) {
	target := freeLoopbackAddr(t)
	startEchoServer(t, target)
	fw := &portForwarder{}
	if err := fw.start("127.0.0.1:0", target); err != nil {
		t.Fatalf("start forwarder: %v", err)
	}
	defer fw.stop()
	if got := forwardEcho(t, fw.listener.Addr().String(), "hello"); got != "hello" {
		t.Fatalf("echo through forwarder = %q, want %q", got, "hello")
	}
}

func freeLoopbackAddr(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve a port: %v", err)
	}
	addr := ln.Addr().String()
	ln.Close()
	return addr
}

func TestPortForwarderDropsCleanlyWhenTargetDown(t *testing.T) {
	target := freeLoopbackAddr(t)
	fw := &portForwarder{}
	if err := fw.start("127.0.0.1:0", target); err != nil {
		t.Fatalf("start forwarder: %v", err)
	}
	defer fw.stop()
	listen := fw.listener.Addr().String()

	dialClosed := func() {
		t.Helper()
		conn, err := net.DialTimeout("tcp", listen, 2*time.Second)
		if err != nil {
			t.Fatalf("dial forwarder: %v", err)
		}
		defer conn.Close()
		conn.SetReadDeadline(time.Now().Add(2 * time.Second))
		buf := make([]byte, 1)
		if _, err := conn.Read(buf); err == nil {
			t.Fatal("read from a dead forward succeeded, want it closed")
		}
	}
	// The extension is down: the forward fails, but the forwarder keeps
	// accepting.
	dialClosed()
	dialClosed()

	// The extension comes up on the same port: forwarding works again.
	startEchoServer(t, target)
	if got := forwardEcho(t, listen, "back"); got != "back" {
		t.Fatalf("echo after the target came up = %q, want %q", got, "back")
	}
}

func TestForwardersFollowTheEffectivePorts(t *testing.T) {
	// Echo servers stand in for the extension core on each effective port.
	startEchoServer(t, "127.0.0.1:37893")
	startEchoServer(t, "127.0.0.1:37890")
	startEchoServer(t, "127.0.0.1:39090")
	startEchoServer(t, "127.0.0.1:39080")

	cfg := &config.Config{
		General:    &config.General{MixedPort: 37893, BindAddress: "*", AllowLan: true},
		Controller: &config.Controller{ExternalController: "127.0.0.1:39090"},
	}
	withCurrentConfig(t, cfg)
	isRunning.Store(true)
	t.Cleanup(func() {
		isRunning.Store(false)
		stopPortForwarders()
		mixedPortSkipped = false
		externalControllerSkipped = false
		forwardMixedPort = 0
		forwardController = ""
	})

	skipMixedPort(&SetupParams{SkipMixedPort: true}, cfg)
	skipExternalController(&SetupParams{SkipExternalController: true}, cfg)
	if cfg.General.MixedPort != 0 || cfg.Controller.ExternalController != "" {
		t.Fatalf("real ports not cleared: mixed=%d controller=%q", cfg.General.MixedPort, cfg.Controller.ExternalController)
	}
	reconcilePortForwarders(cfg)
	addrs := forwarderAddrs(t)
	if addrs["mixed"] != (forwardTarget{listen: ":37894", target: "127.0.0.1:37893"}) {
		t.Fatalf("mixed forwarder = %+v, want listen :37894 target 127.0.0.1:37893", addrs["mixed"])
	}
	if addrs["controller"] != (forwardTarget{listen: "127.0.0.1:39091", target: "127.0.0.1:39090"}) {
		t.Fatalf("controller forwarder = %+v, want listen 127.0.0.1:39091 target 127.0.0.1:39090", addrs["controller"])
	}
	if got := forwardEcho(t, "127.0.0.1:37894", "mixed"); got != "mixed" {
		t.Fatalf("echo through mixed forwarder = %q, want %q", got, "mixed")
	}
	if got := forwardEcho(t, "127.0.0.1:39091", "ctrl"); got != "ctrl" {
		t.Fatalf("echo through controller forwarder = %q, want %q", got, "ctrl")
	}

	// A settings change moves the effective ports; the forwarders follow.
	mixed := 37890
	controller := "127.0.0.1:39080"
	if err := updateConfig(&UpdateParams{MixedPort: &mixed, ExternalController: &controller}); err != nil {
		t.Fatalf("updateConfig: %v", err)
	}
	addrs = forwarderAddrs(t)
	if addrs["mixed"] != (forwardTarget{listen: ":37891", target: "127.0.0.1:37890"}) {
		t.Fatalf("mixed forwarder after the move = %+v, want listen :37891 target 127.0.0.1:37890", addrs["mixed"])
	}
	if addrs["controller"] != (forwardTarget{listen: "127.0.0.1:39081", target: "127.0.0.1:39080"}) {
		t.Fatalf("controller forwarder after the move = %+v, want listen 127.0.0.1:39081 target 127.0.0.1:39080", addrs["controller"])
	}
	if got := forwardEcho(t, "127.0.0.1:37891", "mixed2"); got != "mixed2" {
		t.Fatalf("echo through the moved mixed forwarder = %q, want %q", got, "mixed2")
	}
	if got := forwardEcho(t, "127.0.0.1:39081", "ctrl2"); got != "ctrl2" {
		t.Fatalf("echo through the moved controller forwarder = %q, want %q", got, "ctrl2")
	}
	if conn, err := net.DialTimeout("tcp", "127.0.0.1:37894", time.Second); err == nil {
		conn.Close()
		t.Error("old mixed forwarder 37894 still listening after the port moved")
	}
}
