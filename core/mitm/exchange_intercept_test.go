package mitm

import (
	"bytes"
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

type captureInvoker struct {
	requestBytes int
	responseBody []byte
}

func (f *captureInvoker) Invoke(req *http.Request) (*http.Response, error) {
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

// TestInterceptStreamsLargeBodies pins the #28 fix: bodies over 1 MiB are
// forwarded whole, with their ContentLength untouched, while only a 1 MiB
// prefix is recorded.
func TestInterceptStreamsLargeBodies(t *testing.T) {
	s := NewExchangeStore(10)
	engine := &Engine{}

	const bodySize = 2 << 20
	payload := bytes.Repeat([]byte("a"), bodySize)
	invoker := &captureInvoker{responseBody: payload}
	req := httptest.NewRequest(http.MethodPost, "https://example.com/upload", bytes.NewReader(payload))
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://example.com/upload")
	req.ContentLength = bodySize

	resp, err := s.Intercept(context.Background(), engine, req, invoker)
	if err != nil {
		t.Fatalf("Intercept: %v", err)
	}
	if req.ContentLength != bodySize {
		t.Fatalf("request ContentLength = %d, want %d (rewritten)", req.ContentLength, bodySize)
	}
	if invoker.requestBytes != bodySize {
		t.Fatalf("upstream saw %d request bytes, want %d", invoker.requestBytes, bodySize)
	}
	if resp.ContentLength != bodySize {
		t.Fatalf("response ContentLength = %d, want %d (rewritten)", resp.ContentLength, bodySize)
	}
	list := s.List("", true)
	if len(list.Exchanges) != 1 {
		t.Fatalf("List() = %d exchanges, want 1", len(list.Exchanges))
	}
	ex := s.Get(list.Exchanges[0].ID)
	if ex == nil {
		t.Fatal("exchange missing")
	}
	if !ex.Pending {
		t.Fatal("exchange completed before the response body was read")
	}
	if ex.ResponseSize != 0 {
		t.Fatalf("ResponseSize = %d while streaming, want 0", ex.ResponseSize)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading response body: %v", err)
	}
	if len(body) != bodySize {
		t.Fatalf("client saw %d response bytes, want %d", len(body), bodySize)
	}
	if err := resp.Body.Close(); err != nil {
		t.Fatalf("closing response body: %v", err)
	}
	ex = s.Get(list.Exchanges[0].ID)
	if ex == nil {
		t.Fatal("exchange missing after close")
	}
	if ex.Pending {
		t.Fatal("exchange still pending after the response body closed")
	}
	// complete() drops the bodies from memory once persisted, so their lengths
	// are checked through Body(), which reads them back from disk.
	if !ex.requestTruncated {
		t.Fatal("requestTruncated = false, want true")
	}
	if ex.RequestSize != bodySize {
		t.Fatalf("RequestSize = %d, want %d", ex.RequestSize, bodySize)
	}
	if !ex.responseTruncated {
		t.Fatal("responseTruncated = false, want true")
	}
	if ex.ResponseSize != bodySize {
		t.Fatalf("ResponseSize = %d, want %d", ex.ResponseSize, bodySize)
	}
	if got := s.Body(ex.ID, false); got == nil || !got.Truncated {
		t.Fatalf("Body(request) = %+v, want truncated", got)
	} else if decoded, err := base64.StdEncoding.DecodeString(got.Data); err != nil || len(decoded) != maxRecordedBody {
		t.Fatalf("Body(request) decoded %d bytes, want %d", len(decoded), maxRecordedBody)
	}
	if got := s.Body(ex.ID, true); got == nil || !got.Truncated {
		t.Fatalf("Body(response) = %+v, want truncated", got)
	} else if decoded, err := base64.StdEncoding.DecodeString(got.Data); err != nil || len(decoded) != maxRecordedBody {
		t.Fatalf("Body(response) decoded %d bytes, want %d", len(decoded), maxRecordedBody)
	}
}

func TestInterceptKeepsSmallBodies(t *testing.T) {
	s := NewExchangeStore(10)
	engine := &Engine{}
	invoker := &captureInvoker{responseBody: []byte("hello")}
	req := httptest.NewRequest(http.MethodGet, "https://example.com/", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://example.com/")

	resp, err := s.Intercept(context.Background(), engine, req, invoker)
	if err != nil {
		t.Fatalf("Intercept: %v", err)
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if string(body) != "hello" {
		t.Fatalf("body = %q, want hello", body)
	}
	list := s.List("", true)
	ex := s.Get(list.Exchanges[0].ID)
	if ex == nil || ex.Pending {
		t.Fatalf("exchange = %+v, want completed", ex)
	}
	if ex.requestTruncated || ex.responseTruncated {
		t.Fatalf("truncated flags = %v/%v, want false/false", ex.requestTruncated, ex.responseTruncated)
	}
	if ex.RequestSize != 0 || ex.ResponseSize != 5 {
		t.Fatalf("sizes = %d/%d, want 0/5", ex.RequestSize, ex.ResponseSize)
	}
}
