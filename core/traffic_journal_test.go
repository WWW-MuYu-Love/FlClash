package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func testTrafficInfo(upload, download int64) *statistic.TrackerInfo {
	info := &statistic.TrackerInfo{
		Metadata: &constant.Metadata{Host: "example.com", Process: "Safari"},
		Start:    time.Date(2026, 11, 23, 10, 0, 0, 0, time.UTC),
		Chain:    constant.Chain{"Node-A", "Proxy"},
		Rule:     "RULE-SET",
		RulePayload: "ads",
	}
	info.UploadTotal.Store(upload)
	info.DownloadTotal.Store(download)
	return info
}

func readJournalLines(t *testing.T, dir string) []trafficJournalLine {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("read journal dir: %v", err)
	}
	var lines []trafficJournalLine
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), trafficJournalFileSuffix) {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			t.Fatalf("read journal file: %v", err)
		}
		for _, raw := range strings.Split(strings.TrimSpace(string(data)), "\n") {
			if raw == "" {
				continue
			}
			var line trafficJournalLine
			if err := json.Unmarshal([]byte(raw), &line); err != nil {
				t.Fatalf("decode journal line: %v", err)
			}
			lines = append(lines, line)
		}
	}
	return lines
}

func TestTrafficJournalLine(t *testing.T) {
	info := testTrafficInfo(100, 900)
	end := time.Date(2026, 11, 23, 10, 5, 0, 0, time.UTC)
	line := newTrafficJournalLine("id-a", info, end)
	if line.ID != "id-a" || line.Host != "example.com" || line.Process != "Safari" {
		t.Fatalf("unexpected identity fields: %+v", line)
	}
	if line.Proxy != "Proxy" || line.Node != "Node-A" || line.Direct {
		t.Fatalf("unexpected chain fields: %+v", line)
	}
	if line.Rule != "RULE-SET" || line.RulePayload != "ads" {
		t.Fatalf("unexpected rule fields: %+v", line)
	}
	if line.Upload != 100 || line.Download != 900 {
		t.Fatalf("unexpected totals: %+v", line)
	}
	if line.Start != info.Start.UnixMilli() || line.End != end.UnixMilli() {
		t.Fatalf("unexpected times: %+v", line)
	}

	direct := testTrafficInfo(1, 2)
	direct.Chain = constant.Chain{"DIRECT"}
	directLine := newTrafficJournalLine("id-b", direct, end)
	if !directLine.Direct || directLine.Proxy != "DIRECT" || directLine.Node != "DIRECT" {
		t.Fatalf("unexpected direct fields: %+v", directLine)
	}

	bare := testTrafficInfo(0, 0)
	bare.Metadata = nil
	bare.Chain = nil
	bareLine := newTrafficJournalLine("id-c", bare, end)
	if bareLine.Host != "" || bareLine.Process != "" || bareLine.Proxy != "" || bareLine.Node != "" {
		t.Fatalf("unexpected bare fields: %+v", bareLine)
	}
}

func TestTrafficJournalPollJournalsClosed(t *testing.T) {
	dir := t.TempDir()
	journal := newTrafficJournal()
	journal.setup(dir)
	journal.track("a", testTrafficInfo(10, 20))
	journal.track("b", testTrafficInfo(30, 40))

	journal.poll()

	lines := readJournalLines(t, filepath.Join(dir, trafficJournalDirectoryName))
	if len(lines) != 2 {
		t.Fatalf("expected 2 journal lines, got %d", len(lines))
	}
	byID := map[string]trafficJournalLine{}
	for _, line := range lines {
		byID[line.ID] = line
	}
	if byID["a"].Upload != 10 || byID["a"].Download != 20 {
		t.Fatalf("unexpected totals for a: %+v", byID["a"])
	}
	if byID["b"].Upload != 30 || byID["b"].Download != 40 {
		t.Fatalf("unexpected totals for b: %+v", byID["b"])
	}

	journal.poll()
	if lines := readJournalLines(t, filepath.Join(dir, trafficJournalDirectoryName)); len(lines) != 2 {
		t.Fatalf("second poll re-journaled closed connections: %d lines", len(lines))
	}
}

func TestTrafficJournalFlushJournalsOpen(t *testing.T) {
	dir := t.TempDir()
	journal := newTrafficJournal()
	journal.setup(dir)
	journal.track("a", testTrafficInfo(7, 8))

	journal.flush()

	lines := readJournalLines(t, filepath.Join(dir, trafficJournalDirectoryName))
	if len(lines) != 1 || lines[0].ID != "a" || lines[0].Upload != 7 {
		t.Fatalf("unexpected flushed lines: %+v", lines)
	}
	journal.poll()
	if lines := readJournalLines(t, filepath.Join(dir, trafficJournalDirectoryName)); len(lines) != 1 {
		t.Fatalf("flush left the connection open for the poller: %d lines", len(lines))
	}
}

func TestTrafficJournalDisabledWithoutHome(t *testing.T) {
	dir := t.TempDir()
	journal := newTrafficJournal()
	journal.track("a", testTrafficInfo(1, 2))
	journal.poll()
	journal.flush()
	if entries, err := os.ReadDir(dir); err != nil || len(entries) != 0 {
		t.Fatalf("disabled journal wrote files: %v, %v", entries, err)
	}
}

func TestTrafficJournalPrune(t *testing.T) {
	dir := t.TempDir()
	journal := newTrafficJournal()
	journal.setup(dir)
	journalDir := filepath.Join(dir, trafficJournalDirectoryName)
	if err := os.MkdirAll(journalDir, 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	oldName := now.Add(-4 * 24 * time.Hour).Format("2006-01-02-15") + trafficJournalFileSuffix
	keepName := now.Add(-2 * 24 * time.Hour).Format("2006-01-02-15") + trafficJournalFileSuffix
	for _, name := range []string{oldName, keepName, "notes.txt"} {
		if err := os.WriteFile(filepath.Join(journalDir, name), []byte("x\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	journal.prune(journalDir, now)

	if _, err := os.Stat(filepath.Join(journalDir, oldName)); !os.IsNotExist(err) {
		t.Fatalf("old journal file was not pruned: %v", err)
	}
	for _, name := range []string{keepName, "notes.txt"} {
		if _, err := os.Stat(filepath.Join(journalDir, name)); err != nil {
			t.Fatalf("prune removed %s: %v", name, err)
		}
	}
}
