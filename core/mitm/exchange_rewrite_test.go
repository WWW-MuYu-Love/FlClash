package mitm

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"sync"
	"testing"
)

func TestApplyHeaderRewrite(t *testing.T) {
	cases := []struct {
		name    string
		line    string
		phase   string
		rawURL  string
		before  http.Header
		want    http.Header
		applied bool
	}{
		{
			name: "canonical replace applies on a matching request", line: "http-request https://a.com header-replace X-Test: 1",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{"X-Test": {"old"}}, want: http.Header{"X-Test": {"1"}}, applied: true,
		},
		{
			name: "canonical replace keeps a value with spaces", line: "http-request https://a.com header-replace X-Test: hello world",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{"X-Test": {"hello world"}}, applied: true,
		},
		{
			name: "request rule does not fire on a response", line: "http-request https://a.com header-replace X-Test: 1",
			phase: "response", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
		{
			name: "response rule fires on a response", line: "http-response https://a.com header-replace X-Test: 2",
			phase: "response", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{"X-Test": {"2"}}, applied: true,
		},
		{
			name: "non-matching pattern does not fire", line: "http-request https://a.com header-replace X-Test: 1",
			phase: "request", rawURL: "https://b.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
		{
			name: "wildcard pattern matches any URL", line: "http-request * header-replace X-Test: 1",
			phase: "request", rawURL: "https://b.com/x",
			before: http.Header{}, want: http.Header{"X-Test": {"1"}}, applied: true,
		},
		{
			name: "add appends instead of replacing", line: "http-request https://a.com header-add X-Test: 1",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{"X-Test": {"old"}}, want: http.Header{"X-Test": {"old", "1"}}, applied: true,
		},
		{
			name: "del removes the header", line: "http-request https://a.com header-del X-Test",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{"X-Test": {"1"}, "X-Keep": {"k"}}, want: http.Header{"X-Keep": {"k"}}, applied: true,
		},
		{
			name: "replace-regex rewrites the value", line: "http-request https://a.com header-replace-regex X-Test: ^a(.*) b$1",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{"X-Test": {"aXYZ"}}, want: http.Header{"X-Test": {"bXYZ"}}, applied: true,
		},
		{
			name: "legacy two-field line replaces with its pattern matched", line: "https://a.com X-Test: 1",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{"X-Test": {"1"}}, applied: true,
		},
		{
			name: "legacy line does not fire off-pattern", line: "https://a.com X-Test: 1",
			phase: "request", rawURL: "https://b.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
		{
			name: "legacy line fires in the response phase too", line: "https://a.com X-Test: 1",
			phase: "response", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{"X-Test": {"1"}}, applied: true,
		},
		{
			name: "unknown action is ignored", line: "http-request https://a.com header-bogus X-Test: 1",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
		{
			name: "replace without a colon is ignored", line: "http-request https://a.com header-replace X-Test",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
		{
			name: "replace-regex with a bad regex is ignored", line: "http-request https://a.com header-replace-regex X-Test: [invalid",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{"X-Test": {"v"}}, want: http.Header{"X-Test": {"v"}}, applied: false,
		},
		{
			name: "short line is ignored", line: "http-request",
			phase: "request", rawURL: "https://a.com/x",
			before: http.Header{}, want: http.Header{}, applied: false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			header := c.before.Clone()
			if got := applyHeaderRewrite(header, c.line, c.phase, c.rawURL); got != c.applied {
				t.Fatalf("applyHeaderRewrite() = %v, want %v", got, c.applied)
			}
			if !reflect.DeepEqual(header, c.want) {
				t.Fatalf("header = %v, want %v", header, c.want)
			}
		})
	}
}

func TestHeaderRewriteActionsRespectPhaseAndPattern(t *testing.T) {
	engine := &Engine{config: Config{HeaderRewrite: []string{
		"http-request https://a.com header-replace X-Req: yes",
		"http-response https://a.com header-del X-Resp",
		"http-request https://b.com header-replace X-Other: no",
	}}}
	req := httptest.NewRequest(http.MethodGet, "https://a.com/x", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://a.com/x")

	actions := requestRewriteActions(engine, req)
	if req.Header.Get("X-Req") != "yes" {
		t.Fatalf("request X-Req = %q, want yes", req.Header.Get("X-Req"))
	}
	if len(actions) != 1 || actions[0].Phase != "request" {
		t.Fatalf("request actions = %+v, want one request action", actions)
	}

	resp := &http.Response{Header: http.Header{"X-Resp": {"v"}}, Request: req}
	actions = responseRewriteActions(engine, resp, "https://a.com/x")
	if _, ok := resp.Header["X-Resp"]; ok {
		t.Fatal("response X-Resp survived its header-del rule")
	}
	if len(actions) != 1 || actions[0].Phase != "response" {
		t.Fatalf("response actions = %+v, want one response action", actions)
	}

	resp = &http.Response{Header: http.Header{"X-Resp": {"v"}}, Request: req}
	if actions := responseRewriteActions(engine, resp, "https://other.com/x"); len(actions) != 0 {
		t.Fatalf("off-pattern response actions = %+v, want none", actions)
	}
	if _, ok := resp.Header["X-Resp"]; !ok {
		t.Fatal("off-pattern response rule deleted the header")
	}
}

func TestInterceptRecordsRewrittenURL(t *testing.T) {
	dir := t.TempDir()
	engine := &Engine{
		exchange: NewExchangeStoreWithDir(10, dir),
		config:   Config{URLRewrite: []string{"https://example.com/old https://example.com/new"}},
	}
	engine.SetCapture(true)
	invoker := runIntercept(t, engine, "https://example.com/old", "", "ok")
	if invoker.seenURL != "https://example.com/new" {
		t.Fatalf("upstream URL = %q, want the rewritten URL", invoker.seenURL)
	}
	list := engine.Exchanges("")
	if len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d, want 1", len(list.Exchanges))
	}
	ex := engine.Exchange(list.Exchanges[0].ID)
	if ex == nil {
		t.Fatal("exchange missing")
	}
	if ex.URL != "https://example.com/new" {
		t.Fatalf("URL = %q, want the rewritten URL", ex.URL)
	}
	if ex.OriginalURL != "https://example.com/old" {
		t.Fatalf("OriginalURL = %q, want the pre-rewrite URL", ex.OriginalURL)
	}
}

func TestClosedEntriesPrunedOnEvictAndClear(t *testing.T) {
	s := NewExchangeStore(2)
	s.add(&Exchange{ID: 1, Connection: "1", URL: "https://a.test/"})
	s.add(&Exchange{ID: 2, Connection: "2", URL: "https://b.test/"})
	s.MarkClosed("1")
	s.MarkClosed("2")
	s.MarkClosed("ghost")
	if list := s.List("ghost", true); list.Closed {
		t.Fatal("a connection with no exchange is reported closed")
	}
	if list := s.List("1", true); !list.Closed {
		t.Fatal("connection 1 is not reported closed")
	}
	s.add(&Exchange{ID: 3, Connection: "3", URL: "https://c.test/"})
	if list := s.List("1", true); list.Closed {
		t.Fatal("evicted connection 1 is still reported closed")
	}
	if list := s.List("2", true); !list.Closed {
		t.Fatal("live connection 2 lost its closed flag on eviction")
	}
	s.Clear()
	if list := s.List("2", true); list.Closed {
		t.Fatal("Clear() kept the closed flag")
	}
}

func TestSetPressureGrades(t *testing.T) {
	dir := t.TempDir()
	engine := &Engine{exchange: NewExchangeStoreWithDir(10, dir)}
	engine.SetCapture(true)
	runIntercept(t, engine, "https://example.com/a", "req", "resp")

	engine.SetPressure(1)
	runIntercept(t, engine, "https://example.com/b", "req2", "resp2")
	list := engine.Exchanges("")
	if len(list.Exchanges) != 2 {
		t.Fatalf("Exchanges() = %d, want 2 (metadata is still recorded)", len(list.Exchanges))
	}
	var bID int
	for _, summary := range list.Exchanges {
		if ex := engine.Exchange(summary.ID); ex != nil && ex.URL == "https://example.com/b" {
			bID = ex.ID
		}
	}
	if bID == 0 {
		t.Fatal("exchange for /b missing")
	}
	if got := engine.Body(bID, true); got == nil || got.Data != "" {
		t.Fatalf("Body(/b response) = %+v, want no recorded body at pressure level 1", got)
	}

	engine.SetPressure(3)
	if list := engine.Exchanges(""); len(list.Exchanges) != 0 {
		t.Fatalf("Exchanges() = %d after level 3, want 0", len(list.Exchanges))
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("capture dir holds %d entries after level 3, want none", len(entries))
	}

	runIntercept(t, engine, "https://example.com/c", "req3", "resp3")
	engine.SetPressure(3)
	if list := engine.Exchanges(""); len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d after a throttled repeat level 3, want 1", len(list.Exchanges))
	}

	engine.SetPressure(0)
	runIntercept(t, engine, "https://example.com/d", "req4", "resp4")
	list = engine.Exchanges("")
	var dID int
	for _, summary := range list.Exchanges {
		if ex := engine.Exchange(summary.ID); ex != nil && ex.URL == "https://example.com/d" {
			dID = ex.ID
		}
	}
	if got := engine.Body(dID, true); got == nil || got.Data != base64.StdEncoding.EncodeToString([]byte("resp4")) {
		t.Fatalf("Body(/d response) = %+v, want the recorded body once pressure clears", got)
	}
}

func TestSetPressureLevel2DropsRecordedBodies(t *testing.T) {
	engine := &Engine{exchange: NewExchangeStore(10)}
	engine.SetCapture(true)
	runIntercept(t, engine, "https://example.com/a", "req", "resp")
	list := engine.Exchanges("")
	if len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d, want 1", len(list.Exchanges))
	}
	id := list.Exchanges[0].ID
	if got := engine.Body(id, true); got == nil || got.Data == "" {
		t.Fatalf("Body() = %+v, want the recorded body before pressure", got)
	}
	engine.SetPressure(2)
	if got := engine.Body(id, true); got == nil || got.Data != "" {
		t.Fatalf("Body() = %+v, want the body dropped at pressure level 2", got)
	}
	if list := engine.Exchanges(""); len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d after level 2, want the metadata kept", len(list.Exchanges))
	}
}

// TestExchangeGetBodyConcurrent runs intercepts while Get/Body marshal the
// live exchanges: the readers must see a consistent snapshot, never a
// half-mutated exchange. Run with -race.
func TestExchangeGetBodyConcurrent(t *testing.T) {
	s := NewExchangeStore(100)
	engine := &Engine{}
	done := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		defer close(done)
		for i := 0; i < 50; i++ {
			invoker := &captureInvoker{responseBody: []byte("hello")}
			req := httptest.NewRequest(http.MethodGet, "https://example.com/", nil)
			req.RequestURI = ""
			req.URL, _ = url.Parse("https://example.com/")
			resp, err := s.Intercept(context.Background(), engine, req, invoker)
			if err != nil {
				return
			}
			_, _ = io.ReadAll(resp.Body)
			_ = resp.Body.Close()
		}
	}()
	for {
		select {
		case <-done:
			wg.Wait()
			return
		default:
			for _, summary := range s.List("", true).Exchanges {
				if ex := s.Get(summary.ID); ex == nil {
					t.Error("Get() returned nil for a listed exchange")
				}
				_ = s.Body(summary.ID, true)
				_ = s.Body(summary.ID, false)
			}
		}
	}
}
