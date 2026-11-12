package core

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func resetRedirectStderrDone() {
	redirectStderrMu.Lock()
	redirectStderrDone = false
	redirectStderrMu.Unlock()
}

func TestRedirectStderr(t *testing.T) {
	resetRedirectStderrDone()
	defer resetRedirectStderrDone()
	homeDir := t.TempDir()
	saved, err := syscall.Dup(2)
	if err != nil {
		t.Fatalf("dup stderr: %v", err)
	}
	defer func() {
		_ = syscall.Dup2(saved, 2)
		_ = syscall.Close(saved)
	}()
	redirectStderrToPanicLog(homeDir)
	if _, err := fmt.Fprintln(os.Stderr, "panic: test boom"); err != nil {
		t.Fatalf("write stderr: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(homeDir, panicLogDirName, panicLogFileName))
	if err != nil {
		t.Fatalf("read panic log: %v", err)
	}
	if string(data) != "panic: test boom\n" {
		t.Fatalf("unexpected panic log: %q", data)
	}
}

func TestRedirectStderrRotatesOversizedLog(t *testing.T) {
	homeDir := t.TempDir()
	path := filepath.Join(homeDir, panicLogDirName, panicLogFileName)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	oldContent := strings.Repeat("x", maxPanicLogSize+1)
	if err := os.WriteFile(path, []byte(oldContent), 0o644); err != nil {
		t.Fatal(err)
	}
	saved, err := syscall.Dup(2)
	if err != nil {
		t.Fatalf("dup stderr: %v", err)
	}
	defer func() {
		_ = syscall.Dup2(saved, 2)
		_ = syscall.Close(saved)
	}()
	redirectStderr(path)
	if _, err := fmt.Fprintln(os.Stderr, "panic: after rotation"); err != nil {
		t.Fatalf("write stderr: %v", err)
	}
	rotated, err := os.ReadFile(filepath.Join(homeDir, panicLogDirName, panicLogOldName))
	if err != nil {
		t.Fatalf("read rotated log: %v", err)
	}
	if string(rotated) != oldContent {
		t.Fatalf("rotated log lost content: %d bytes", len(rotated))
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read panic log: %v", err)
	}
	if string(data) != "panic: after rotation\n" {
		t.Fatalf("unexpected panic log: %q", data)
	}
}

func TestRedirectStderrToPanicLogEmptyHome(t *testing.T) {
	if err := redirectStderrToPanicLog(""); err == nil {
		t.Fatal("empty home directory must fail instead of building a relative path")
	}
}

func TestRedirectStderrReturnsError(t *testing.T) {
	badHome := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(badHome, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := redirectStderr(filepath.Join(badHome, panicLogDirName, panicLogFileName)); err == nil {
		t.Fatal("redirect under a regular file must fail")
	}
}

func TestRedirectStderrToPanicLogRetriesAfterFailure(t *testing.T) {
	resetRedirectStderrDone()
	defer resetRedirectStderrDone()
	badHome := filepath.Join(t.TempDir(), "not-a-dir")
	if err := os.WriteFile(badHome, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := redirectStderrToPanicLog(badHome); err == nil {
		t.Fatal("first redirect with an unusable home must fail")
	}
	homeDir := t.TempDir()
	saved, err := syscall.Dup(2)
	if err != nil {
		t.Fatalf("dup stderr: %v", err)
	}
	defer func() {
		_ = syscall.Dup2(saved, 2)
		_ = syscall.Close(saved)
	}()
	if err := redirectStderrToPanicLog(homeDir); err != nil {
		t.Fatalf("retry with a usable home must succeed: %v", err)
	}
	if _, err := fmt.Fprintln(os.Stderr, "panic: after retry"); err != nil {
		t.Fatalf("write stderr: %v", err)
	}
	data, err := os.ReadFile(filepath.Join(homeDir, panicLogDirName, panicLogFileName))
	if err != nil {
		t.Fatalf("read panic log: %v", err)
	}
	if string(data) != "panic: after retry\n" {
		t.Fatalf("unexpected panic log: %q", data)
	}
}
