package mitm

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExchangeStoreDiskPersistsBodies(t *testing.T) {
	dir := t.TempDir()
	s := NewExchangeStoreWithDir(10, dir)
	ex := &Exchange{
		ID: 1, Method: "GET", URL: "https://example.com/",
		Connection: "1", requestBody: []byte("request"),
		responseBody: []byte("response"), Status: 200,
	}
	s.add(ex)
	s.complete(ex)
	if ex.requestBody != nil || ex.responseBody != nil {
		t.Fatalf("complete() kept bodies in memory")
	}
	if _, err := os.Stat(filepath.Join(dir, "1.json")); err != nil {
		t.Fatalf("meta file missing: %v", err)
	}
	if got := s.Body(1, false); got == nil || got.Data != "cmVxdWVzdA==" {
		t.Fatalf("Body(request) = %+v, want base64 of request", got)
	}
	if got := s.Body(1, true); got == nil || got.Data != "cmVzcG9uc2U=" {
		t.Fatalf("Body(response) = %+v, want base64 of response", got)
	}
	loaded := NewExchangeStoreWithDir(10, dir)
	if list := loaded.ListByHost("example.com", true); len(list.Exchanges) != 1 {
		t.Fatalf("reloaded ListByHost() = %d exchanges, want 1", len(list.Exchanges))
	}
	if got := loaded.Get(1); got == nil || got.URL != "https://example.com/" {
		t.Fatalf("reloaded Get(1) = %+v, want the exchange", got)
	}
	if got := loaded.Body(1, true); got == nil || got.Data != "cmVzcG9uc2U=" {
		t.Fatalf("reloaded Body(response) = %+v, want base64 of response", got)
	}
}

func TestExchangeStoreDiskEvictAndClearRemoveFiles(t *testing.T) {
	dir := t.TempDir()
	s := NewExchangeStoreWithDir(1, dir)
	first := &Exchange{ID: 1, URL: "https://a.test/", Connection: "1"}
	second := &Exchange{ID: 2, URL: "https://b.test/", Connection: "2"}
	s.add(first)
	s.complete(first)
	s.add(second)
	s.complete(second)
	if _, err := os.Stat(filepath.Join(dir, "1.json")); !os.IsNotExist(err) {
		t.Fatalf("evicted exchange file still exists")
	}
	if _, err := os.Stat(filepath.Join(dir, "2.json")); err != nil {
		t.Fatalf("kept exchange file missing: %v", err)
	}
	s.Clear()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 0 {
		t.Fatalf("Clear() left %d files", len(entries))
	}
}

func TestExchangeStoreWithoutDirKeepsBodiesInMemory(t *testing.T) {
	s := NewExchangeStore(10)
	ex := &Exchange{
		ID: 1, URL: "https://example.com/", Connection: "1",
		requestBody: []byte("request"), Status: 200,
	}
	s.add(ex)
	s.complete(ex)
	if got := s.Body(1, false); got == nil || got.Data != "cmVxdWVzdA==" {
		t.Fatalf("Body(request) = %+v, want base64 of request", got)
	}
}
