package mitm

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
)

func TestRunScriptSourceReturnsLogsAndResult(t *testing.T) {
	out := runScriptSource(`console.log("hello", 42); $done("ok")`, nil, nil, nil)
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
	out := runScriptSource(`1 + 2`, nil, nil, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "3" {
		t.Fatalf("result = %q, want 3", out.Result)
	}
}

func TestRunScriptSourceThrowReturnsError(t *testing.T) {
	out := runScriptSource(`console.log("before"); throw new Error("boom")`, nil, nil, nil)
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
	out := runScriptSource(`function (`, nil, nil, nil)
	if out.Error == "" {
		t.Fatal("runScriptSource error = empty, want a syntax error reported")
	}
}

func TestRunScriptSourceArgument(t *testing.T) {
	out := runScriptSource(`$done($argument)`, nil, map[string]string{"argument": "hello"}, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "hello" {
		t.Fatalf("result = %q, want hello", out.Result)
	}
}

func TestRunScriptSourceArgumentJSON(t *testing.T) {
	out := runScriptSource(`$done($argument.name)`, nil, map[string]string{"argument-json": `{"name":"x"}`}, nil)
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
	`, ctx, nil, nil)
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

func TestPersistentStoreReadWriteRemove(t *testing.T) {
	store := newPersistentStore("")
	if _, ok := store.read("ns", "missing"); ok {
		t.Fatal("read of a missing key reported found")
	}
	if !store.write("ns", "k", "v") {
		t.Fatal("memory write returned false")
	}
	if got, ok := store.read("ns", "k"); !ok || got != "v" {
		t.Fatalf("read = %q, %v, want v, true", got, ok)
	}
	if !store.remove("ns", "k") {
		t.Fatal("memory remove returned false")
	}
	if _, ok := store.read("ns", "k"); ok {
		t.Fatal("removed key still reads")
	}
}

func TestPersistentStoreNamespacesIsolated(t *testing.T) {
	store := newPersistentStore("")
	store.write("a", "k", "one")
	store.write("b", "k", "two")
	if got, _ := store.read("a", "k"); got != "one" {
		t.Fatalf("namespace a read %q, want one", got)
	}
	if got, _ := store.read("b", "k"); got != "two" {
		t.Fatalf("namespace b read %q, want two", got)
	}
}

func TestPersistentStorePersistsAcrossInstances(t *testing.T) {
	path := filepath.Join(t.TempDir(), "persistent_store.json")
	first := newPersistentStore(path)
	if !first.write("ns", "token", "abc") {
		t.Fatal("write returned false")
	}
	if info, err := os.Stat(path); err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("store file mode = %v, %v, want 0600", info.Mode(), err)
	}
	second := newPersistentStore(path)
	if got, ok := second.read("ns", "token"); !ok || got != "abc" {
		t.Fatalf("reloaded read = %q, %v, want abc, true", got, ok)
	}
}

func TestPersistentStoreCorruptFileStartsEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "persistent_store.json")
	if err := os.WriteFile(path, []byte("{not json"), 0o600); err != nil {
		t.Fatal(err)
	}
	store := newPersistentStore(path)
	if _, ok := store.read("ns", "k"); ok {
		t.Fatal("corrupt store read a key")
	}
	if !store.write("ns", "k", "v") {
		t.Fatal("write after corrupt load returned false")
	}
}

func TestScriptPersistentStoreAndPrefsShareOneStore(t *testing.T) {
	store := newPersistentStore("")
	env := &scriptEnv{store: store, namespace: "Box"}
	out := runScriptSource(`
		$persistentStore.write("hello", "greeting");
		$prefs.setValueForKey("42", "answer");
		$done($persistentStore.read("answer"));
	`, nil, nil, env)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "42" {
		t.Fatalf("result = %q, want 42 (prefs write visible through persistentStore)", out.Result)
	}
	if got, _ := store.read("Box", "greeting"); got != "hello" {
		t.Fatalf("store greeting = %q, want hello", got)
	}
	out = runScriptSource(`$done($prefs.valueForKey("greeting"))`, nil, nil, env)
	if out.Result != "hello" {
		t.Fatalf("prefs read = %q, want hello", out.Result)
	}
	out = runScriptSource(`$done($persistentStore.read("missing") === null ? "null" : "not-null")`, nil, nil, env)
	if out.Result != "null" {
		t.Fatalf("missing key result = %q, want null", out.Result)
	}
	out = runScriptSource(`$prefs.removeValueForKey("greeting"); $done($persistentStore.read("greeting") === null ? "null" : "not-null")`, nil, nil, env)
	if out.Result != "null" {
		t.Fatalf("removed key result = %q, want null", out.Result)
	}
}

func TestScriptPersistentStoreNamespacesIsolated(t *testing.T) {
	store := newPersistentStore("")
	one := &scriptEnv{store: store, namespace: "One"}
	two := &scriptEnv{store: store, namespace: "Two"}
	runScriptSource(`$persistentStore.write("1", "k")`, nil, nil, one)
	runScriptSource(`$persistentStore.write("2", "k")`, nil, nil, two)
	out := runScriptSource(`$done($persistentStore.read("k"))`, nil, nil, one)
	if out.Result != "1" {
		t.Fatalf("namespace One read %q, want 1", out.Result)
	}
	out = runScriptSource(`$done($persistentStore.read("k"))`, nil, nil, two)
	if out.Result != "2" {
		t.Fatalf("namespace Two read %q, want 2", out.Result)
	}
}

func TestScriptNetworkSSIDIsNull(t *testing.T) {
	out := runScriptSource(`$done(String($network.wifi.ssid))`, nil, nil, nil)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "null" {
		t.Fatalf("ssid = %q, want null", out.Result)
	}
	out = runScriptSource(`$done(typeof $network.v4.primaryAddress)`, nil, nil, nil)
	if out.Result != "string" {
		t.Fatalf("v4 address type = %q, want string", out.Result)
	}
}

func TestScriptNotificationPost(t *testing.T) {
	var got []ScriptNotification
	env := &scriptEnv{notify: func(n ScriptNotification) { got = append(got, n) }}
	out := runScriptSource(`$notification.post("Title", "Sub", "Body"); $done("posted")`, nil, nil, env)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if len(got) != 1 || got[0] != (ScriptNotification{Title: "Title", Subtitle: "Sub", Body: "Body"}) {
		t.Fatalf("notifications = %+v, want one Title/Sub/Body", got)
	}
}

func TestScriptHTTPClientGetAndPost(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		w.Header().Set("X-Echo", r.Header.Get("X-Test"))
		w.WriteHeader(http.StatusTeapot)
		_, _ = w.Write([]byte(r.Method + ":" + string(body)))
	}))
	defer server.Close()
	env := &scriptEnv{http: newScriptHTTPClient(0)}
	out := runScriptSource(`
		$httpClient.get({url: $argument, headers: {"X-Test": "yes"}}, function(error, response, data) {
			if (error) { $done("error:" + error); return; }
			$done(response.status + ":" + response.headers["X-Echo"] + ":" + data);
		});
	`, nil, map[string]string{"argument": server.URL + "/get"}, env)
	if out.Error != "" {
		t.Fatalf("get error = %q", out.Error)
	}
	if out.Result != "418:yes:GET:" {
		t.Fatalf("get result = %q, want 418:yes:GET:", out.Result)
	}
	out = runScriptSource(`
		$httpClient.post({url: $argument, body: "payload"}, function(error, response, data) {
			$done(response.statusCode + ":" + data);
		});
	`, nil, map[string]string{"argument": server.URL + "/post"}, env)
	if out.Error != "" {
		t.Fatalf("post error = %q", out.Error)
	}
	if out.Result != "418:POST:payload" {
		t.Fatalf("post result = %q, want 418:POST:payload", out.Result)
	}
}

func TestScriptHTTPClientErrorReachesCallback(t *testing.T) {
	env := &scriptEnv{http: newScriptHTTPClient(0)}
	out := runScriptSource(`
		$httpClient.get({url: "http://127.0.0.1:1/nope"}, function(error, response, data) {
			$done(error ? "failed" : "ok");
		});
	`, nil, nil, env)
	if out.Error != "" {
		t.Fatalf("runScriptSource error = %q", out.Error)
	}
	if out.Result != "failed" {
		t.Fatalf("result = %q, want failed", out.Result)
	}
}

func scriptHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() { constant.SetHomeDir("") })
	if err := os.MkdirAll(filepath.Join(home, "mitm", "resources"), 0o700); err != nil {
		t.Fatal(err)
	}
	return home
}

func writeScriptResource(t *testing.T, home, name, source string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(home, "mitm", "resources", name), []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
}

func runScriptIntercept(t *testing.T, engine *Engine, rawURL, reqBody, respBody string) (*recordingInvoker, string) {
	t.Helper()
	invoker := &recordingInvoker{responseBody: []byte(respBody)}
	req := httptest.NewRequest(http.MethodPost, rawURL, bytes.NewReader([]byte(reqBody)))
	req.RequestURI = ""
	req.URL, _ = url.Parse(rawURL)
	req.ContentLength = int64(len(reqBody))
	resp, err := engine.intercept(context.Background(), req, invoker)
	if err != nil {
		t.Fatalf("intercept %s: %v", rawURL, err)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading response body: %v", err)
	}
	if err := resp.Body.Close(); err != nil {
		t.Fatalf("closing response body: %v", err)
	}
	return invoker, string(body)
}

func TestInterceptRunsRequestAndResponseScripts(t *testing.T) {
	home := scriptHome(t)
	writeScriptResource(t, home, "req.js", `
		$request.headers["X-Script"] = "yes";
		$request.body = "edited";
		$done();
	`)
	writeScriptResource(t, home, "resp.js", `
		$response.headers["X-Resp"] = "done";
		$response.body = "replaced";
		$done();
	`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Req = type=http-request,pattern=https://example.com/.*,script-path=req.js,requires-body=true`,
			`Resp = type=http-response,pattern=https://example.com/.*,script-path=resp.js,requires-body=true`,
		}},
	}
	invoker, seen := runScriptIntercept(t, engine, "https://example.com/api", "original", "upstream")
	if seen != "replaced" {
		t.Fatalf("client saw %q, want replaced", seen)
	}
	if invoker.requestBytes != len("edited") {
		t.Fatalf("upstream saw %d request bytes, want %d", invoker.requestBytes, len("edited"))
	}
}

