package mitm

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/log"
)

// http scripts run after the declarative rewrites and before map-local on
// the request, and after the body and header rewrites on the response; the
// capture path runs the same hooks. A script's pattern therefore matches the
// URL the rewrites produced. A failing script logs and leaves the exchange
// alone; a body is only buffered for a script that asks for it.
func scriptPattern(parsed *scriptLine) string {
	if pattern := parsed.params["pattern"]; pattern != "" {
		return pattern
	}
	return "*"
}

func scriptBodyCap(parsed *scriptLine) int {
	if raw := parsed.params["max-size"]; raw != "" {
		if size, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && size > 0 {
			return size
		}
	}
	return maxRewriteBodySize
}

func (e *Engine) runRequestScripts(req *http.Request) ([]Action, *ScriptResponse) {
	e.mu.RLock()
	lines := append([]string(nil), e.config.Script...)
	e.mu.RUnlock()
	rawURL := req.URL.String()
	var actions []Action
	for _, line := range lines {
		parsed := parseScriptLine(line)
		if parsed == nil || parsed.typ != "http-request" {
			continue
		}
		if !matchURLPattern(scriptPattern(parsed), rawURL) {
			continue
		}
		action, echo := e.runRequestScript(parsed, line, req)
		actions = append(actions, action)
		if echo != nil {
			return actions, echo
		}
	}
	return actions, nil
}

func (e *Engine) runRequestScript(parsed *scriptLine, line string, req *http.Request) (Action, *ScriptResponse) {
	source, err := e.scriptSource(parsed)
	if err != nil {
		log.Warnln("[MITM] script %q: %v", parsed.name, err)
		return Action{Kind: "script", Phase: "request", Detail: line + " (" + err.Error() + ")"}, nil
	}
	scriptReq := &ScriptRequest{
		URL:     req.URL.String(),
		Method:  req.Method,
		Headers: req.Header.Clone(),
	}
	hadBody := req.Body != nil && req.Body != http.NoBody
	if parsed.params["requires-body"] == "true" {
		raw, complete := readScriptBody(req.Body, scriptBodyCap(parsed))
		if !complete {
			log.Warnln("[MITM] script %q: request body past the cap, skipped", parsed.name)
			return Action{Kind: "script", Phase: "request", Detail: line + " (request body past the cap)"}, nil
		}
		scriptReq.Body = raw
	}
	ctx := &ScriptContext{Request: scriptReq}
	out := runScriptSource(source, ctx, parsed.params, e.scriptEnv(parsed.name))
	if out.Error != "" {
		log.Warnln("[MITM] script %q: %v", parsed.name, out.Error)
		return Action{Kind: "script", Phase: "request", Detail: line + " (" + out.Error + ")"}, nil
	}
	applyRequestScript(req, scriptReq, hadBody)
	return Action{Kind: "script", Phase: "request", Detail: line}, out.Response
}

// scriptEchoResponse serves a scripted response in place of the upstream one.
func scriptEchoResponse(req *http.Request, echo *ScriptResponse) *http.Response {
	header := echo.Headers.Clone()
	if header == nil {
		header = http.Header{}
	}
	header.Set("Content-Length", strconv.Itoa(len(echo.Body)))
	status := echo.Status
	if status == 0 {
		status = http.StatusOK
	}
	proto := req.Proto
	if proto == "" {
		proto = "HTTP/1.1"
	}
	return &http.Response{
		Status:        fmt.Sprintf("%d %s", status, http.StatusText(status)),
		StatusCode:    status,
		Proto:         proto,
		Header:        header,
		Body:          io.NopCloser(bytes.NewReader(echo.Body)),
		ContentLength: int64(len(echo.Body)),
		Request:       req,
	}
}

func applyRequestScript(req *http.Request, edited *ScriptRequest, hadBody bool) {
	if edited.URL != "" && edited.URL != req.URL.String() {
		if u, err := url.Parse(edited.URL); err == nil && u.Host != "" {
			req.URL = u
			req.Host = u.Host
		} else {
			log.Warnln("[MITM] script set an unusable request URL %q, kept the original", edited.URL)
		}
	}
	if edited.Method != "" {
		req.Method = edited.Method
	}
	if edited.Headers != nil {
		req.Header = edited.Headers
	}
	// A bodiless request stays bodiless unless the script actually set one:
	// buffering an empty body looks identical to a script clearing it.
	if edited.Body != nil && (hadBody || len(edited.Body) > 0) {
		req.Body = io.NopCloser(bytes.NewReader(edited.Body))
		req.ContentLength = int64(len(edited.Body))
		req.Header.Del("Transfer-Encoding")
	}
}

