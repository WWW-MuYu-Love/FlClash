package mitm

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/dop251/goja"
	"github.com/metacubex/mihomo/constant"
)

// ScriptOutput is the mitm.runScript answer (MitmScriptOutput).
type ScriptOutput struct {
	Logs   []string `json:"logs"`
	Result string   `json:"result"`
	Error  string   `json:"error"`
	// Response is a $done answer for the intercept path only, never part of the runScript answer.
	Response *ScriptResponse `json:"-"`
}

type ScriptNotification struct {
	Title    string `json:"title"`
	Subtitle string `json:"subtitle"`
	Body     string `json:"body"`
}

type scriptEnv struct {
	store     *persistentStore
	namespace string
	http      *http.Client
	notify    func(ScriptNotification)
}

// scriptTimeout bounds one script run.
const scriptTimeout = 10 * time.Second

func scriptTimeoutFor(params map[string]string) time.Duration {
	if raw := params["timeout"]; raw != "" {
		if seconds, err := strconv.ParseFloat(strings.TrimSpace(raw), 64); err == nil && seconds > 0 {
			if seconds > 120 {
				seconds = 120
			}
			return time.Duration(seconds * float64(time.Second))
		}
	}
	return scriptTimeout
}

var (
	// errScriptDone and errScriptTimeout travel as Interrupt values so the
	// runner can tell them apart from a script throw.
	errScriptDone    = errors.New("script done")
	errScriptTimeout = errors.New("script timed out")
)

// ScriptContext gives a script the exchange it may inspect or modify. A nil
// context runs the script standalone; edits write back into these structs.
type ScriptContext struct {
	Request  *ScriptRequest
	Response *ScriptResponse
}

// ScriptRequest is the request half of a script context.
type ScriptRequest struct {
	URL     string
	Method  string
	Headers http.Header
	Body    []byte
}

// ScriptResponse is the response half of a script context.
type ScriptResponse struct {
	Status  int
	Headers http.Header
	Body    []byte
}

func (e *Engine) persistentStore() *persistentStore {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.store != nil {
		return e.store
	}
	e.store = newPersistentStore(e.storePath())
	return e.store
}

func (e *Engine) storePath() string {
	if e.homeDir != "" {
		return filepath.Join(e.homeDir, persistentStoreName)
	}
	if base := constant.Path.HomeDir(); base != "" {
		return filepath.Join(base, dirName, persistentStoreName)
	}
	return ""
}

func (e *Engine) scriptHTTPClient() *http.Client {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.httpClient != nil && e.httpClientPort == e.mixedPort {
		return e.httpClient
	}
	e.httpClient = newScriptHTTPClient(e.mixedPort)
	e.httpClientPort = e.mixedPort
	return e.httpClient
}

func (e *Engine) scriptEnv(namespace string) *scriptEnv {
	e.mu.RLock()
	notify := e.notify
	e.mu.RUnlock()
	return &scriptEnv{
		store:     e.persistentStore(),
		namespace: namespace,
		http:      e.scriptHTTPClient(),
		notify:    notify,
	}
}

// SetNotifyHandler sets where $notification.post delivers; a nil handler
// drops the notification.
func (e *Engine) SetNotifyHandler(fn func(ScriptNotification)) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.notify = fn
}

// RunScript executes the named cron/event/generic module script.
func (e *Engine) RunScript(name string) ScriptOutput {
	if name == "" {
		return ScriptOutput{Error: "missing script name"}
	}
	e.mu.RLock()
	lines := append([]string(nil), e.config.Script...)
	e.mu.RUnlock()
	for _, line := range lines {
		parsed := parseScriptLine(line)
		if parsed == nil || parsed.name != name {
			continue
		}
		if parsed.typ != "cron" && parsed.typ != "event" && parsed.typ != "generic" {
			return ScriptOutput{Error: fmt.Sprintf("script %q is a %s script and cannot be run directly", name, parsed.typ)}
		}
		path := parsed.params["script-path"]
		if path == "" {
			return ScriptOutput{Error: fmt.Sprintf("script %q has no script-path", name)}
		}
		source, err := e.readResource(path)
		if err != nil {
			return ScriptOutput{Error: err.Error()}
		}
		return runScriptSource(string(source), nil, parsed.params, e.scriptEnv(name))
	}
	return ScriptOutput{Error: fmt.Sprintf("no script named %q", name)}
}

type scriptLine struct {
	name   string
	typ    string
	params map[string]string
}

func parseScriptLine(line string) *scriptLine {
	eq := strings.Index(line, "=")
	if eq <= 0 {
		return nil
	}
	name := strings.TrimSpace(line[:eq])
	if name == "" {
		return nil
	}
	params := map[string]string{}
	for _, field := range splitScriptParams(line[eq+1:]) {
		key, value, ok := strings.Cut(field, "=")
		if !ok {
			continue
		}
		params[strings.ToLower(strings.TrimSpace(key))] = unquoteScriptValue(strings.TrimSpace(value))
	}
	return &scriptLine{name: name, typ: strings.ToLower(params["type"]), params: params}
}

