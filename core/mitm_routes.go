package core

import (
	"strconv"

	"core/mitm"

	"github.com/metacubex/chi"
	"github.com/metacubex/chi/render"
	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/hub/route"
)

// The MITM capture store lives in the core that decrypts. On iOS that is the
// extension core behind the external controller, while the app reads it over
// FFI from the app core, so the same queries are served on 9090 as well.
// The routes register here, inside the controller's authenticated group, so
// the app's Bearer secret already authorizes them.
func init() {
	route.Register(func(r chi.Router) {
		r.Get("/mitm/hosts", handleMitmHostsRoute)
		r.Get("/mitm/exchanges", handleMitmExchangesRoute)
		r.Get("/mitm/exchange", handleMitmExchangeRoute)
		r.Get("/mitm/body", handleMitmBodyRoute)
	})
}

func handleMitmHostsRoute(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, mitm.Default().DecryptedHosts())
}

func handleMitmExchangesRoute(w http.ResponseWriter, r *http.Request) {
	render.JSON(w, r, mitm.Default().ExchangesByHost(r.URL.Query().Get("host")))
}

func handleMitmExchangeRoute(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.URL.Query().Get("id"))
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, route.ErrBadRequest)
		return
	}
	render.JSON(w, r, mitm.Default().Exchange(id))
}

func handleMitmBodyRoute(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.URL.Query().Get("id"))
	if err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, route.ErrBadRequest)
		return
	}
	render.JSON(w, r, mitm.Default().Body(id, r.URL.Query().Get("response") == "true"))
}
