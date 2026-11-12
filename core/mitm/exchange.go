package mitm

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	mitmproxy "github.com/josexy/mitmproxy-go"
)

// maxRecordedBody caps how much of a body the store keeps per side.
const maxRecordedBody = 1 << 20 // 1 MiB

// capturesDirName is the home-relative directory for persisted captures,
// shared with the app so the history does not count against the
// extension's memory limit.
const capturesDirName = "captures"

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

// HostList is the mitm.hosts answer: the hosts with recorded exchanges.
type HostList struct {
	Hosts []string `json:"hosts"`
}

// Body is one side of an exchange as base64 (MitmBody).
type Body struct {
	Data      string `json:"data"`
	Truncated bool   `json:"truncated"`
	Encoding  string `json:"encoding"`
}

// storedExchange is the on-disk form of one completed exchange: the
// Exchange meta plus its unexported truncation flags. Bodies live in
// sibling <id>.request / <id>.response files.
type storedExchange struct {
	Exchange
	RequestTruncated  bool `json:"request-truncated"`
	ResponseTruncated bool `json:"response-truncated"`
}

// ExchangeStore keeps decrypted exchanges, bounded by a capture limit. It is
// safe for concurrent use. With dir set, completed exchanges are persisted
// there and only summaries stay in memory; without one it keeps everything.
type ExchangeStore struct {
	mu      sync.RWMutex
	seq     atomic.Int64
	connSeq atomic.Int64
	limit   int
	since   time.Time
	byID    map[int]*Exchange
	order   []int
	closed  map[string]bool
	dir     string
}

// NewExchangeStore creates a store bounded to limit entries (0 disables the
// bound only when capture is off; a non-positive limit keeps the default).
func NewExchangeStore(limit int) *ExchangeStore {
	return NewExchangeStoreWithDir(limit, "")
}

func NewExchangeStoreWithDir(limit int, dir string) *ExchangeStore {
	if limit <= 0 {
		limit = defaultCaptureEntries
	}
	s := &ExchangeStore{
		limit:  limit,
		since:  time.Now(),
		byID:   map[int]*Exchange{},
		closed: map[string]bool{},
	}
	s.SetDir(dir)
	return s
}

// SetDir points the store at dir, loading the summaries already there.
// A second call with the same dir, or an empty dir, is a no-op.
func (s *ExchangeStore) SetDir(dir string) {
	if dir == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.dir == dir {
		return
	}
	s.dir = dir
	_ = os.MkdirAll(dir, 0o700)
	s.loadLocked()
}

func (s *ExchangeStore) metaPath(id int) string {
	return filepath.Join(s.dir, strconv.Itoa(id)+".json")
}

func (s *ExchangeStore) bodyPath(id int, response bool) string {
	suffix := ".request"
	if response {
		suffix = ".response"
	}
	return filepath.Join(s.dir, strconv.Itoa(id)+suffix)
}

func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, perm); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func (s *ExchangeStore) persistLocked(ex *Exchange) {
	if s.dir == "" {
		return
	}
	meta, err := json.Marshal(storedExchange{
		Exchange:          *ex,
		RequestTruncated:  ex.requestTruncated,
		ResponseTruncated: ex.responseTruncated,
	})
	if err != nil {
		return
	}
	_ = writeFileAtomic(s.metaPath(ex.ID), meta, 0o600)
	if len(ex.requestBody) > 0 {
		_ = writeFileAtomic(s.bodyPath(ex.ID, false), ex.requestBody, 0o600)
	}
	if len(ex.responseBody) > 0 {
		_ = writeFileAtomic(s.bodyPath(ex.ID, true), ex.responseBody, 0o600)
	}
}

func (s *ExchangeStore) loadLocked() {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return
	}
	var ids []int
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		id, err := strconv.Atoi(strings.TrimSuffix(entry.Name(), ".json"))
		if err != nil {
			continue
		}
		ids = append(ids, id)
	}
	sort.Ints(ids)
	if s.limit > 0 && len(ids) > s.limit {
		for _, id := range ids[:len(ids)-s.limit] {
			s.removeFilesLocked(id)
		}
		ids = ids[len(ids)-s.limit:]
	}
	for _, id := range ids {
		data, err := os.ReadFile(s.metaPath(id))
		if err != nil {
			continue
		}
		var stored storedExchange
		if err := json.Unmarshal(data, &stored); err != nil {
			continue
		}
		ex := stored.Exchange
		ex.requestTruncated = stored.RequestTruncated
		ex.responseTruncated = stored.ResponseTruncated
		if _, ok := s.byID[id]; ok {
			continue
		}
		s.byID[id] = &ex
		s.order = append(s.order, id)
		if int64(id) > s.seq.Load() {
			s.seq.Store(int64(id))
		}
	}
	sort.Ints(s.order)
}

