package tun

import (
	"testing"

	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

// Regression test: sing_tun.New asserts tunnel.(P.Tunnel) for provider
// access. A MITM wrapper that only embeds C.Tunnel panics there, StartTun
// recovers it, and the tunnel fails to start with "无法启动核心隧道".
// The wrapped real tunnel must keep satisfying both tunnel interfaces.
func TestWrapTunnelKeepsProviderTunnel(t *testing.T) {
	wrapped := WrapTunnel(tunnel.Tunnel)
	if _, ok := wrapped.(P.Tunnel); !ok {
		t.Fatal("wrapped tunnel does not implement provider.Tunnel")
	}
	var _ C.Tunnel = wrapped
}
