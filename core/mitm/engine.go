// Package mitm wires an open-source MITM engine (josexy/mitmproxy-go) into
// the FlClash core. The engine decrypts TLS for hostnames the user lists,
// runs the interceptor chain (rewrite rules, exchange capture), and dials the
// origin through the core's mixed port (SOCKS5), so MITM traffic follows the
// same route a direct connection would take.
//
// The upstream dial goes through the mixed port as SOCKS5, not as TLS, so
// the tunnel wrapper that hands connections to this engine never sees the
// engine's own upstream connection as a MITM target and cannot loop on it.
//
// The CA lives under <home>/mitm/ as ca.crt/ca.key and is reused across
// restarts, so a device that already trusts it keeps trusting it.
// Completed captures live under <home>/mitm/captures/ instead of in the
// extension's memory; only in-flight exchanges and summaries are kept.
package mitm

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	mitmproxy "github.com/josexy/mitmproxy-go"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

const (
	// dirName is the home-relative directory for the CA and MITM state.
	dirName = "mitm"
	// caCertName and caKeyName are the stored CA certificate and key.
	caCertName = "ca.crt"
	caKeyName  = "ca.key"
	// defaultCaptureEntries bounds the exchange store when the config names
	// no limit.
	defaultCaptureEntries = 2000
)

// Config is the MITM section of the applied Clash config, as the app sends
// it (see Mitm.coreJson). Hostname lines use Surge syntax: a leading '-'
// excludes the host, and '*' matches a whole label. Capture itself arrives
// separately, via CoreOptions.MITMCapture.
type Config struct {
	Enable               bool     `json:"enable" yaml:"enable"`
	Hostname             []string `json:"hostname" yaml:"hostname"`
	URLRewrite           []string `json:"url-rewrite" yaml:"url-rewrite"`
	HeaderRewrite        []string `json:"header-rewrite" yaml:"header-rewrite"`
	BodyRewrite          []string `json:"body-rewrite" yaml:"body-rewrite"`
	MapLocal             []string `json:"map-local" yaml:"map-local"`
	Script               []string `json:"script" yaml:"script"`
	DecryptTLS           bool     `json:"decrypt-tls" yaml:"decrypt-tls"`
	SkipServerCertVerify bool     `json:"skip-server-cert-verify" yaml:"skip-server-cert-verify"`
	AutoQUICBlock        bool     `json:"auto-quic-block" yaml:"auto-quic-block"`
	H2                   bool     `json:"h2" yaml:"h2"`
	Limits               Limits   `json:"limits" yaml:"limits"`
	Capture              bool     `json:"-" yaml:"-"`
	CaptureEntries       int      `json:"-" yaml:"-"`
}

// Limits holds the MITM resource limits from the config.
type Limits struct {
	CaptureEntries int `json:"capture-entries" yaml:"capture-entries"`
}

// Engine owns the MITM handler and its state. All methods are safe for
// concurrent use.
type Engine struct {
	mu        sync.RWMutex
	homeDir   string
	ca        *tls.Certificate
	caCert    *x509.Certificate
	handler   mitmproxy.MitmProxyHandler
	config    Config
	mixedPort int
	capture   bool
	exchange  *ExchangeStore
	closed    bool
}

// Default returns the process-wide engine, creating it on first use.
var (
	defaultMu sync.Mutex
	defEngine *Engine
)

// Default returns the process-wide engine.
func Default() *Engine {
	defaultMu.Lock()
	defer defaultMu.Unlock()
	if defEngine == nil {
		defEngine = &Engine{exchange: NewExchangeStore(defaultCaptureEntries)}
	}
	return defEngine
}

// HomeDir returns the directory the engine stores its CA in.
func (e *Engine) HomeDir() string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.homeDir != "" {
		return e.homeDir
	}
	return filepath.Join(constant.Path.HomeDir(), dirName)
}

// Init loads the stored CA, generating one when none exists, and (re)builds
// the handler. It is idempotent.
func (e *Engine) Init() error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return errors.New("mitm engine closed")
	}
	homeDir := filepath.Join(constant.Path.HomeDir(), dirName)
	if err := os.MkdirAll(homeDir, 0o700); err != nil {
		return fmt.Errorf("mitm home: %w", err)
	}
	e.homeDir = homeDir
	e.exchange.SetDir(filepath.Join(homeDir, capturesDirName))
	if err := e.loadOrGenerateCA(); err != nil {
		return err
	}
	return e.rebuildHandlerLocked()
}