func (s *ExchangeStore) removeFilesLocked(id int) {
	if s.dir == "" {
		return
	}
	_ = os.Remove(s.metaPath(id))
	_ = os.Remove(s.bodyPath(id, false))
	_ = os.Remove(s.bodyPath(id, true))
}

// complete persists a finished exchange and drops its bodies from memory.
// It is a no-op for a pending exchange, or a store with no dir.
func (s *ExchangeStore) complete(ex *Exchange) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.completeLocked(ex)
}

func (s *ExchangeStore) completeLocked(ex *Exchange) {
	if ex.Pending || s.dir == "" {
		return
	}
	if s.byID[ex.ID] != ex {
		return
	}
	s.persistLocked(ex)
	ex.requestBody = nil
	ex.responseBody = nil
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
// Bodies are teed, never buffered and replaced: the request body is read by
// the upstream during Invoke, the response body by the client after Intercept returns.
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
	var reqCapture *cappedCapture
	if req.Body != nil {
		reqCapture = &cappedCapture{}
		req.Body = io.NopCloser(io.TeeReader(req.Body, reqCapture))
	}
	s.add(ex)
	applyRequestRewrites(e, req, ex)

	resp, err := invoker.Invoke(req)
	if reqCapture != nil {
		ex.requestBody, ex.requestTruncated = reqCapture.snapshot()
		ex.RequestSize = int(reqCapture.total)
	}
	if err != nil {
		ex.Pending = false
		ex.Duration = time.Since(start).Milliseconds()
		ex.Error = err.Error()
		s.complete(ex)
		return resp, err
	}
	ex.TTFB = time.Since(start).Milliseconds()
	ex.Status = resp.StatusCode
	ex.ResponseHeader = cloneHeader(resp.Header)
	if resp.Body != nil {
		resp.Body = newTeeBody(resp.Body, func(capture *cappedCapture) {
			s.finishResponse(ex, start, capture)
		})
	}
	applyResponseRewrites(e, resp, ex)
	return resp, nil
}

func (s *ExchangeStore) finishResponse(ex *Exchange, start time.Time, capture *cappedCapture) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.byID[ex.ID] != ex {
		return
	}
	ex.responseBody, ex.responseTruncated = capture.snapshot()
	ex.ResponseSize = int(capture.total)
	ex.Pending = false
	ex.Duration = time.Since(start).Milliseconds()
	s.completeLocked(ex)
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
		s.removeFilesLocked(oldest)
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

func (s *ExchangeStore) Get(id int) *Exchange {
	s.mu.RLock()
	ex := s.byID[id]
	dir := s.dir
	s.mu.RUnlock()
	if ex != nil || dir == "" {
		return ex
	}
	stored, err := s.loadStored(id)
	if err != nil {
		return nil
	}
	loaded := stored.Exchange
	loaded.requestTruncated = stored.RequestTruncated
	loaded.responseTruncated = stored.ResponseTruncated
	return &loaded
}

// Hosts returns the distinct hosts with recorded exchanges, lowercased and
// sorted, so the app can mark decrypted connections without a per-connection
// id: the tracker's ids never reach the store.
func (s *ExchangeStore) Hosts() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	seen := make(map[string]struct{})
	for _, id := range s.order {
		ex := s.byID[id]
		if ex == nil {
			continue
		}
		if host := exchangeHost(ex.URL); host != "" {
			seen[host] = struct{}{}
		}
	}
	hosts := make([]string, 0, len(seen))
	for host := range seen {
		hosts = append(hosts, host)
	}
	sort.Strings(hosts)
	return hosts
}