func splitScriptParams(s string) []string {
	var out []string
	var b bytes.Buffer
	inQuote := false
	for _, r := range s {
		switch {
		case r == '"':
			inQuote = !inQuote
			b.WriteRune(r)
		case r == ',' && !inQuote:
			if b.Len() > 0 {
				out = append(out, strings.TrimSpace(b.String()))
				b.Reset()
			}
		default:
			b.WriteRune(r)
		}
	}
	if b.Len() > 0 {
		out = append(out, strings.TrimSpace(b.String()))
	}
	return out
}

func unquoteScriptValue(s string) string {
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		return s[1 : len(s)-1]
	}
	return s
}

func runScriptSource(source string, ctx *ScriptContext, params map[string]string, env *scriptEnv) (out ScriptOutput) {
	rt := goja.New()
	rt.Set("console", map[string]any{
		"log":   func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
		"warn":  func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
		"error": func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
	})
	// Env.js reads $environment to identify its host; a truthy surge-version selects the Surge branch.
	rt.Set("$environment", map[string]any{
		"surge-version": "5.0.0",
	})
	if env != nil {
		if env.store != nil {
			namespace := env.namespace
			rt.Set("$persistentStore", map[string]any{
				"read": func(key goja.Value) any {
					if value, ok := env.store.read(namespace, key.String()); ok {
						return value
					}
					return goja.Null()
				},
				"write": func(value, key goja.Value) bool {
					return env.store.write(namespace, key.String(), value.String())
				},
			})
			rt.Set("$prefs", map[string]any{
				"valueForKey": func(key goja.Value) any {
					if value, ok := env.store.read(namespace, key.String()); ok {
						return value
					}
					return goja.Null()
				},
				"setValueForKey": func(value, key goja.Value) bool {
					return env.store.write(namespace, key.String(), value.String())
				},
				"removeValueForKey": func(key goja.Value) bool {
					return env.store.remove(namespace, key.String())
				},
			})
		}
		if env.http != nil {
			setHTTPClient(rt, env.http, &out)
		}
		if env.notify != nil {
			notify := env.notify
			rt.Set("$notification", map[string]any{
				"post": func(title, subtitle, body goja.Value) {
					notify(ScriptNotification{
						Title:    stringOrEmpty(title),
						Subtitle: stringOrEmpty(subtitle),
						Body:     stringOrEmpty(body),
					})
				},
			})
		}
	}
	rt.Set("$network", networkInfo())
	var doneResult string
	var doneResponse *ScriptResponse
	var done bool
	rt.Set("$done", func(v goja.Value) {
		if v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
			if resp := parseDoneResponse(v); resp != nil {
				doneResponse = resp
			} else {
				doneResult = v.String()
			}
		}
		done = true
		rt.Interrupt(errScriptDone)
	})
	if argument, ok := scriptArgument(params); ok {
		rt.Set("$argument", argument)
	}
	var reqObj, respObj *goja.Object
	if ctx != nil && ctx.Request != nil {
		reqObj = requestToJS(rt, ctx.Request)
		rt.Set("$request", reqObj)
	}
	if ctx != nil && ctx.Response != nil {
		respObj = responseToJS(rt, ctx.Response)
		rt.Set("$response", respObj)
	}
	timer := time.AfterFunc(scriptTimeoutFor(params), func() { rt.Interrupt(errScriptTimeout) })
	defer timer.Stop()
	value, err := rt.RunString(source)
	if err != nil {
		var interrupted *goja.InterruptedError
		if errors.As(err, &interrupted) {
			switch {
			case errors.Is(interrupted.Unwrap(), errScriptDone):
				out.Result = doneResult
				out.Response = doneResponse
				applyScriptContext(ctx, reqObj, respObj)
				return out
			case errors.Is(interrupted.Unwrap(), errScriptTimeout):
				out.Error = errScriptTimeout.Error()
				return out
			}
		}
		out.Error = formatJSError(err)
		return out
	}
	if done {
		out.Result = doneResult
		out.Response = doneResponse
	} else if value != nil && !goja.IsUndefined(value) && !goja.IsNull(value) {
		out.Result = value.String()
	}
	applyScriptContext(ctx, reqObj, respObj)
	return out
}

func parseDoneResponse(v goja.Value) *ScriptResponse {
	exported, ok := v.Export().(map[string]any)
	if !ok {
		return nil
	}
	if raw, ok := exported["response"].(map[string]any); ok {
		return doneResponseFrom(raw)
	}
	if _, ok := exported["status"]; ok {
		return doneResponseFrom(exported)
	}
	if _, ok := exported["headers"]; ok {
		return doneResponseFrom(exported)
	}
	return nil
}

