package core

import (
	"errors"
	"os"
	"path/filepath"
	"runtime/debug"
	"sync"
	"syscall"
)

// A Go runtime panic in a background goroutine exits the process with
// exit(2) and no signal, so iOS records neither a crash log nor a
// JetsamEvent. The runtime writes the trace straight to fd 2, so the core
// redirects fd 2 at init to a file under the shared home directory; the
// log export appends it. Names mirror lib/common/path.dart.
const (
	panicLogDirName  = "logs"
	panicLogFileName = "panic.log"
	panicLogOldName  = "panic.log.old"
	maxPanicLogSize  = 512 << 10
)

// Only a successful redirect latches, so a failed init retries next time.
var (
	redirectStderrMu   sync.Mutex
	redirectStderrDone bool
)

func redirectStderrToPanicLog(homeDir string) error {
	if homeDir == "" {
		err := errors.New("panic log unavailable: empty home directory")
		logError("redirect stderr to panic log failed: %v", err)
		return err
	}
	redirectStderrMu.Lock()
	defer redirectStderrMu.Unlock()
	if redirectStderrDone {
		return nil
	}
	debug.SetTraceback("all")
	if err := redirectStderr(filepath.Join(homeDir, panicLogDirName, panicLogFileName)); err != nil {
		logError("redirect stderr to panic log failed: %v", err)
		return err
	}
	redirectStderrDone = true
	return nil
}

func redirectStderr(path string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if st, err := os.Stat(path); err == nil && st.Size() > maxPanicLogSize {
		_ = os.Rename(path, filepath.Join(filepath.Dir(path), panicLogOldName))
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	// Held open for the life of the process: closing it would close fd 2.
	if err := syscall.Dup2(int(file.Fd()), 2); err != nil {
		_ = file.Close()
		return err
	}
	return nil
}