func TestInterceptRequestScriptSeesHeaderOnlyWithoutBody(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "hdr.js", `
		$request.headers["X-Script"] = "yes";
		$done();
	`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Hdr = type=http-request,pattern=https://example.com/.*,script-path=hdr.js`,
		}},
	}
	invoker, seen := runScriptIntercept(t, engine, "https://example.com/api", "keep-me", "ok")
	if seen != "ok" {
		t.Fatalf("client saw %q, want ok", seen)
	}
	if invoker.requestBytes != len("keep-me") {
		t.Fatalf("upstream saw %d request bytes, want %d (header script must not touch the body)", invoker.requestBytes, len("keep-me"))
	}
}

func TestInterceptRequestScriptErrorLeavesExchangeAlone(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "boom.js", `throw new Error("boom")`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Boom = type=http-request,pattern=https://example.com/.*,script-path=boom.js`,
		}},
	}
	invoker, seen := runScriptIntercept(t, engine, "https://example.com/api", "body", "upstream")
	if seen != "upstream" || invoker.requestBytes != len("body") {
		t.Fatalf("client saw %q and upstream %d bytes, want upstream/body untouched", seen, invoker.requestBytes)
	}
}

func TestInterceptScriptPatternMatchesRewrittenURL(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "after.js", `
		$request.headers["X-After"] = "yes";
		$done();
	`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{
			URLRewrite: []string{"https://example.com/old https://example.com/new"},
			Script: []string{
				`After = type=http-request,pattern=https://example.com/new,script-path=after.js`,
			},
		},
	}
	invoker, _ := runScriptIntercept(t, engine, "https://example.com/old", "", "ok")
	if invoker.seenURL != "https://example.com/new" {
		t.Fatalf("upstream URL = %q, want the rewritten URL", invoker.seenURL)
	}
}

