package mitm

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestRunScriptSourceReturnsLogsAndResult(t *testing.T) {
	out := runScriptSource(`console.log("hello", 42); $done("ok")`, nil, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if len(out.Logs) != 1 || out.Logs[0] != "hello 42" {
		t.Fatalf("logs = %v, want [hello 42]", out.Logs)
	}
	if out.Result != "ok" {
		t.Fatalf("result = %q, want ok", out.Result)
	}
}

func TestRunScriptSourceReturnValueIsResult(t *testing.T) {
	out := runScriptSource(`1 + 2`, nil, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "3" {
		t.Fatalf("result = %q, want 3", out.Result)
	}
}

func TestRunScriptSourceThrowReturnsError(t *testing.T) {
	out := runScriptSource(`console.log("before"); throw new Error("boom")`, nil, nil)
	if out.Error == "" {
		t.Fatal("runScriptSource error = empty, want a throw reported")
	}
	if !strings.Contains(out.Error, "boom") {
		t.Fatalf("error = %q, want it to mention boom", out.Error)
	}
	if len(out.Logs) != 1 || out.Logs[0] != "before" {
		t.Fatalf("logs = %v, want the log before the throw kept", out.Logs)
	}
}

func TestRunScriptSourceSyntaxErrorReturnsError(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("runScriptSource panicked: %v", r)
		}
	}()
	out := runScriptSource(`function (`, nil, nil)
	if out.Error == "" {
		t.Fatal("runScriptSource error = empty, want a syntax error reported")
	}
}

func TestRunScriptSourceArgument(t *testing.T) {
	out := runScriptSource(`$done($argument)`, nil, map[string]string{"argument": "hello"})
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "hello" {
		t.Fatalf("result = %q, want hello", out.Result)
	}
}

func TestRunScriptSourceArgumentJSON(t *testing.T) {
	out := runScriptSource(`$done($argument.name)`, nil, map[string]string{"argument-json": `{"name":"x"}`})
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "x" {
		t.Fatalf("result = %q, want x", out.Result)
	}
}

func TestRunScriptSourceContextReadsAndEdits(t *testing.T) {
	ctx := &ScriptContext{
		Request: &ScriptRequest{
			URL:     "https://a.com/x",
			Method:  "GET",
			Headers: http.Header{"X-Test": {"1"}},
			Body:    []byte("req"),
		},
		Response: &ScriptResponse{
			Status:  200,
			Headers: http.Header{"Content-Type": {"text/plain"}},
			Body:    []byte("old"),
		},
	}
	out := runScriptSource(`
		console.log($request.url, $request.method);
		$request.headers["X-Test"] = "2";
		$response.body = "new";
		$response.status = 201;
		$done("edited");
	`, ctx, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if len(out.Logs) != 1 || out.Logs[0] != "https://a.com/x GET" {
		t.Fatalf("logs = %v, want [https://a.com/x GET]", out.Logs)
	}
	if out.Result != "edited" {
		t.Fatalf("result = %q, want edited", out.Result)
	}
	if ctx.Request.Headers.Get("X-Test") != "2" {
		t.Fatalf("request header = %q, want 2", ctx.Request.Headers.Get("X-Test"))
	}
	if string(ctx.Response.Body) != "new" {
		t.Fatalf("response body = %q, want new", ctx.Response.Body)
	}
	if ctx.Response.Status != 201 {
		t.Fatalf("response status = %d, want 201", ctx.Response.Status)
	}
}

func TestParseScriptLine(t *testing.T) {
	line := `My Script = type=generic,script-path=abc123.js,argument="a,b"`
	parsed := parseScriptLine(line)
	if parsed == nil {
		t.Fatal("parseScriptLine returned nil")
	}
	if parsed.name != "My Script" {
		t.Fatalf("name = %q, want My Script", parsed.name)
	}
	if parsed.typ != "generic" {
		t.Fatalf("type = %q, want generic", parsed.typ)
	}
	if parsed.params["script-path"] != "abc123.js" {
		t.Fatalf("script-path = %q, want abc123.js", parsed.params["script-path"])
	}
	if parsed.params["argument"] != "a,b" {
		t.Fatalf("argument = %q, want a,b", parsed.params["argument"])
	}
	if parseScriptLine("not a script line") != nil {
		t.Fatal("parseScriptLine accepted a line with no params")
	}
}

func TestEngineRunScriptByName(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	if err := os.MkdirAll(filepath.Join(home, "mitm", "resources"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "mitm", "resources", "abc123.js"), []byte(`console.log("ran"); $done("done")`), 0o644); err != nil {
		t.Fatal(err)
	}
	engine := &Engine{config: Config{Script: []string{
		"MyScript = type=generic,script-path=abc123.js",
		"HttpHook = type=http-request,script-path=abc123.js",
	}}}
	out := engine.RunScript("MyScript")
	if out.Error != "" {
		t.Fatalf("RunScript error = %q", out.Error)
	}
	if out.Result != "done" || len(out.Logs) != 1 || out.Logs[0] != "ran" {
		t.Fatalf("output = %+v, want result done with one log", out)
	}
	if out := engine.RunScript("Missing"); out.Error == "" {
		t.Fatal("RunScript missing name: error empty, want one")
	}
	if out := engine.RunScript("HttpHook"); out.Error == "" {
		t.Fatal("RunScript http-request type: error empty, want one")
	}
}

func TestEngineRunScriptMissingFile(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	engine := &Engine{config: Config{Script: []string{
		"MyScript = type=generic,script-path=nope.js",
	}}}
	out := engine.RunScript("MyScript")
	if out.Error == "" {
		t.Fatal("RunScript missing file: error empty, want one")
	}
}

func TestResolveResourceRejectsTraversal(t *testing.T) {
	home := t.TempDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir("")
	engine := &Engine{}
	for _, name := range []string{"../ca.crt", "a/../../ca.crt", "/etc/passwd"} {
		if _, err := engine.resolveResource(name); err == nil {
			t.Fatalf("resolveResource(%q) accepted an escaping path", name)
		}
	}
	if _, err := engine.resolveResource("abc123.js"); err != nil {
		t.Fatalf("resolveResource(abc123.js) = %v, want it accepted", err)
	}
}
