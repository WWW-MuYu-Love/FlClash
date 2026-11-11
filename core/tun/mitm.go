// Package tun wraps the Clash.Meta TUN listener so the core can divert a
// connection to the MITM engine before the tunnel routes it.
package tun

import (
	"context"
	"net"
	"strconv"
	"time"

	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/component/sniffer"
	C "github.com/metacubex/mihomo/constant"

	"core/mitm"
)

// mitmTunnel wraps a C.Tunnel and diverts TLS connections whose SNI is in the
// MITM hostname list to the MITM engine. Every other connection, and every
// connection while MITM is off, goes to the real tunnel unchanged.
type mitmTunnel struct {
	C.Tunnel
}

// WrapTunnel returns a C.Tunnel that diverts MITM targets to the engine.
func WrapTunnel(t C.Tunnel) C.Tunnel {
	return mitmTunnel{Tunnel: t}
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
		// The MITM path failed; do not drop the connection silently, hand it
		// to the tunnel so it still routes.
		m.Tunnel.HandleTCPConn(conn, metadata)
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
