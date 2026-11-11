package mitm

import (
	"bytes"
	"context"
	"encoding/base64"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	mitmproxy "github.com/josexy/mitmproxy-go"
)

// maxRecordedBody caps how much of a body the store keeps per side.
const maxRecordedBody = 1 << 20 // 1 MiB

// Action is one rewrite or observation applied to an exchange (MitmAction).
type Action struct {
	Kind   string `json:"kind"`
	Phase  string `json:"phase"`
	Detail string `json:"detail"`
}

// Exchange is one decrypted request/response pair (MitmExchange).
type Exchange struct {
	ID             int                 `json:"id"`
	Start          time.Time           `json:"start"`
	Pending        bool                `json:"pending"`
	Duration       int64               `json:"duration"`
	TTFB           int64               `json:"ttfb"`
	Method         string              `json:"method"`
	URL            string              `json:"url"`
	OriginalURL    string              `json:"original-url"`
	Proto          string              `json:"proto"`
	Status         int                 `json:"status"`
	RequestSize    int                 `json:"request-size"`
	ResponseSize   int                 `json:"response-size"`
	Error          string              `json:"error"`
	Connection     string              `json:"connection"`
	RequestHeader  map[string][]string `json:"request-header"`
	ResponseHeader map[string][]string `json:"response-header"`
	Actions        []Action            `json:"actions"`

	requestBody       []byte
	responseBody      []byte
	requestTruncated  bool
	responseTruncated bool
}

// Summary is the list form of an exchange (MitmExchangeSummary).
type Summary struct {
	ID           int       `json:"id"`
	Start        time.Time `json:"start"`
	Pending      bool      `json:"pending"`
	Duration     int64     `json:"duration"`
	Method       string    `json:"method"`
	URL          string    `json:"url"`
	Status       int       `json:"status"`
	RequestSize  int       `json:"request-size"`
	ResponseSize int       `json:"response-size"`
	Error        string    `json:"error"`
}

// ExchangeList is the mitm.exchanges answer (MitmExchangeList).
type ExchangeList struct {
	Capturing bool      `json:"capturing"`
	Since     time.Time `json:"since"`
	Exchanges []Summary `json:"exchanges"`
	Closed    bool      `json:"closed"`
}

// Body is one side of an exchange as base64 (MitmBody).
type Body struct {
	Data      string `json:"data"`
	Truncated bool   `json:"truncated"`
	Encoding  string `json:"encoding"`
}

// ExchangeStore keeps decrypted exchanges, bounded by a capture limit. It is
// safe for concurrent use.
type ExchangeStore struct {
	mu      sync.RWMutex
	seq     atomic.Int64
	connSeq atomic.Int64
	limit   int
	since   time.Time
	byID    map[int]*Exchange
	order   []int
	closed  map[string]bool
}

// NewExchangeStore creates a store bounded to limit entries (0 disables the
// bound only when capture is off; a non-positive limit keeps the default).
func NewExchangeStore(limit int) *ExchangeStore {
	if limit <= 0 {
		limit = defaultCaptureEntries
	}
	return &ExchangeStore{
		limit:  limit,
		since:  time.Now(),
		byID:   map[int]*Exchange{},
		closed: map[string]bool{},
	}
}

// SetLimit changes the capture bound. Entries beyond it are dropped oldest
// first.
func (s *ExchangeStore) SetLimit(limit int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if limit <= 0 {
		limit = defaultCaptureEntries
	}
	s.limit = limit
	s.evictLocked()
}

// NextConnectionID allocates an id for one MITM connection.
func (s *ExchangeStore) NextConnectionID() string {
	return strconv.FormatInt(s.connSeq.Add(1), 10)
}

