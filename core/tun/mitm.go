// Package tun wraps the Clash.Meta TUN listener so the core can divert a
// connection to the MITM engine before the tunnel routes it.
package tun

import (
	"context"
	"errors"
	"net"
	"strconv"
	"time"

	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/sniffer"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/log"

	"core/mitm"
)

// mitmTunnel wraps a C.Tunnel and diverts TLS connections whose SNI is in the
// MITM hostname list to the MITM engine. Every other connection, and every
// connection while MITM is off, goes to the real tunnel unchanged.
type mitmTunnel struct {
	C.Tunnel
}

// The wrapper must also satisfy P.Tunnel: sing_tun.New asserts
// tunnel.(P.Tunnel) for provider access, and a wrapper that only embeds
// C.Tunnel panics there, which StartTun recovers as a failed tunnel start.
var (
	_ C.Tunnel = mitmTunnel{}
	_ P.Tunnel = mitmTunnel{}
)

// WrapTunnel returns a C.Tunnel that diverts MITM targets to the engine.
// A tunnel that does not implement P.Tunnel is returned unwrapped.
func WrapTunnel(t C.Tunnel) C.Tunnel {
	if _, ok := t.(P.Tunnel); !ok {
		return t
	}
	return mitmTunnel{Tunnel: t}
}

// Providers forwards to the wrapped tunnel.
func (m mitmTunnel) Providers() map[string]P.ProxyProvider {
	return m.Tunnel.(P.Tunnel).Providers()
}

// RuleProviders forwards to the wrapped tunnel.
func (m mitmTunnel) RuleProviders() map[string]P.RuleProvider {
	return m.Tunnel.(P.Tunnel).RuleProviders()
}

// RuleUpdateCallback forwards to the wrapped tunnel.
func (m mitmTunnel) RuleUpdateCallback() *utils.Callback[P.RuleProvider] {
	return m.Tunnel.(P.Tunnel).RuleUpdateCallback()
}

// HandleTCPConn diverts a MITM target to the engine; all other connections go
// to the tunnel.
func (m mitmTunnel) HandleTCPConn(conn net.Conn, metadata *C.Metadata) {
	if !mitm.Default().Enabled() {
		m.Tunnel.HandleTCPConn(conn, metadata)
		return
	}
	host := sniffSNI(conn)
	if host == "" || !mitm.Default().ShouldIntercept(host) {
		m.Tunnel.HandleTCPConn(conn, metadata)
		return
	}
	hostport := net.JoinHostPort(host, portString(metadata.DstPort))
	if err := mitm.Default().Serve(context.Background(), conn, hostport); err != nil {
		if errors.Is(err, mitm.ErrHandlerUnavailable) {
			// The handler never started, so the connection is untouched:
			// route it direct, as if MITM were off.
			m.Tunnel.HandleTCPConn(conn, metadata)
			return
		}
		// The handler owned the connection once Serve started: it closes
		// it on every error path and reads the ClientHello before failing,
		// so the bytes a tunnel retry would need are already consumed.
		// Handing it back would only fail later, on a closed connection.
		log.Warnln("[MITM] serve %s failed: %v", hostport, err)
		_ = conn.Close()
	}
}

// sniffSNI peeks the TLS ClientHello and returns its SNI, or "" when the
// connection is not TLS or the hello is not yet readable.
func sniffSNI(conn net.Conn) string {
	bc, ok := conn.(*N.BufferedConn)
	if !ok {
		return ""
	}
	// Wait briefly for the first bytes, as the tunnel does before sniffing.
	if !bc.Peeked() {
		_ = conn.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
		_, _ = bc.Peek(1)
		_ = conn.SetReadDeadline(time.Time{})
	}
	n := bc.Buffered()
	if n == 0 {
		return ""
	}
	if n > 16384 {
		n = 16384
	}
	peeked, err := bc.Peek(n)
	if err != nil {
		return ""
	}
	name, err := sniffer.SniffTLS(peeked)
	if err != nil || name == nil {
		return ""
	}
	return *name
}

func portString(port uint16) string {
	if port == 0 {
		return "443"
	}
	return strconv.Itoa(int(port))
}
