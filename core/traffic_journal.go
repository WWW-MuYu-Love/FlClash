package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

const trafficJournalDirectoryName = "traffic"
const trafficJournalFileSuffix = ".jsonl"
const trafficJournalPollInterval = time.Second
const trafficJournalRetention = 3 * 24 * time.Hour
const trafficJournalPruneInterval = time.Hour
const trafficJournalErrorLogInterval = time.Minute

type trafficJournalLine struct {
	ID          string `json:"id"`
	Host        string `json:"host"`
	Process     string `json:"process"`
	Proxy       string `json:"proxy"`
	Node        string `json:"node"`
	Direct      bool   `json:"direct"`
	Rule        string `json:"rule"`
	RulePayload string `json:"rulePayload"`
	Upload      int64  `json:"upload"`
	Download    int64  `json:"download"`
	Start       int64  `json:"start"`
	End         int64  `json:"end"`
}

func newTrafficJournalLine(id string, info *statistic.TrackerInfo, end time.Time) trafficJournalLine {
	node := ""
	proxy := ""
	if chains := info.Chain; len(chains) > 0 {
		node = chains[0]
		proxy = chains[len(chains)-1]
	}
	host := ""
	process := ""
	if metadata := info.Metadata; metadata != nil {
		host = metadata.Host
		process = metadata.Process
	}
	return trafficJournalLine{
		ID:          id,
		Host:        host,
		Process:     process,
		Proxy:       proxy,
		Node:        node,
		Direct:      node == "DIRECT",
		Rule:        info.Rule,
		RulePayload: info.RulePayload,
		Upload:      info.UploadTotal.Load(),
		Download:    info.DownloadTotal.Load(),
		Start:       info.Start.UnixMilli(),
		End:         end.UnixMilli(),
	}
}

type trafficJournalEntry struct {
	id   string
	info *statistic.TrackerInfo
}

type trafficJournal struct {
	mu           sync.Mutex
	dir          string
	open         map[string]*statistic.TrackerInfo
	started      bool
	lastPrune    time.Time
	lastErrorLog time.Time
}

func newTrafficJournal() *trafficJournal {
	return &trafficJournal{open: make(map[string]*statistic.TrackerInfo)}
}

var defaultTrafficJournal = newTrafficJournal()

func setupTrafficJournal(homeDir string) {
	defaultTrafficJournal.setup(homeDir)
}

func trackTrafficConnection(id string, info *statistic.TrackerInfo) {
	defaultTrafficJournal.track(id, info)
}

func flushTrafficJournal() {
	defaultTrafficJournal.flush()
}

func (j *trafficJournal) setup(homeDir string) {
	if homeDir == "" {
		return
	}
	j.mu.Lock()
	if j.dir == "" {
		j.dir = filepath.Join(homeDir, trafficJournalDirectoryName)
	}
	start := !j.started
	if start {
		j.started = true
	}
	j.mu.Unlock()
	if start {
		safeGo("trafficJournal", j.run)
	}
}

func (j *trafficJournal) track(id string, info *statistic.TrackerInfo) {
	if info == nil {
		return
	}
	j.mu.Lock()
	defer j.mu.Unlock()
	if j.dir == "" {
		return
	}
	j.open[id] = info
}

func (j *trafficJournal) run() {
	ticker := time.NewTicker(trafficJournalPollInterval)
	defer ticker.Stop()
	for range ticker.C {
		j.poll()
	}
}

func (j *trafficJournal) poll() {
	live := make(map[string]struct{})
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		live[c.ID()] = struct{}{}
		return true
	})
	j.mu.Lock()
	closed := make([]trafficJournalEntry, 0, len(j.open))
	for id, info := range j.open {
		if _, ok := live[id]; !ok {
			closed = append(closed, trafficJournalEntry{id: id, info: info})
			delete(j.open, id)
		}
	}
	dir := j.dir
	now := time.Now()
	pruneDue := now.Sub(j.lastPrune) >= trafficJournalPruneInterval
	if pruneDue {
		j.lastPrune = now
	}
	j.mu.Unlock()
	if len(closed) > 0 && dir != "" {
		j.writeLines(dir, closed, now)
	}
	if pruneDue && dir != "" {
		j.prune(dir, now)
	}
}

func (j *trafficJournal) flush() {
	j.mu.Lock()
	if len(j.open) == 0 || j.dir == "" {
		j.mu.Unlock()
		return
	}
	closed := make([]trafficJournalEntry, 0, len(j.open))
	for id, info := range j.open {
		closed = append(closed, trafficJournalEntry{id: id, info: info})
	}
	clear(j.open)
	dir := j.dir
	j.mu.Unlock()
	j.writeLines(dir, closed, time.Now())
}

func (j *trafficJournal) writeLines(dir string, closed []trafficJournalEntry, now time.Time) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		j.logError("traffic journal mkdir failed: %v", err)
		return
	}
	path := filepath.Join(dir, now.Format("2006-01-02-15")+trafficJournalFileSuffix)
	for _, entry := range closed {
		line, err := json.Marshal(newTrafficJournalLine(entry.id, entry.info, now))
		if err != nil {
			j.logError("traffic journal encode failed: %v", err)
			continue
		}
		if err := appendJournalLine(path, line); err != nil {
			j.logError("traffic journal write failed: %v", err)
			return
		}
	}
}

func appendJournalLine(path string, line []byte) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = file.Write(append(line, '\n'))
	return err
}

func (j *trafficJournal) prune(dir string, now time.Time) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if !strings.HasSuffix(name, trafficJournalFileSuffix) {
			continue
		}
		hour, err := time.Parse(
			"2006-01-02-15",
			strings.TrimSuffix(name, trafficJournalFileSuffix),
		)
		if err != nil || !hour.Add(trafficJournalRetention).Before(now) {
			continue
		}
		_ = os.Remove(filepath.Join(dir, name))
	}
}

func (j *trafficJournal) logError(format string, args ...any) {
	j.mu.Lock()
	now := time.Now()
	if now.Sub(j.lastErrorLog) < trafficJournalErrorLogInterval {
		j.mu.Unlock()
		return
	}
	j.lastErrorLog = now
	j.mu.Unlock()
	logError(format, args...)
}
