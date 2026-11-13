package core

import (
	"github.com/metacubex/chi"
	"github.com/metacubex/chi/render"
	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/hub/route"
)

// The service, route and outbound-IP probes run in the core that routes. On iOS that is
// the extension core behind the external controller, while the app reads
// them over FFI from the app core, so the same queries are served on 9090
// as well. The routes register here, inside the controller's authenticated
// group, so the app's Bearer secret already authorizes them.
func init() {
	route.Register(func(r chi.Router) {
		r.Post("/probe/services", handleServiceCheckRoute)
		r.Post("/route/check", handleCheckRoutesRoute)
		r.Post("/probe/outbound-ip", handleOutboundIpRoute)
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

func handleCheckRoutesRoute(w http.ResponseWriter, r *http.Request) {
	var params CheckRoutesParams
	if err := render.DecodeJSON(r.Body, &params); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, route.ErrBadRequest)
		return
	}
	render.JSON(w, r, handleCheckRoutes(&params))
}

func handleOutboundIpRoute(w http.ResponseWriter, r *http.Request) {
	var params OutboundIpParams
	if err := render.DecodeJSON(r.Body, &params); err != nil {
		render.Status(r, http.StatusBadRequest)
		render.JSON(w, r, route.ErrBadRequest)
		return
	}
	render.JSON(w, r, handleOutboundIp(&params))
}
