package core

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/metacubex/http"
	"github.com/metacubex/http/httptest"
)

func TestProbeRoutes(t *testing.T) {
	// The routes run the probes in the process-wide core. An unknown name
	// selects no checker, so the sweep answers an empty list without
	// touching the network.
	post := func(handler http.HandlerFunc, target, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, target, strings.NewReader(body))
		rec := httptest.NewRecorder()
		handler(rec, req)
		return rec
	}

	services := post(
		handleServiceCheckRoute,
		"/probe/services",
		`{"proxy-name":"","names":["no-such-service"],"timeout":1000}`,
	)
	if services.Code != http.StatusOK {
		t.Fatalf("services status = %d, want 200", services.Code)
	}
	var items []any
	if err := json.Unmarshal(services.Body.Bytes(), &items); err != nil {
		t.Fatalf("services body: %v", err)
	}
	if len(items) != 0 {
		t.Errorf("services = %v, want none", items)
	}
	if rec := post(handleServiceCheckRoute, "/probe/services", `{bad`); rec.Code != http.StatusBadRequest {
		t.Errorf("services bad body status = %d, want 400", rec.Code)
	}

	routes := post(
		handleCheckRoutesRoute,
		"/route/check",
		`{"routes":[]}`,
	)
	if routes.Code != http.StatusOK {
		t.Fatalf("routes status = %d, want 200", routes.Code)
	}
	var check struct {
		Held []bool `json:"held"`
	}
	if err := json.Unmarshal(routes.Body.Bytes(), &check); err != nil {
		t.Fatalf("routes body: %v", err)
	}
	if check.Held == nil {
		t.Errorf("held = nil, want an (empty) array")
	}
	if rec := post(handleCheckRoutesRoute, "/route/check", `{bad`); rec.Code != http.StatusBadRequest {
		t.Errorf("routes bad body status = %d, want 400", rec.Code)
	}
}
