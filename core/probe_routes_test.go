package core

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/metacubex/http"
	"github.com/metacubex/http/httptest"
)

func TestProbeRoutes(t *testing.T) {
	// The route runs the probe in the process-wide core. An unknown name
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

	routes := post(handleCheckRoutesRoute, "/route/check", `{"routes":[]}`)
	if routes.Code != http.StatusOK {
		t.Fatalf("routes status = %d, want 200", routes.Code)
	}
	var check map[string]any
	if err := json.Unmarshal(routes.Body.Bytes(), &check); err != nil {
		t.Fatalf("routes body: %v", err)
	}
	if _, ok := check["held"]; !ok {
		t.Errorf("routes = %v, want a held list", check)
	}
	if rec := post(handleCheckRoutesRoute, "/route/check", `{bad`); rec.Code != http.StatusBadRequest {
		t.Errorf("routes bad body status = %d, want 400", rec.Code)
	}

	// No sources: the lookup fails fast without touching the network.
	outbound := post(
		handleOutboundIpRoute,
		"/probe/outbound-ip",
		`{"proxy-name":"","urls":[],"timeout":1000}`,
	)
	if outbound.Code != http.StatusOK {
		t.Fatalf("outbound status = %d, want 200", outbound.Code)
	}
	var result map[string]any
	if err := json.Unmarshal(outbound.Body.Bytes(), &result); err != nil {
		t.Fatalf("outbound body: %v", err)
	}
	if _, ok := result["error"]; !ok {
		t.Errorf("outbound = %v, want an error", result)
	}
	if rec := post(handleOutboundIpRoute, "/probe/outbound-ip", `{bad`); rec.Code != http.StatusBadRequest {
		t.Errorf("outbound bad body status = %d, want 400", rec.Code)
	}
}
