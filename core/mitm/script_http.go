package mitm

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/dop251/goja"
	"golang.org/x/net/proxy"
)

const httpClientTimeout = 15 * time.Second

// maxHTTPClientBody caps a $httpClient response body; a larger one fails
// the call instead of growing the script's memory without bound.
const maxHTTPClientBody = 16 << 20

// newScriptHTTPClient builds the client $httpClient dials with; a mixed port routes through it as SOCKS5.
func newScriptHTTPClient(mixedPort int) *http.Client {
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	transport := &http.Transport{
		DialContext:         dialer.DialContext,
		ForceAttemptHTTP2:   true,
		MaxIdleConns:        10,
		IdleConnTimeout:     30 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
	}
	if mixedPort > 0 {
		if socks, err := proxy.SOCKS5("tcp", fmt.Sprintf("127.0.0.1:%d", mixedPort), nil, proxy.Direct); err == nil {
			transport.DialContext = func(_ context.Context, network, addr string) (net.Conn, error) {
				return socks.Dial(network, addr)
			}
		}
	}
	return &http.Client{Transport: transport, Timeout: httpClientTimeout}
}

// setHTTPClient installs $httpClient: get/post/put/delete/head/patch, each
// taking Surge's ({url, headers, body, timeout}, callback) shape. The fetch
// runs inside the call; an error reaches the callback as a string, never
// as a throw.
func setHTTPClient(rt *goja.Runtime, client *http.Client, out *ScriptOutput) {
	call := func(method string) func(goja.Value, goja.Value) {
		return func(options, callback goja.Value) {
			callHTTPClient(rt, client, method, options, callback, out)
		}
	}
	rt.Set("$httpClient", map[string]any{
		"get":    call(http.MethodGet),
		"post":   call(http.MethodPost),
		"put":    call(http.MethodPut),
		"delete": call(http.MethodDelete),
		"head":   call(http.MethodHead),
		"patch":  call(http.MethodPatch),
	})
}

func callHTTPClient(rt *goja.Runtime, client *http.Client, method string, options, callback goja.Value, out *ScriptOutput) {
	done := func(err any, response *goja.Object, data string) {
		callable, ok := goja.AssertFunction(callback)
		if !ok {
			return
		}
		var errArg goja.Value = goja.Null()
		if err != nil {
			errArg = rt.ToValue(fmt.Sprint(err))
		}
		var respArg goja.Value = goja.Null()
		if response != nil {
			respArg = response
		}
		if _, callErr := callable(goja.Undefined(), errArg, respArg, rt.ToValue(data)); callErr != nil {
			out.Logs = append(out.Logs, fmt.Sprintf("$httpClient callback: %v", formatJSError(callErr)))
		}
	}
	req, cancel, err := httpRequestFromJS(method, options)
	if err != nil {
		done(err.Error(), nil, "")
		return
	}
	defer cancel()
	resp, err := client.Do(req)
	if err != nil {
		done(err.Error(), nil, "")
		return
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxHTTPClientBody+1))
	if err != nil {
		done(err.Error(), nil, "")
		return
	}
	if len(body) > maxHTTPClientBody {
		done("response body exceeds 16 MiB", nil, "")
		return
	}
	done(nil, httpResponseToJS(rt, resp, body), string(body))
}

func httpRequestFromJS(method string, options goja.Value) (*http.Request, context.CancelFunc, error) {
	exported, ok := options.Export().(map[string]any)
	if !ok {
		return nil, nil, fmt.Errorf("$httpClient: options must be an object")
	}
	rawURL, _ := exported["url"].(string)
	if rawURL == "" {
		return nil, nil, fmt.Errorf("$httpClient: missing url")
	}
	var body io.Reader
	if raw, ok := exported["body"]; ok && raw != nil {
		if s, ok := raw.(string); ok {
			body = strings.NewReader(s)
		}
	}
	timeout := httpClientTimeout
	if raw, ok := exported["timeout"]; ok {
		if seconds, ok := raw.(float64); ok && seconds > 0 && seconds <= 15 {
			timeout = time.Duration(seconds * float64(time.Second))
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	req, err := http.NewRequestWithContext(ctx, method, rawURL, body)
	if err != nil {
		cancel()
		return nil, nil, err
	}
	if headers, ok := exported["headers"].(map[string]any); ok {
		for name, v := range headers {
			if s, ok := v.(string); ok {
				req.Header.Set(name, s)
			}
		}
	}
	return req, cancel, nil
}

func httpResponseToJS(rt *goja.Runtime, resp *http.Response, body []byte) *goja.Object {
	obj := rt.NewObject()
	obj.Set("status", resp.StatusCode)
	obj.Set("statusCode", resp.StatusCode)
	obj.Set("headers", headersToJS(rt, resp.Header))
	obj.Set("body", string(body))
	return obj
}
