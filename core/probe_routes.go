package core

import (
	"github.com/metacubex/chi"
	"github.com/metacubex/chi/render"
	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/hub/route"
)

// The service probe runs in the core that routes. On iOS that is the
// extension core behind the external controller, while the app reads it
// over FFI from the app core, so the same query is served on 9090 as
// well. The route registers here, inside the controller's authenticated
// group, so the app's Bearer secret already authorizes it.
func init() {
	route.Register(func(r chi.Router) {
		r.Post("/probe/services", handleServiceCheckRoute)
	})
}

func handleServiceCheckRoute(w http.ResponseWriter, r *http.Request) {
	var params ServiceCheckParams
	if err := render.DecodeJSON(r.Body, &params); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, route.ErrBadRequest)
		return
	}
	render.JSON(w, r, handleServiceCheck(&params))
}