func TestInterceptCapturePathRunsResponseScripts(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "cap.js", `
		$response.body = "captured-edit";
		$done();
	`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Cap = type=http-response,pattern=https://example.com/.*,script-path=cap.js,requires-body=true`,
		}},
	}
	engine.SetCapture(true)
	_, seen := runScriptIntercept(t, engine, "https://example.com/api", "in", "out")
	if seen != "captured-edit" {
		t.Fatalf("client saw %q, want captured-edit", seen)
	}
	list := engine.Exchanges("")
	if len(list.Exchanges) != 1 {
		t.Fatalf("Exchanges() = %d, want 1", len(list.Exchanges))
	}
	ex := engine.Exchange(list.Exchanges[0].ID)
	if ex == nil {
		t.Fatal("exchange missing")
	}
	found := false
	for _, action := range ex.Actions {
		if action.Kind == "script" && action.Phase == "response" {
			found = true
		}
	}
	if !found {
		t.Fatalf("exchange actions = %+v, want a response script action", ex.Actions)
	}
}

func TestParseCronNext(t *testing.T) {
	cases := []struct {
		expr string
		from string
		want string
	}{
		{"* * * * *", "2026-11-15 10:00:30", "2026-11-15 10:01:00"},
		{"0 9 * * *", "2026-11-15 10:00:00", "2026-11-16 09:00:00"},
		{"*/15 * * * *", "2026-11-15 10:07:00", "2026-11-15 10:15:00"},
		{"30 8 15 * *", "2026-11-15 10:00:00", "2026-12-15 08:30:00"},
		{"0 0 * * 0", "2026-11-14 10:00:00", "2026-11-15 00:00:00"},
		{"0 12 1 * mon", "2026-11-15 10:00:00", "2026-11-16 12:00:00"},
		{"0 0 29 2 *", "2026-11-15 10:00:00", "2028-02-29 00:00:00"},
	}
	for _, tc := range cases {
		schedule, err := parseCron(tc.expr)
		if err != nil {
			t.Fatalf("parseCron(%q) = %v", tc.expr, err)
		}
		from, _ := time.ParseInLocation("2006-01-02 15:04:05", tc.from, time.UTC)
		want, _ := time.ParseInLocation("2006-01-02 15:04:05", tc.want, time.UTC)
		if got := schedule.next(from); !got.Equal(want) {
			t.Fatalf("parseCron(%q).next(%s) = %s, want %s", tc.expr, tc.from, got, want)
		}
	}
	for _, expr := range []string{"* * * *", "60 * * * *", "a b c d e", "* * * * 8", "0 0 * * * *"} {
		if _, err := parseCron(expr); err == nil {
			t.Fatalf("parseCron(%q) accepted an invalid expression", expr)
		}
	}
}