// ListByHost returns the exchanges for one host, oldest first. A host has
// many connections over time, so the list is never closed.
func (s *ExchangeStore) ListByHost(host string, capturing bool) *ExchangeList {
	host = normalizeHost(host)
	s.mu.RLock()
	defer s.mu.RUnlock()
	list := &ExchangeList{Capturing: capturing, Since: s.since}
	for _, id := range s.order {
		ex := s.byID[id]
		if ex == nil || exchangeHost(ex.URL) != host {
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

// exchangeHost reports the lowercased host of an exchange URL, or "" when
// the URL has none.
func exchangeHost(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return ""
	}
	return strings.ToLower(u.Hostname())
}

// normalizeHost lowercases a host and strips a port, matching the hostname
// list's treatment of host:port strings.
func normalizeHost(host string) string {
	host = strings.ToLower(strings.TrimSpace(host))
	if h, _, err := splitHostPort(host); err == nil {
		host = h
	}
	return host
}

func (s *ExchangeStore) Body(id int, response bool) *Body {
	s.mu.RLock()
	ex := s.byID[id]
	dir := s.dir
	s.mu.RUnlock()
	if ex == nil {
		return nil
	}
	var data []byte
	var truncated bool
	if response {
		data, truncated = ex.responseBody, ex.responseTruncated
	} else {
		data, truncated = ex.requestBody, ex.requestTruncated
	}
	if data == nil && dir != "" && !ex.Pending {
		data, truncated = s.readBodyFile(id, response, truncated)
	}
	return &Body{Data: base64.StdEncoding.EncodeToString(data), Truncated: truncated}
}

func (s *ExchangeStore) readBodyFile(id int, response bool, truncated bool) ([]byte, bool) {
	s.mu.RLock()
	dir := s.dir
	s.mu.RUnlock()
	if dir == "" {
		return nil, truncated
	}
	suffix := ".request"
	if response {
		suffix = ".response"
	}
	data, err := os.ReadFile(filepath.Join(dir, strconv.Itoa(id)+suffix))
	if err != nil {
		return nil, truncated
	}
	if stored, err := s.loadStored(id); err == nil {
		if response {
			truncated = stored.ResponseTruncated
		} else {
			truncated = stored.RequestTruncated
		}
	}
	return data, truncated
}

func (s *ExchangeStore) loadStored(id int) (storedExchange, error) {
	var stored storedExchange
	s.mu.RLock()
	dir := s.dir
	s.mu.RUnlock()
	if dir == "" {
		return stored, os.ErrNotExist
	}
	data, err := os.ReadFile(filepath.Join(dir, strconv.Itoa(id)+".json"))
	if err != nil {
		return stored, err
	}
	if err := json.Unmarshal(data, &stored); err != nil {
		return stored, err
	}
	return stored, nil
}

// MarkClosed records that a MITM connection has ended.
func (s *ExchangeStore) MarkClosed(connectionID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.closed[connectionID] = true
}

func (s *ExchangeStore) Clear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byID = map[int]*Exchange{}
	s.order = nil
	s.since = time.Now()
	if s.dir == "" {
		return
	}
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		switch filepath.Ext(entry.Name()) {
		case ".json", ".request", ".response":
			_ = os.Remove(filepath.Join(s.dir, entry.Name()))
		}
	}
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

type cappedCapture struct {
	buf   []byte
	total int64
}

func (c *cappedCapture) Write(p []byte) (int, error) {
	c.total += int64(len(p))
	if len(c.buf) < maxRecordedBody {
		room := maxRecordedBody - len(c.buf)
		if len(p) < room {
			room = len(p)
		}
		c.buf = append(c.buf, p[:room]...)
	}
	return len(p), nil
}

func (c *cappedCapture) snapshot() ([]byte, bool) {
	return c.buf, c.total > maxRecordedBody
}

// The framework may swap an empty body for http.NoBody without closing the
// original, so the exchange finishes when the body is fully read or closed.
type teeBody struct {
	body    io.ReadCloser
	tee     io.Reader
	capture *cappedCapture
	finish  sync.Once
	onDone  func(*cappedCapture)
}

func newTeeBody(body io.ReadCloser, onDone func(*cappedCapture)) *teeBody {
	capture := &cappedCapture{}
	return &teeBody{body: body, tee: io.TeeReader(body, capture), capture: capture, onDone: onDone}
}

func (t *teeBody) Read(p []byte) (int, error) {
	n, err := t.tee.Read(p)
	if err == io.EOF {
		t.finish.Do(func() { t.onDone(t.capture) })
	}
	return n, err
}

func (t *teeBody) Close() error {
	err := t.body.Close()
	t.finish.Do(func() { t.onDone(t.capture) })
	return err
}

// applyRequestRewrites applies URL and header rewrites to a decrypted request.
func applyRequestRewrites(e *Engine, req *http.Request, ex *Exchange) {
	ex.Actions = append(ex.Actions, requestRewriteActions(e, req)...)
}

func requestRewriteActions(e *Engine, req *http.Request) []Action {
	e.mu.RLock()
	rules := e.config
	e.mu.RUnlock()
	var actions []Action
	for _, line := range rules.URLRewrite {
		if applyURLRewrite(req, line) {
			actions = append(actions, Action{Kind: "url-rewrite", Phase: "request", Detail: line})
		}
	}
	for _, line := range rules.HeaderRewrite {
		if applyHeaderRewrite(req.Header, line) {
			actions = append(actions, Action{Kind: "header-rewrite", Phase: "request", Detail: line})
		}
	}
	return actions
}

// applyResponseRewrites applies header rewrites to a decrypted response.
func applyResponseRewrites(e *Engine, resp *http.Response, ex *Exchange) {
	ex.Actions = append(ex.Actions, responseRewriteActions(e, resp)...)
}

func responseRewriteActions(e *Engine, resp *http.Response) []Action {
	e.mu.RLock()
	rules := e.config
	e.mu.RUnlock()
	var actions []Action
	for _, line := range rules.HeaderRewrite {
		if applyHeaderRewrite(resp.Header, line) {
			actions = append(actions, Action{Kind: "header-rewrite", Phase: "response", Detail: line})
		}
	}
	return actions
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
