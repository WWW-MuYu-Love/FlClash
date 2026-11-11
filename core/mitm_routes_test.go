package core

import (
	"encoding/json"
	"testing"

	"github.com/metacubex/http"
	"github.com/metacubex/http/httptest"
)

func TestMitmRoutes(t *testing.T) {
	// The routes read the process-wide engine, whose store is empty here:
	// they answer shapes, not recorded exchanges.
	get := func(handler http.HandlerFunc, target string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, target, nil)
		rec := httptest.NewRecorder()
		handler(rec, req)
		return rec
	}

	hosts := get(handleMitmHostsRoute, "/mitm/hosts")
	if hosts.Code != http.StatusOK {
		t.Fatalf("hosts status = %d, want 200", hosts.Code)
	}
	var hostList struct {
		Hosts []string `json:"hosts"`
	}
	if err := json.Unmarshal(hosts.Body.Bytes(), &hostList); err != nil {
		t.Fatalf("hosts body: %v", err)
	}
	if hostList.Hosts == nil {
		t.Errorf("hosts = nil, want an (empty) array")
	}

	changes := get(handleMitmExchangesRoute, "/mitm/exchanges?host=example.com")
	if changes.Code != http.StatusOK {
		t.Fatalf("exchanges status = %d, want 200", changes.Code)
	}
	var list struct {
		Exchanges []any `json:"exchanges"`
	}
	if err := json.Unmarshal(changes.Body.Bytes(), &list); err != nil {
		t.Fatalf("exchanges body: %v", err)
	}
	if len(list.Exchanges) != 0 {
		t.Errorf("exchanges = %v, want none", list.Exchanges)
	}

	if rec := get(handleMitmExchangeRoute, "/mitm/exchange?id=abc"); rec.Code != http.StatusBadRequest {
		t.Errorf("exchange bad id status = %d, want 400", rec.Code)
	}
	if rec := get(handleMitmExchangeRoute, "/mitm/exchange?id=999999999"); rec.Code != http.StatusOK || rec.Body.String() != "null\n" {
		t.Errorf("exchange missing id = %d %q, want 200 null", rec.Code, rec.Body.String())
	}
	if rec := get(handleMitmBodyRoute, "/mitm/body?id=abc"); rec.Code != http.StatusBadRequest {
		t.Errorf("body bad id status = %d, want 400", rec.Code)
	}
	if rec := get(handleMitmBodyRoute, "/mitm/body?id=999999999&response=true"); rec.Code != http.StatusOK || rec.Body.String() != "null\n" {
		t.Errorf("body missing id = %d %q, want 200 null", rec.Code, rec.Body.String())
	}
}