func TestCronNextDueAndRun(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "cron.js", `$persistentStore.write("yes", "fired"); $done("ran")`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Tick = type=cron,cronexp=* * * * *,script-path=cron.js`,
		}},
	}
	from, _ := time.ParseInLocation("2006-01-02 15:04:05", "2026-11-15 10:00:30", time.UTC)
	next, due := engine.nextCron(from)
	if len(due) != 1 || due[0].name != "Tick" {
		t.Fatalf("nextCron due = %+v, want one Tick", due)
	}
	want, _ := time.ParseInLocation("2006-01-02 15:04:05", "2026-11-15 10:01:00", time.UTC)
	if !next.Equal(want) {
		t.Fatalf("nextCron = %s, want %s", next, want)
	}
	out := engine.RunScript("Tick")
	if out.Error != "" || out.Result != "ran" {
		t.Fatalf("RunScript(Tick) = %+v, want result ran", out)
	}
	if got, ok := engine.persistentStore().read("Tick", "fired"); !ok || got != "yes" {
		t.Fatalf("store fired = %q, %v, want yes, true", got, ok)
	}
}

func TestCronStartStopIsIdempotent(t *testing.T) {
	engine := &Engine{exchange: NewExchangeStore(10)}
	engine.StartCron()
	engine.StartCron()
	engine.StopCron()
	engine.StopCron()
	engine.StartCron()
	engine.StopCron()
}

func TestInterceptBodyScriptOnBodilessRequestLeavesBodyNil(t *testing.T) {
	writeScriptResource(t, scriptHome(t), "get.js", `
		$done($request.body === undefined ? "no-body" : "has-body");
	`)
	engine := &Engine{
		exchange: NewExchangeStore(10),
		config: Config{Script: []string{
			`Get = type=http-request,pattern=https://example.com/.*,script-path=get.js,requires-body=true`,
		}},
	}
	invoker := &recordingInvoker{responseBody: []byte("ok")}
	req := httptest.NewRequest(http.MethodGet, "https://example.com/api", nil)
	req.RequestURI = ""
	req.URL, _ = url.Parse("https://example.com/api")
	req.Body = http.NoBody
	resp, err := engine.intercept(context.Background(), req, invoker)
	if err != nil {
		t.Fatalf("intercept: %v", err)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("reading response body: %v", err)
	}
	if string(body) != "ok" {
		t.Fatalf("client saw %q, want ok", body)
	}
	if invoker.requestBytes != 0 {
		t.Fatalf("upstream saw %d request bytes, want 0", invoker.requestBytes)
	}
	if req.Body != http.NoBody {
		t.Fatal("request Body was replaced for a bodiless request")
	}
}