func doneResponseFrom(obj map[string]any) *ScriptResponse {
	resp := &ScriptResponse{Headers: http.Header{}}
	resp.Status = doneStatus(obj["status"])
	if raw, ok := obj["headers"].(map[string]any); ok {
		for name, value := range raw {
			switch v := value.(type) {
			case string:
				resp.Headers.Set(name, v)
			case []any:
				for _, item := range v {
					if s, ok := item.(string); ok {
						resp.Headers.Add(name, s)
					}
				}
			}
		}
	}
	if raw, ok := obj["body"].(string); ok {
		resp.Body = []byte(raw)
	}
	return resp
}

func doneStatus(raw any) int {
	switch v := raw.(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	case string:
		for _, field := range strings.Fields(v) {
			if code, err := strconv.Atoi(field); err == nil && code >= 100 && code < 600 {
				return code
			}
		}
	}
	return 0
}

func applyScriptContext(ctx *ScriptContext, reqObj, respObj *goja.Object) {
	if ctx == nil {
		return
	}
	if reqObj != nil && ctx.Request != nil {
		applyRequestFromJS(ctx.Request, reqObj)
	}
	if respObj != nil && ctx.Response != nil {
		applyResponseFromJS(ctx.Response, respObj)
	}
}

func scriptArgument(params map[string]string) (any, bool) {
	if raw, ok := params["argument-json"]; ok && raw != "" {
		var value any
		if err := json.Unmarshal([]byte(raw), &value); err == nil {
			return value, true
		}
	}
	if raw, ok := params["argument"]; ok && raw != "" {
		return raw, true
	}
	return nil, false
}

func formatJSArgs(args []goja.Value) string {
	parts := make([]string, len(args))
	for i, a := range args {
		switch {
		case goja.IsUndefined(a):
			parts[i] = "undefined"
		case goja.IsNull(a):
			parts[i] = "null"
		default:
			parts[i] = fmt.Sprint(a.Export())
		}
	}
	return strings.Join(parts, " ")
}

func formatJSError(err error) string {
	var exc *goja.Exception
	if errors.As(err, &exc) {
		return exc.Value().String()
	}
	return err.Error()
}

func requestToJS(rt *goja.Runtime, req *ScriptRequest) *goja.Object {
	obj := rt.NewObject()
	obj.Set("url", req.URL)
	obj.Set("method", req.Method)
	obj.Set("headers", headersToJS(rt, req.Headers))
	// The body is only set when the caller buffered one, so a header-only
	// script cannot replace the live request stream with an empty body.
	if req.Body != nil {
		obj.Set("body", string(req.Body))
	}
	return obj
}

func responseToJS(rt *goja.Runtime, resp *ScriptResponse) *goja.Object {
	obj := rt.NewObject()
	obj.Set("status", resp.Status)
	obj.Set("headers", headersToJS(rt, resp.Headers))
	if resp.Body != nil {
		obj.Set("body", string(resp.Body))
	}
	return obj
}

func headersToJS(rt *goja.Runtime, h http.Header) *goja.Object {
	obj := rt.NewObject()
	for name, values := range h {
		if len(values) > 0 {
			obj.Set(name, values[0])
		}
	}
	return obj
}

func applyRequestFromJS(req *ScriptRequest, obj *goja.Object) {
	if v := obj.Get("url"); v != nil && !goja.IsUndefined(v) {
		req.URL = v.String()
	}
	if v := obj.Get("method"); v != nil && !goja.IsUndefined(v) {
		req.Method = v.String()
	}
	if v := obj.Get("body"); v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		req.Body = []byte(v.String())
	}
	if v := obj.Get("headers"); v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		if headers, ok := v.Export().(map[string]any); ok {
			req.Headers = applyHeadersFromJS(req.Headers, headers)
		}
	}
}

func applyResponseFromJS(resp *ScriptResponse, obj *goja.Object) {
	if v := obj.Get("status"); v != nil && !goja.IsUndefined(v) {
		resp.Status = int(v.ToInteger())
	}
	if v := obj.Get("body"); v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		resp.Body = []byte(v.String())
	}
	if v := obj.Get("headers"); v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
		if headers, ok := v.Export().(map[string]any); ok {
			resp.Headers = applyHeadersFromJS(resp.Headers, headers)
		}
	}
}

// applyHeadersFromJS merges the script's headers onto the originals, so a
// key the script left alone keeps every value it had.
func applyHeadersFromJS(original http.Header, exported map[string]any) http.Header {
	merged := original.Clone()
	if merged == nil {
		merged = http.Header{}
	}
	seen := map[string]struct{}{}
	for name, v := range exported {
		canonical := http.CanonicalHeaderKey(name)
		seen[canonical] = struct{}{}
		value, ok := v.(string)
		if !ok {
			continue
		}
		if merged.Get(canonical) != value {
			merged.Set(canonical, value)
		}
	}
	for name := range original {
		if _, ok := seen[name]; !ok {
			merged.Del(name)
		}
	}
	return merged
}

func stringOrEmpty(v goja.Value) string {
	if v == nil || goja.IsUndefined(v) || goja.IsNull(v) {
		return ""
	}
	return v.String()
}