// Intercept runs on every decrypted request: it records the exchange, applies
// the configured rewrites, and returns the (possibly rewritten) response.
func (s *ExchangeStore) Intercept(ctx context.Context, e *Engine, req *http.Request, invoker mitmproxy.HTTPDelegatedInvoker) (*http.Response, error) {
	connID := connectionIDFromContext(ctx)
	start := time.Now()
	id := int(s.seq.Add(1))
	ex := &Exchange{
		ID:            id,
		Start:         start,
		Pending:       true,
		Method:        req.Method,
		URL:           req.URL.String(),
		OriginalURL:   req.URL.String(),
		Proto:         req.Proto,
		Connection:    connID,
		RequestHeader: cloneHeader(req.Header),
	}
	// Capture the request body, then restore it for the upstream call.
	if req.Body != nil {
		body, truncated := readCapped(req.Body)
		ex.requestBody = body
		ex.requestTruncated = truncated
		ex.RequestSize = len(body)
		req.Body = io.NopCloser(bytes.NewReader(body))
		req.ContentLength = int64(len(body))
	}
	s.add(ex)
	applyRequestRewrites(e, req, ex)

	resp, err := invoker.Invoke(req)
	if err != nil {
		ex.Pending = false
		ex.Duration = time.Since(start).Milliseconds()
		ex.Error = err.Error()
		return resp, err
	}
	ex.TTFB = time.Since(start).Milliseconds()
	ex.Status = resp.StatusCode
	ex.ResponseHeader = cloneHeader(resp.Header)
	if resp.Body != nil {
		body, truncated := readCapped(resp.Body)
		ex.responseBody = body
		ex.responseTruncated = truncated
		ex.ResponseSize = len(body)
		resp.Body = io.NopCloser(bytes.NewReader(body))
		resp.ContentLength = int64(len(body))
	}
	applyResponseRewrites(e, resp, ex)
	ex.Pending = false
	ex.Duration = time.Since(start).Milliseconds()
	return resp, nil
}

func (s *ExchangeStore) add(ex *Exchange) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byID[ex.ID] = ex
	s.order = append(s.order, ex.ID)
	s.evictLocked()
}

func (s *ExchangeStore) evictLocked() {
	for len(s.order) > s.limit {
		oldest := s.order[0]
		s.order = s.order[1:]
		delete(s.byID, oldest)
	}
}

// List returns the exchanges for a connection, oldest first.
func (s *ExchangeStore) List(connectionID string, capturing bool) *ExchangeList {
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := &ExchangeList{Capturing: capturing, Since: s.since, Closed: s.closed[connectionID]}
	for _, id := range s.order {
		ex := s.byID[id]
		if ex == nil {
			continue
		}
		if connectionID != "" && ex.Connection != connectionID {
			continue
		}
		list.Exchanges = append(list.Exchanges, Summary{
			ID: ex.ID, Start: ex.Start, Pending: ex.Pending,
			Duration: ex.Duration, Method: ex.Method, URL: ex.URL,
			Status: ex.Status, RequestSize: ex.RequestSize,
			ResponseSize: ex.ResponseSize, Error: ex.Error,
		})
	}
	return list
}

// Get returns one exchange by id, or nil.
func (s *ExchangeStore) Get(id int) *Exchange {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.byID[id]
}

// Body returns one side of an exchange as base64, or nil.
func (s *ExchangeStore) Body(id int, response bool) *Body {
	s.mu.RLock()
	defer s.mu.RUnlock()
	ex := s.byID[id]
	if ex == nil {
		return nil
	}
	if response {
		return &Body{Data: base64.StdEncoding.EncodeToString(ex.responseBody), Truncated: ex.responseTruncated}
	}
	return &Body{Data: base64.StdEncoding.EncodeToString(ex.requestBody), Truncated: ex.requestTruncated}
}

// MarkClosed records that a MITM connection has ended.
func (s *ExchangeStore) MarkClosed(connectionID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed[connectionID] = true
}

// Clear drops all recorded exchanges.
func (s *ExchangeStore) Clear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byID = map[int]*Exchange{}
	s.order = nil
	s.since = time.Now()
}

// connectionIDKey carries the MITM connection id through the interceptor
// context.
type connectionIDKey struct{}

func contextWithConnectionID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, connectionIDKey{}, id)
}

