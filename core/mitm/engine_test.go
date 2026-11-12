package mitm

import (
	"bytes"
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
	"strconv"
	"sync/atomic"
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
	origin := newLeafOrigin(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Origin", "ok")
		_, _ = w.Write([]byte("hello"))
	}))
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
func newLeafOrigin(t *testing.T, handler http.HandlerFunc) *httptest.Server {
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
	server := httptest.NewUnstartedServer(handler)
	server.TLS = &tls.Config{Certificates: []tls.Certificate{pair}}
	server.StartTLS()
	return server
}

// dialEngineClient listens on a transparent entry that hands connections to
// the engine, and returns an HTTPS client trusting the MITM CA that dials
// through it.
func dialEngineClient(t *testing.T, home, originHost string, engine *Engine) *http.Client {
	t.Helper()
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
	t.Cleanup(func() { entry.Close() })
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
	return &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{RootCAs: caPool},
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return net.Dial("tcp", entry.Addr().String())
			},
		},
		Timeout: 10 * time.Second,
	}
}

// TestEngineServeLargeBodiesEndToEnd pins the #28 fix through a real Serve:
// a 2 MiB upload reaches the origin whole and a 2 MiB download reaches the
// client whole, while the recorded exchange keeps only a 1 MiB prefix per side.
func TestEngineServeLargeBodiesEndToEnd(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")

	const bodySize = 2 << 20
	big := bytes.Repeat([]byte("a"), bodySize)
	origin := newLeafOrigin(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/big":
			w.Header().Set("Content-Type", "application/octet-stream")
			w.Header().Set("Content-Length", strconv.Itoa(bodySize))
			_, _ = w.Write(big)
		case "/upload":
			got, _ := io.ReadAll(r.Body)
			w.Header().Set("X-Received", strconv.Itoa(len(got)))
			_, _ = w.Write([]byte("ok"))
		default:
			http.NotFound(w, r)
		}
	}))
	defer origin.Close()
	originURL, _ := url.Parse(origin.URL)
	originHost := originURL.Host

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
	client := dialEngineClient(t, home, originHost, engine)

	resp, err := client.Get("https://" + originHost + "/big")
	if err != nil {
		t.Fatalf("GET through engine: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if len(body) != bodySize {
		t.Fatalf("GET body = %d bytes, want %d", len(body), bodySize)
	}
	if resp.ContentLength != bodySize {
		t.Fatalf("GET ContentLength = %d, want %d", resp.ContentLength, bodySize)
	}

	resp, err = client.Post("https://"+originHost+"/upload", "application/octet-stream", bytes.NewReader(big))
	if err != nil {
		t.Fatalf("POST through engine: %v", err)
	}
	body, _ = io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if string(body) != "ok" {
		t.Fatalf("POST body = %q, want ok", body)
	}
	if resp.Header.Get("X-Received") != strconv.Itoa(bodySize) {
		t.Fatalf("origin received %s bytes, want %d", resp.Header.Get("X-Received"), bodySize)
	}

	list := engine.Exchanges("")
	if len(list.Exchanges) != 2 {
		t.Fatalf("exchanges = %d, want 2", len(list.Exchanges))
	}
	var getEx, postEx *Exchange
	for _, summary := range list.Exchanges {
		ex := engine.Exchange(summary.ID)
		switch {
		case ex.Method == http.MethodGet:
			getEx = ex
		case ex.Method == http.MethodPost:
			postEx = ex
		}
	}
	if getEx == nil || postEx == nil {
		t.Fatalf("exchanges = %+v, want one GET and one POST", list.Exchanges)
	}
	if getEx.Pending || postEx.Pending {
		t.Fatal("an exchange is still pending after both bodies closed")
	}
	if !getEx.responseTruncated || getEx.ResponseSize != bodySize {
		t.Fatalf("GET response = size %d truncated=%v, want %d true", getEx.ResponseSize, getEx.responseTruncated, bodySize)
	}
	if getEx.RequestSize != 0 || getEx.requestTruncated {
		t.Fatalf("GET request = size %d truncated=%v, want 0 false", getEx.RequestSize, getEx.requestTruncated)
	}
	if !postEx.requestTruncated || postEx.RequestSize != bodySize {
		t.Fatalf("POST request = size %d truncated=%v, want %d true", postEx.RequestSize, postEx.requestTruncated, bodySize)
	}
	if postEx.ResponseSize != 2 || postEx.responseTruncated {
		t.Fatalf("POST response = size %d truncated=%v, want 2 false", postEx.ResponseSize, postEx.responseTruncated)
	}
}

type fakeMitmHandler struct {
	cleanups atomic.Int32
}

func (f *fakeMitmHandler) CACertPath() string { return "" }

func (f *fakeMitmHandler) Serve(ctx context.Context, conn net.Conn) error { return nil }

func (f *fakeMitmHandler) ServeSOCKS5(ctx context.Context, conn net.Conn) error { return nil }

func (f *fakeMitmHandler) ServeHTTP(w http.ResponseWriter, req *http.Request) {}

func (f *fakeMitmHandler) Cleanup() { f.cleanups.Add(1) }

// TestHandlerRefDefersCleanupUntilDrained pins the #32 fix: retiring a
// generation with a Serve in flight must not clean it up until that Serve
// releases it, and a retired generation refuses new Serves.
func TestHandlerRefDefersCleanupUntilDrained(t *testing.T) {
	fake := &fakeMitmHandler{}
	ref := &handlerRef{handler: fake}
	if !ref.acquire() {
		t.Fatal("acquire on a fresh generation failed")
	}
	ref.retire()
	if got := fake.cleanups.Load(); got != 0 {
		t.Fatalf("cleanups = %d with a Serve still in flight, want 0", got)
	}
	if ref.acquire() {
		t.Fatal("acquire on a retired generation succeeded")
	}
	ref.release()
	if got := fake.cleanups.Load(); got != 1 {
		t.Fatalf("cleanups = %d, want 1", got)
	}

	idle := &handlerRef{handler: fake}
	idle.retire()
	if got := fake.cleanups.Load(); got != 2 {
		t.Fatalf("cleanups = %d after retiring an idle generation, want 2", got)
	}
}

// A stored pair that no longer parses is renamed aside before a fresh CA replaces it.
func TestEngineInitBacksUpCorruptCA(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	dir := filepath.Join(home, dirName)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, caCertName), []byte("not a cert"), 0o644); err != nil {
		t.Fatalf("write cert: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, caKeyName), []byte("not a key"), 0o600); err != nil {
		t.Fatalf("write key: %v", err)
	}
	engine := &Engine{exchange: NewExchangeStore(defaultCaptureEntries)}
	if err := engine.Init(); err != nil {
		t.Fatalf("Init: %v", err)
	}
	if got, err := os.ReadFile(filepath.Join(dir, caCertName+".bak")); err != nil || string(got) != "not a cert" {
		t.Fatalf("ca.crt.bak = %q, err %v, want the corrupt cert", got, err)
	}
	if got, err := os.ReadFile(filepath.Join(dir, caKeyName+".bak")); err != nil || string(got) != "not a key" {
		t.Fatalf("ca.key.bak = %q, err %v, want the corrupt key", got, err)
	}
	if engine.Certificate() == nil {
		t.Fatal("no fresh CA after backing up the corrupt one")
	}
}