// runResponseScripts executes the matching http-response scripts. The
// request is attached read-only, so a response script can read $request.
func (e *Engine) runResponseScripts(req *http.Request, resp *http.Response, matchURL string) []Action {
	e.mu.RLock()
	lines := append([]string(nil), e.config.Script...)
	e.mu.RUnlock()
	var actions []Action
	for _, line := range lines {
		parsed := parseScriptLine(line)
		if parsed == nil || parsed.typ != "http-response" {
			continue
		}
		if !matchURLPattern(scriptPattern(parsed), matchURL) {
			continue
		}
		actions = append(actions, e.runResponseScript(parsed, line, req, resp))
	}
	return actions
}

func (e *Engine) runResponseScript(parsed *scriptLine, line string, req *http.Request, resp *http.Response) Action {
	source, err := e.scriptSource(parsed)
	if err != nil {
		log.Warnln("[MITM] script %q: %v", parsed.name, err)
		return Action{Kind: "script", Phase: "response", Detail: line + " (" + err.Error() + ")"}
	}
	scriptResp := &ScriptResponse{
		Status:  resp.StatusCode,
		Headers: resp.Header.Clone(),
	}
	gzipped := contentEncodingIs(resp, "gzip")
	hadBody := resp.Body != nil && resp.Body != http.NoBody
	if parsed.params["requires-body"] == "true" {
		raw, complete := readScriptBody(resp.Body, scriptBodyCap(parsed))
		if !complete {
			log.Warnln("[MITM] script %q: response body past the cap, skipped", parsed.name)
			return Action{Kind: "script", Phase: "response", Detail: line + " (response body past the cap)"}
		}
		plain := raw
		if gzipped {
			decoded, err := gunzipBytes(raw)
			if err != nil {
				log.Warnln("[MITM] script %q: cannot gunzip response body: %v", parsed.name, err)
				return Action{Kind: "script", Phase: "response", Detail: line + " (cannot gunzip response body)"}
			}
			plain = decoded
		}
		scriptResp.Body = plain
	}
	ctx := &ScriptContext{Response: scriptResp}
	if req != nil {
		ctx.Request = &ScriptRequest{
			URL:     req.URL.String(),
			Method:  req.Method,
			Headers: req.Header.Clone(),
		}
	}
	out := runScriptSource(source, ctx, parsed.params, e.scriptEnv(parsed.name))
	if out.Error != "" {
		log.Warnln("[MITM] script %q: %v", parsed.name, out.Error)
		return Action{Kind: "script", Phase: "response", Detail: line + " (" + out.Error + ")"}
	}
	applyResponseScript(resp, scriptResp, gzipped, hadBody)
	return Action{Kind: "script", Phase: "response", Detail: line}
}

func applyResponseScript(resp *http.Response, edited *ScriptResponse, gzipped, hadBody bool) {
	if edited.Status != 0 && edited.Status != resp.StatusCode {
		resp.StatusCode = edited.Status
		resp.Status = fmt.Sprintf("%d %s", edited.Status, http.StatusText(edited.Status))
	}
	if edited.Headers != nil {
		resp.Header = edited.Headers
	}
	if edited.Body != nil && (hadBody || len(edited.Body) > 0) {
		out := edited.Body
		if gzipped {
			encoded, err := gzipBytes(out)
			if err != nil {
				resp.Body = io.NopCloser(bytes.NewReader(out))
				resp.ContentLength = int64(len(out))
				resp.Header.Set("Content-Length", strconv.Itoa(len(out)))
				resp.Header.Del("Content-Encoding")
				resp.Header.Del("Transfer-Encoding")
				return
			}
			out = encoded
		}
		resp.Body = io.NopCloser(bytes.NewReader(out))
		resp.ContentLength = int64(len(out))
		resp.Header.Set("Content-Length", strconv.Itoa(len(out)))
		resp.Header.Del("Transfer-Encoding")
	}
}

func (e *Engine) scriptSource(parsed *scriptLine) (string, error) {
	path := parsed.params["script-path"]
	if path == "" {
		return "", fmt.Errorf("script %q has no script-path", parsed.name)
	}
	source, err := e.readResource(path)
	if err != nil {
		return "", err
	}
	return string(source), nil
}

// readScriptBody reads up to limit bytes; a nil body stays nil, and a body
// past the limit reports incomplete instead of returning a prefix.
func readScriptBody(r io.Reader, limit int) ([]byte, bool) {
	if r == nil {
		return nil, true
	}
	buf, err := io.ReadAll(io.LimitReader(r, int64(limit)+1))
	if err != nil {
		return buf, false
	}
	return buf, len(buf) <= limit
}
