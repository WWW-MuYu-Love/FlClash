package mitm

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"testing"
)

type recordingInvoker struct {
	responseBody []byte
	requestBytes int
	seenURL      string
}

func (f *recordingInvoker) Invoke(req *http.Request) (*http.Response, error) {
	f.seenURL = req.URL.String()
	body, _ := io.ReadAll(req.Body)
	f.requestBytes = len(body)
	return &http.Response{
		Status:        "200 OK",
		StatusCode:    http.StatusOK,
		Proto:         "HTTP/1.1",
		Header:        http.Header{},
		Body:          io.NopCloser(bytes.NewReader(f.responseBody)),
		ContentLength: int64(len(f.responseBody)),
		Request:       req,
	}, nil
}

func runIntercept(t *testing.T, engine *Engine, rawURL, reqBody, respBody string) *recordingInvoker {
	t.Helper()
	invoker := &recordingInvoker{responseBody: []byte(respBody)}
	req := httptest.NewRequest(http.MethodPost, rawURL, bytes.NewReader([]byte(reqBody)))
	req.RequestURI = ""
	req.URL, _ = url.Parse(rawURL)
	req.ContentLength = int64(len(reqBody))
	resp, err := engine.intercept(context.Background(), req, invoker)
	if err != nil {
		t.Fatalf("intercept %s: %v", rawURL, err)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading response body: %v", err)
	}
	if err := resp.Body.Close(); err != nil {
		t.Fatalf("closing response body: %v", err)
	}
	if string(body) != respBody {
		t.Fatalf("client saw %q, want %q", body, respBody)
	}
	if invoker.requestBytes != len(reqBody) {
		t.Fatalf("upstream saw %d request bytes, want %d", invoker.requestBytes, len(reqBody))
	}
	return invoker
}

func TestInterceptCaptureOffMarksHostWithoutRecording(t *testing.T) {
	dir := t.TempDir()
	engine := &Engine{
		exchange: NewExchangeStoreWithDir(10, dir),
		config:   Config{URLRewrite: []string{"https://example.com/upload https://example.com/rewritten"}},
	}
	engine.SetCapture(false)
	invoker := runIntercept(t, engine, "https://example.com/upload", "hello", "world")
	if invoker.seenURL != "https://example.com/rewritten" {
		t.Fatalf("upstream URL = %q, want the rewritten URL", invoker.seenURL)
	}
	if list := engine.Exchanges(""); len(list.Exchanges) != 0 {
		t.Fatalf("Exchanges() = %d, want 0", len(list.Exchanges))
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("capture dir holds %d entries, want none", len(entries))
	}
	if got := engine.DecryptedHosts().Hosts; !reflect.DeepEqual(got, []string{"example.com"}) {
		t.Fatalf("DecryptedHosts() = %v, want [example.com]", got)
	}
}

func TestInterceptCaptureOnStillRecords(t *testing.T) {
	dir := t.TempDir()
	engine := &Engine{exchange: NewExchangeStoreWithDir(10, dir)}
	engine.SetCapture(true)
	runIntercept(t, engine, "https://example.com/upload", "hello", "world")
	if list := engine.Exchanges(""); len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d, want 1", len(list.Exchanges))
	}
	if got := engine.DecryptedHosts().Hosts; !reflect.DeepEqual(got, []string{"example.com"}) {
		t.Fatalf("DecryptedHosts() = %v, want [example.com]", got)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) == 0 {
		t.Fatal("capture dir holds no entries, want the persisted exchange")
	}
}

func TestDecryptedHostsUnionsStoredAndUncaptured(t *testing.T) {
	dir := t.TempDir()
	first := &Engine{exchange: NewExchangeStoreWithDir(10, dir)}
	first.SetCapture(true)
	runIntercept(t, first, "https://old.example/a", "hello", "world")
	second := &Engine{exchange: NewExchangeStoreWithDir(10, dir)}
	second.SetCapture(false)
	runIntercept(t, second, "https://new.example/b", "hello", "world")
	if list := second.Exchanges(""); len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d, want 1 (only the stored one)", len(list.Exchanges))
	}
	want := []string{"new.example", "old.example"}
	if got := second.DecryptedHosts().Hosts; !reflect.DeepEqual(got, want) {
		t.Fatalf("DecryptedHosts() = %v, want %v", got, want)
	}
}
