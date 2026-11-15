package mitm

import (
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestMatchURLPattern(t *testing.T) {
	cases := []struct {
		pattern string
		rawurl  string
		want    bool
	}{
		// The caret anchor a plain prefix match could never satisfy.
		{"^https://httpbin.org/flclash-test", "https://httpbin.org/flclash-test", true},
		{"^https://httpbin.org/flclash-test", "https://httpbin.org/flclash-test2", true},
		{"^https://a.com/api$", "https://a.com/api", true},
		{"^https://a.com/api$", "https://a.com/api/v2", false},
		{"https://a.com/api", "https://a.com/api", true},
		{"https://a.com/api", "https://a.com/api?x=1", true},
		{"https://a.com/api", "https://a.com/other", false},
		{"*", "https://anything.example/", true},
		// Not a valid regex: fall back to a prefix match.
		{"[", "[abc", true},
		{"[", "abc", false},
		{"https://a.com/ap(i", "https://a.com/ap(i", true},
	}
	for _, tc := range cases {
		if got := matchURLPattern(tc.pattern, tc.rawurl); got != tc.want {
			t.Errorf("matchURLPattern(%q, %q) = %v, want %v", tc.pattern, tc.rawurl, got, tc.want)
		}
	}
}

func TestMapLocalMatchesCaretPattern(t *testing.T) {
	engine := &Engine{config: Config{MapLocal: []string{
		"^https://a.com/api data-type=text data=hello",
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
	if string(body) != "hello" {
		t.Fatalf("body = %q, want hello", body)
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