// loadOrGenerateCA reads the stored CA or generates and stores a new one.
func (e *Engine) loadOrGenerateCA() error {
	certPath := filepath.Join(e.homeDir, caCertName)
	keyPath := filepath.Join(e.homeDir, caKeyName)
	certPEM, certErr := os.ReadFile(certPath)
	keyPEM, keyErr := os.ReadFile(keyPath)
	if certErr == nil && keyErr == nil {
		pair, err := tls.X509KeyPair(certPEM, keyPEM)
		if err == nil {
			if leaf, err := x509.ParseCertificate(pair.Certificate[0]); err == nil && leaf.IsCA {
				e.ca = &pair
				e.caCert = leaf
				return nil
			}
		}
	}
	return e.generateCALocked()
}

// generateCALocked creates a fresh CA, stores it, and keeps it in memory.
// The caller must hold e.mu.
func (e *Engine) generateCALocked() error {
	ca, leaf, err := GenerateCA()
	if err != nil {
		return err
	}
	certPEM := pemEncodeCert(leaf.Raw)
	keyPEM, err := pemEncodeKey(ca)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(e.homeDir, caCertName), certPEM, 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(e.homeDir, caKeyName), keyPEM, 0o600); err != nil {
		return err
	}
	pair, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		return err
	}
	e.ca = &pair
	e.caCert = leaf
	return nil
}

// GenerateCertificate replaces the CA with a fresh one and rebuilds the
// handler, then returns the new CA's description.
func (e *Engine) GenerateCertificate() (*Certificate, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.closed {
		return nil, errors.New("mitm engine closed")
	}
	if e.homeDir == "" {
		e.homeDir = filepath.Join(constant.Path.HomeDir(), dirName)
		if err := os.MkdirAll(e.homeDir, 0o700); err != nil {
			return nil, err
		}
	}
	if err := e.generateCALocked(); err != nil {
		return nil, err
	}
	if err := e.rebuildHandlerLocked(); err != nil {
		return nil, err
	}
	return DescribeCertificate(e.caCert), nil
}

// Certificate returns the current CA, or nil when none exists yet.
func (e *Engine) Certificate() *Certificate {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if e.caCert == nil {
		return nil
	}
	return DescribeCertificate(e.caCert)
}

// SetMixedPort records the core's mixed port, which the engine dials as a
// SOCKS5 upstream so MITM traffic follows the user's proxy selection. A zero
// port leaves the handler dialing direct.
func (e *Engine) SetMixedPort(port int) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.mixedPort == port {
		return nil
	}
	e.mixedPort = port
	if e.handler == nil {
		return nil
	}
	return e.rebuildHandlerLocked()
}

// rebuildHandlerLocked (re)creates the mitmproxy handler from the current CA
// and config. The caller must hold e.mu.
func (e *Engine) rebuildHandlerLocked() error {
	if e.handler != nil {
		e.handler.Cleanup()
		e.handler = nil
	}
	if e.ca == nil {
		return nil
	}
	certPath := filepath.Join(e.homeDir, caCertName)
	keyPath := filepath.Join(e.homeDir, caKeyName)
	opts := []mitmproxy.Option{
		mitmproxy.WithCACertPath(certPath),
		mitmproxy.WithCAKeyPath(keyPath),
		mitmproxy.WithHTTPInterceptor(e.intercept),
		mitmproxy.WithDialer(&net.Dialer{Timeout: 15 * time.Second}),
		mitmproxy.WithErrorHandler(func(ec mitmproxy.ErrorContext) {
			log.Warnln("[MITM] %s: %v", ec.Hostport, ec.Error)
		}),
	}
	// Route upstream through the mixed port so MITM traffic follows the
	// user's proxy selection instead of bypassing the nodes.
	if e.mixedPort > 0 {
		opts = append(opts, mitmproxy.WithProxy(fmt.Sprintf("socks5://127.0.0.1:%d", e.mixedPort)))
	}
	if e.config.SkipServerCertVerify {
		opts = append(opts, mitmproxy.WithSkipVerifySSLFromServer())
	}
	handler, err := mitmproxy.NewMitmProxyHandler(opts...)
	if err != nil {
		return fmt.Errorf("mitm handler: %w", err)
	}
	e.handler = handler
	return nil
}

