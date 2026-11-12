package tun

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"testing"
	"time"

	"core/mitm"

	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/common/utils"
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

// Regression test: the TUN stack hands HandleTCPConn a raw connection,
// never a BufferedConn, so sniffSNI used to see nothing and no connection
// was ever diverted to the engine. The wrapper must wrap the connection
// before sniffing and hand the wrapped connection downstream, or the
// peeked ClientHello would be lost.
func TestHandleTCPConnPassesWrappedConnectionThrough(t *testing.T) {
	mitm.Default().SetConfig(&mitm.Config{
		Enable:     true,
		DecryptTLS: true,
		Hostname:   []string{"example.com"},
	})
	t.Cleanup(func() { mitm.Default().SetConfig(nil) })

	inner := &recordingTunnel{}
	wrapped := WrapTunnel(inner)

	// The SNI is not in the hostname list, so the connection passes
	// through to the real tunnel.
	hello := makeTestTLSRecords(makeTestClientHello("other.com"))
	conn := &bufferConn{buf: bytes.NewBuffer(hello)}
	wrapped.HandleTCPConn(conn, &C.Metadata{DstPort: 443})

	received := inner.received
	if received == nil {
		t.Fatal("inner tunnel never received the connection")
	}
	bc, ok := received.(*N.BufferedConn)
	if !ok {
		t.Fatalf("inner tunnel received %T, want *N.BufferedConn", received)
	}
	head := make([]byte, 3)
	if _, err := io.ReadFull(bc, head); err != nil {
		t.Fatalf("reading peeked bytes: %v", err)
	}
	if head[0] != 0x16 || head[1] != 0x03 || head[2] != 0x01 {
		t.Fatalf("peeked bytes lost: got %x", head)
	}
}

func TestSniffSNIFromWrappedRawConnection(t *testing.T) {
	hello := makeTestTLSRecords(makeTestClientHello("example.com"))
	bc := N.NewBufferedConn(&bufferConn{buf: bytes.NewBuffer(hello)})
	if got := sniffSNI(bc); got != "example.com" {
		t.Fatalf("sniffSNI = %q, want example.com", got)
	}
}

type recordingTunnel struct {
	received net.Conn
}

func (f *recordingTunnel) HandleTCPConn(conn net.Conn, metadata *C.Metadata) {
	f.received = conn
}

func (f *recordingTunnel) HandleUDPPacket(packet C.UDPPacket, metadata *C.Metadata) {
}

func (f *recordingTunnel) NatTable() C.NatTable { return nil }

func (f *recordingTunnel) Providers() map[string]P.ProxyProvider { return nil }

func (f *recordingTunnel) RuleProviders() map[string]P.RuleProvider { return nil }

func (f *recordingTunnel) RuleUpdateCallback() *utils.Callback[P.RuleProvider] { return nil }

type bufferConn struct {
	buf *bytes.Buffer
}

func (c *bufferConn) Read(b []byte) (int, error)         { return c.buf.Read(b) }
func (c *bufferConn) Write(b []byte) (int, error)        { return len(b), nil }
func (c *bufferConn) Close() error                       { return nil }
func (c *bufferConn) LocalAddr() net.Addr                { return &net.TCPAddr{IP: net.IPv4zero} }
func (c *bufferConn) RemoteAddr() net.Addr               { return &net.TCPAddr{IP: net.IPv4zero, Port: 443} }
func (c *bufferConn) SetDeadline(t time.Time) error      { return nil }
func (c *bufferConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *bufferConn) SetWriteDeadline(t time.Time) error { return nil }

func makeTestClientHello(host string) []byte {
	var extensions []byte
	if host != "" {
		serverName := []byte(host)
		serverNameListLen := 1 + 2 + len(serverName)
		extensionDataLen := 2 + serverNameListLen
		extensions = make([]byte, 4+extensionDataLen)
		binary.BigEndian.PutUint16(extensions[2:4], uint16(extensionDataLen))
		binary.BigEndian.PutUint16(extensions[4:6], uint16(serverNameListLen))
		binary.BigEndian.PutUint16(extensions[7:9], uint16(len(serverName)))
		copy(extensions[9:], serverName)
	}
	body := make([]byte, 0, 64+len(host))
	body = append(body, 0x03, 0x03)
	body = append(body, make([]byte, 32)...)
	body = append(body, 0)
	body = append(body, 0, 2, 0x13, 0x01)
	body = append(body, 1, 0)
	body = binary.BigEndian.AppendUint16(body, uint16(len(extensions)))
	body = append(body, extensions...)
	hello := []byte{0x01, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}
	return append(hello, body...)
}

func makeTestTLSRecords(handshake []byte) []byte {
	header := []byte{0x16, 0x03, 0x01, 0, 0}
	binary.BigEndian.PutUint16(header[3:], uint16(len(handshake)))
	return append(header, handshake...)
}
