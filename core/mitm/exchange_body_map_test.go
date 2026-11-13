package mitm

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	mitmproxy "github.com/josexy/mitmproxy-go"
	"github.com/metacubex/mihomo/constant"
)

func testIntercept(t *testing.T, engine *Engine, req *http.Request, invoker mitmproxy.HTTPDelegatedInvoker) (*http.Response, *ExchangeStore) {
	t.Helper()
	s := NewExchangeStore(10)
	resp, err := s.Intercept(context.Background(), engine, req, invoker)
	if err != nil {
		t.Fatalf("Intercept: %v", err)
	}
	return resp, s
}

func TestBodyRewriteModifiesResponseBody(t *testing.T) {
	engine := &Engine{config: Config{BodyRewrite: []string{
		"http-response https://a.com/api foo bar",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("foo and foo")}
	resp, s := testIntercept(t, engine, req, invoker)
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading response body: %v", err)
	}
	if string(body) != "bar and bar" {
		t.Fatalf("body = %q, want bar and bar", body)
	}
	if resp.ContentLength != int64(len("bar and bar")) {
		t.Fatalf("ContentLength = %d, want %d", resp.ContentLength, len("bar and bar"))
	}
	if resp.Header.Get("Content-Length") != "11" {
		t.Fatalf("Content-Length header = %q, want 11", resp.Header.Get("Content-Length"))
	}
	ex := s.Get(s.List("", true).Exchanges[0].ID)
	if ex == nil {
		t.Fatal("exchange missing")
	}
	found := false
	for _, a := range ex.Actions {
		if a.Kind == "body-rewrite" && a.Phase == "response" {
			found = true
		}
	}
	if !found {
		t.Fatalf("actions = %v, want a body-rewrite action", ex.Actions)
	}
}

func TestBodyRewriteNoMatchLeavesBodyAlone(t *testing.T) {
	engine := &Engine{config: Config{BodyRewrite: []string{
		"http-response https://a.com/api foo bar",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://b.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://b.com/api")
	invoker := &captureInvoker{responseBody: []byte("foo")}
	resp, s := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "foo" {
		t.Fatalf("body = %q, want foo untouched", body)
	}
	if resp.ContentLength != 3 {
		t.Fatalf("ContentLength = %d, want 3 untouched", resp.ContentLength)
	}
	ex := s.Get(s.List("", true).Exchanges[0].ID)
	for _, a := range ex.Actions {
		if a.Kind == "body-rewrite" {
			t.Fatalf("actions = %v, want no body-rewrite action", ex.Actions)
		}
	}
}

func TestBodyRewriteRegexNoMatchLeavesBodyAlone(t *testing.T) {
	engine := &Engine{config: Config{BodyRewrite: []string{
		"http-response https://a.com/api zzz bar",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("foo")}
	resp, _ := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "foo" {
		t.Fatalf("body = %q, want foo untouched", body)
	}
	if resp.ContentLength != 3 {
		t.Fatalf("ContentLength = %d, want 3 untouched", resp.ContentLength)
	}
}

func TestBodyRewriteGzippedResponse(t *testing.T) {
	var gzipped bytes.Buffer
	w := gzip.NewWriter(&gzipped)
	_, _ = w.Write([]byte("foo foo"))
	_ = w.Close()
	engine := &Engine{config: Config{BodyRewrite: []string{
		"http-response https://a.com/api foo bar",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &gzipInvoker{body: gzipped.Bytes()}
	resp, _ := testIntercept(t, engine, req, invoker)
	if resp.Header.Get("Content-Encoding") != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip kept", resp.Header.Get("Content-Encoding"))
	}
	zr, err := gzip.NewReader(resp.Body)
	if err != nil {
		t.Fatalf("response body is not valid gzip: %v", err)
	}
	body, _ := io.ReadAll(zr)
	if string(body) != "bar bar" {
		t.Fatalf("decompressed body = %q, want bar bar", body)
	}
}

type gzipInvoker struct {
	body []byte
}

func (g *gzipInvoker) Invoke(req *http.Request) (*http.Response, error) {
	return &http.Response{
		Status:        "200 OK",
		StatusCode:    http.StatusOK,
		Proto:         "HTTP/1.1",
		Header:        http.Header{"Content-Encoding": {"gzip"}},
		Body:          io.NopCloser(bytes.NewReader(g.body)),
		ContentLength: int64(len(g.body)),
		Request:       req,
	}, nil
}

func TestBodyRewriteReplacementWithSpaces(t *testing.T) {
	engine := &Engine{config: Config{BodyRewrite: []string{
		`http-response https://a.com/api foo "hello world"`,
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("foo")}
	resp, _ := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "hello world" {
		t.Fatalf("body = %q, want hello world", body)
	}
}

func TestMapLocalServesFile(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	if err := os.MkdirAll(filepath.Join(home, "mitm", "resources"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "mitm", "resources", "mock.json"), []byte(`{"ok":true}`), 0o644); err != nil {
		t.Fatal(err)
	}
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=file data=mock.json",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, s := testIntercept(t, engine, req, invoker)
	if invoker.requestBytes != 0 {
		t.Fatalf("upstream saw %d request bytes, want 0 (map-local short-circuits)", invoker.requestBytes)
	}
	body, _ := io.ReadAll(resp.Body)
	if string(body) != `{"ok":true}` {
		t.Fatalf("body = %q, want the local file", body)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if resp.Header.Get("Content-Type") != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", resp.Header.Get("Content-Type"))
	}
	ex := s.Get(s.List("", true).Exchanges[0].ID)
	found := false
	for _, a := range ex.Actions {
		if a.Kind == "map-local" {
			found = true
		}
	}
	if !found {
		t.Fatalf("actions = %v, want a map-local action", ex.Actions)
	}
}

func TestMapLocalTextAndStatus(t *testing.T) {
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=text data=hello status-code=404",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, _ := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "hello" {
		t.Fatalf("body = %q, want hello", body)
	}
	if resp.StatusCode != 404 {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestMapLocalBase64(t *testing.T) {
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=base64 data=aGVsbG8=",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, _ := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "hello" {
		t.Fatalf("body = %q, want hello", body)
	}
}

func TestMapLocalMissingFileFallsThrough(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=file data=nope.json",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, s := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "upstream" {
		t.Fatalf("body = %q, want the upstream response (fall-through)", body)
	}
	ex := s.Get(s.List("", true).Exchanges[0].ID)
	found := false
	for _, a := range ex.Actions {
		if a.Kind == "map-local" {
			found = true
		}
	}
	if !found {
		t.Fatalf("actions = %v, want a map-local fall-through action", ex.Actions)
	}
}

func TestMapLocalNoMatchGoesUpstream(t *testing.T) {
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=text data=hello",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://b.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://b.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, s := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "upstream" {
		t.Fatalf("body = %q, want upstream", body)
	}
	ex := s.Get(s.List("", true).Exchanges[0].ID)
	for _, a := range ex.Actions {
		if a.Kind == "map-local" {
			t.Fatalf("actions = %v, want no map-local action", ex.Actions)
		}
	}
}

func TestMapLocalEscapingPathFallsThrough(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	engine := &Engine{config: Config{MapLocal: []string{
		"https://a.com/api data-type=file data=../ca.crt",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/api")
	invoker := &captureInvoker{responseBody: []byte("upstream")}
	resp, _ := testIntercept(t, engine, req, invoker)
	body, _ := io.ReadAll(resp.Body)
	if string(body) != "upstream" {
		t.Fatalf("body = %q, want upstream (escaping path must not be served)", body)
	}
}