// Serve hands a raw client connection to the MITM handler. The caller must
// have decided the connection is a MITM target and supplies its hostport.
// The connection is tagged with a fresh id so its exchanges can be listed.
// The handler is initialized lazily on first use.
func (e *Engine) Serve(ctx context.Context, conn net.Conn, hostport string) error {
	e.mu.RLock()
	handler := e.handler
	e.mu.RUnlock()
	if handler == nil {
		if err := e.Init(); err != nil {
			return err
		}
		e.mu.RLock()
		handler = e.handler
		e.mu.RUnlock()
	}
	if handler == nil {
		return errors.New("mitm handler not initialized")
	}
	connID := e.exchange.NextConnectionID()
	ctx = contextWithConnectionID(ctx, connID)
	ctx = mitmproxy.AppendToRequestContext(ctx, mitmproxy.ReqContext{Hostport: hostport})
	err := handler.Serve(ctx, conn)
	e.exchange.MarkClosed(connID)
	return err
}

// Enabled reports whether MITM interception is on for new connections.
func (e *Engine) Enabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.config.Enable && e.config.DecryptTLS
}

// ShouldIntercept reports whether host is in the MITM hostname list.
func (e *Engine) ShouldIntercept(host string) bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if !e.config.Enable || !e.config.DecryptTLS {
		return false
	}
	return matchHostnameList(e.config.Hostname, host)
}

// SetConfig replaces the MITM rules. A nil config disables MITM. The capture
// flag is not part of the config section (it arrives via CoreOptions), so it
// is preserved.
func (e *Engine) SetConfig(cfg *Config) {
	e.mu.Lock()
	defer e.mu.Unlock()
	capture := e.capture
	if cfg == nil {
		e.config = Config{}
	} else {
		e.config = *cfg
		if e.config.Limits.CaptureEntries > 0 {
			e.config.CaptureEntries = e.config.Limits.CaptureEntries
		}
	}
	e.config.Capture = capture
	e.capture = capture
	if e.exchange != nil {
		e.exchange.SetLimit(e.config.CaptureEntries)
	}
}

// SetCapture enables or disables exchange capture.
func (e *Engine) SetCapture(capture bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.capture = capture
	e.config.Capture = capture
}

// Capturing reports whether exchanges are being recorded.
func (e *Engine) Capturing() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.capture
}

// Exchanges returns the recorded exchanges for a connection.
func (e *Engine) Exchanges(connectionID string) *ExchangeList {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.exchange.List(connectionID, e.capture)
}

// DecryptedHosts returns the hosts with recorded exchanges.
func (e *Engine) DecryptedHosts() *HostList {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return &HostList{Hosts: e.exchange.Hosts()}
}

// ExchangesByHost returns the recorded exchanges for one host.
func (e *Engine) ExchangesByHost(host string) *ExchangeList {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.exchange.ListByHost(host, e.capture)
}

// Exchange returns one recorded exchange by id, or nil.
func (e *Engine) Exchange(id int) *Exchange {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.exchange.Get(id)
}

// Body returns one side of a recorded exchange as base64, or nil.
func (e *Engine) Body(id int, response bool) *Body {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.exchange.Body(id, response)
}

// ReleasePressure drops recorded exchanges to free memory under pressure.
// The CA and handler stay, so interception keeps working.
func (e *Engine) ReleasePressure() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.exchange != nil {
		e.exchange.Clear()
	}
}

// Close releases the handler. The stored CA is kept.
func (e *Engine) Close() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.closed = true
	if e.handler != nil {
		e.handler.Cleanup()
		e.handler = nil
	}
}

// intercept runs on every decrypted request. It records the exchange and
// applies the configured rewrites.
func (e *Engine) intercept(ctx context.Context, req *http.Request, invoker mitmproxy.HTTPDelegatedInvoker) (*http.Response, error) {
	return e.exchange.Intercept(ctx, e, req, invoker)
}
