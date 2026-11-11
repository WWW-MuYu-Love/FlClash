package mitm

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

// TestEngineServeEndToEnd verifies the engine decrypts, intercepts, and
// records an exchange through Serve, the way the TUN wrapper hands it a
// connection.
func TestEngineServeEndToEnd(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")

	// A local HTTPS origin that echoes a marker header. It presents a proper
	// leaf certificate (CA:FALSE): the MITM handler needs a non-CA leaf in the
	// origin's chain to copy its SANs into the downstream certificate, and
	// httptest's own cert is a CA.
	origin := newLeafOrigin(t)
	defer origin.Close()
	originURL, _ := url.Parse(origin.URL)
	originHost := originURL.Host // 127.0.0.1:port

	engine := &Engine{
		exchange: NewExchangeStore(defaultCaptureEntries),
		config: Config{
			Enable: true, DecryptTLS: true, Hostname: []string{"127.0.0.1"},
			Capture: true, SkipServerCertVerify: true,
		},
		capture: true,
	}
	if err := engine.Init(); err != nil {
		t.Fatalf("Init: %v", err)
	}
	// The engine dials the origin directly (no mixed port in this test).

	// Client: dials the engine's transparent entry, trusts the MITM CA.
	caPool := x509.NewCertPool()
	caPEM, err := os.ReadFile(filepath.Join(home, dirName, caCertName))
	if err != nil {
		t.Fatalf("read CA: %v", err)
	}
	caPool.AppendCertsFromPEM(caPEM)
	entry, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer entry.Close()
	go func() {
		for {
			conn, err := entry.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				_ = engine.Serve(context.Background(), c, originHost)
			}(conn)
		}
	}()
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: caPool},
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return net.Dial("tcp", entry.Addr().String())
			},
		},
		Timeout: 10 * time.Second,
	}
	resp, err := client.Get("https://" + originHost + "/")
	if err != nil {
		t.Fatalf("GET through engine: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if string(body) != "hello" {
		t.Fatalf("body = %q, want hello", body)
	}
	if resp.Header.Get("X-Origin") != "ok" {
		t.Fatalf("missing X-Origin header")
	}
	// The exchange was recorded.
	list := engine.Exchanges("")
	if len(list.Exchanges) == 0 {
		t.Fatal("no exchange recorded")
	}
	ex := engine.Exchange(list.Exchanges[0].ID)
	if ex == nil || ex.Status != 200 {
		t.Fatalf("exchange = %+v, want status 200", ex)
	}
}

// newLeafOrigin starts an HTTPS server whose certificate is a leaf (CA:FALSE)
// for 127.0.0.1, so the MITM handler can copy its SANs.
func newLeafOrigin(t *testing.T) *httptest.Server {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("origin key: %v", err)
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		t.Fatalf("origin serial: %v", err)
	}
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "127.0.0.1"},
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		t.Fatalf("origin cert: %v", err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("origin key PEM: %v", err)
	}
	keyBlock := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyPEM})
	pair, err := tls.X509KeyPair(certPEM, keyBlock)
	if err != nil {
		t.Fatalf("origin key pair: %v", err)
	}
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Origin", "ok")
		_, _ = w.Write([]byte("hello"))
	}))
	server.TLS = &tls.Config{Certificates: []tls.Certificate{pair}}
	server.StartTLS()
	return server
}
