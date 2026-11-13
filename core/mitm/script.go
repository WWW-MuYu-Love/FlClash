package mitm

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/dop251/goja"
)

// ScriptOutput is the mitm.runScript answer (MitmScriptOutput).
type ScriptOutput struct {
	Logs   []string `json:"logs"`
	Result string   `json:"result"`
	Error  string   `json:"error"`
}

// scriptTimeout bounds one script run.
const scriptTimeout = 10 * time.Second

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
		return runScriptSource(string(source), nil, parsed.params)
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

func runScriptSource(source string, ctx *ScriptContext, params map[string]string) (out ScriptOutput) {
	rt := goja.New()
	rt.Set("console", map[string]any{
		"log":   func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
		"warn":  func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
		"error": func(args ...goja.Value) { out.Logs = append(out.Logs, formatJSArgs(args)) },
	})
	var doneResult string
	var done bool
	rt.Set("$done", func(v goja.Value) {
		if v != nil && !goja.IsUndefined(v) && !goja.IsNull(v) {
			doneResult = v.String()
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
	timer := time.AfterFunc(scriptTimeout, func() { rt.Interrupt(errScriptTimeout) })
	defer timer.Stop()
	value, err := rt.RunString(source)
	if err != nil {
		var interrupted *goja.InterruptedError
		if errors.As(err, &interrupted) {
			switch {
			case errors.Is(interrupted.Unwrap(), errScriptDone):
				out.Result = doneResult
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
	} else if value != nil && !goja.IsUndefined(value) && !goja.IsNull(value) {
		out.Result = value.String()
	}
	applyScriptContext(ctx, reqObj, respObj)
	return out
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
	obj.Set("body", string(req.Body))
	return obj
}

func responseToJS(rt *goja.Runtime, resp *ScriptResponse) *goja.Object {
	obj := rt.NewObject()
	obj.Set("status", resp.Status)
	obj.Set("headers", headersToJS(rt, resp.Headers))
	obj.Set("body", string(resp.Body))
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
			req.Headers = headersFromJS(headers)
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
			resp.Headers = headersFromJS(headers)
		}
	}
}

func headersFromJS(values map[string]any) http.Header {
	h := http.Header{}
	for name, v := range values {
		if s, ok := v.(string); ok {
			h.Set(name, s)
		}
	}
	return h
}