func connectionIDFromContext(ctx context.Context) string {
	if id, ok := ctx.Value(connectionIDKey{}).(string); ok {
		return id
	}
	return ""
}

func cloneHeader(h http.Header) map[string][]string {
	out := make(map[string][]string, len(h))
	for k, v := range h {
		cp := make([]string, len(v))
		copy(cp, v)
		out[k] = cp
	}
	return out
}

// readCapped reads up to maxRecordedBody bytes, reporting truncation.
func readCapped(r io.Reader) ([]byte, bool) {
	body, err := io.ReadAll(io.LimitReader(r, maxRecordedBody+1))
	if err != nil {
		return nil, false
	}
	if len(body) > maxRecordedBody {
		return body[:maxRecordedBody], true
	}
	return body, false
}

// applyRequestRewrites applies URL and header rewrites to a decrypted request.
func applyRequestRewrites(e *Engine, req *http.Request, ex *Exchange) {
	e.mu.RLock()
	rules := e.config
	e.mu.RUnlock()
	for _, line := range rules.URLRewrite {
		if applyURLRewrite(req, line) {
			ex.Actions = append(ex.Actions, Action{Kind: "url-rewrite", Phase: "request", Detail: line})
		}
	}
	for _, line := range rules.HeaderRewrite {
		if applyHeaderRewrite(req.Header, line) {
			ex.Actions = append(ex.Actions, Action{Kind: "header-rewrite", Phase: "request", Detail: line})
		}
	}
}

// applyResponseRewrites applies header rewrites to a decrypted response.
func applyResponseRewrites(e *Engine, resp *http.Response, ex *Exchange) {
	e.mu.RLock()
	rules := e.config
	e.mu.RUnlock()
	for _, line := range rules.HeaderRewrite {
		if applyHeaderRewrite(resp.Header, line) {
			ex.Actions = append(ex.Actions, Action{Kind: "header-rewrite", Phase: "response", Detail: line})
		}
	}
}

// applyURLRewrite rewrites req.URL when line matches "<pattern> <replacement>".
func applyURLRewrite(req *http.Request, line string) bool {
	parts := splitRewriteLine(line)
	if len(parts) < 2 {
		return false
	}
	pattern, replacement := parts[0], parts[1]
	if !matchURLPattern(pattern, req.URL.String()) {
		return false
	}
	if u, err := parseURL(replacement); err == nil {
		req.URL = u
		req.Host = u.Host
		return true
	}
	return false
}

// applyHeaderRewrite applies "<pattern> <header>: <value>" to a header map.
func applyHeaderRewrite(header http.Header, line string) bool {
	parts := splitRewriteLine(line)
	if len(parts) < 2 {
		return false
	}
	kv := splitHeaderValue(parts[1])
	if kv == nil {
		return false
	}
	header.Set(kv[0], kv[1])
	return true
}

func splitRewriteLine(line string) []string {
	return splitFields(line)
}

func splitFields(s string) []string {
	var out []string
	var b bytes.Buffer
	inQuote := false
	for _, r := range s {
		switch {
		case r == '"':
			inQuote = !inQuote
		case r == ' ' || r == '\t':
			if inQuote {
				b.WriteRune(r)
			} else if b.Len() > 0 {
				out = append(out, b.String())
				b.Reset()
			}
		default:
			b.WriteRune(r)
		}
	}
	if b.Len() > 0 {
		out = append(out, b.String())
	}
	return out
}

func splitHeaderValue(s string) []string {
	for i := 0; i < len(s); i++ {
		if s[i] == ':' {
			return []string{trimSpace(s[:i]), trimSpace(s[i+1:])}
		}
	}
	return nil
}

func trimSpace(s string) string {
	return string(bytes.TrimSpace([]byte(s)))
}

func matchURLPattern(pattern, rawurl string) bool {
	if pattern == "*" {
		return true
	}
	// A plain prefix match covers the common Surge/Loon rewrite shape.
	return len(rawurl) >= len(pattern) && rawurl[:len(pattern)] == pattern
}

func parseURL(s string) (*url.URL, error) {
	return url.Parse(s)
}
