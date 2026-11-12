package core

import (
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

var redirectStderrOnce sync.Once

func redirectStderrToPanicLog(homeDir string) {
	redirectStderrOnce.Do(func() {
		// A single goroutine's stack rarely explains a background panic.
		debug.SetTraceback("all")
		redirectStderr(filepath.Join(homeDir, panicLogDirName, panicLogFileName))
	})
}

func redirectStderr(path string) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	if st, err := os.Stat(path); err == nil && st.Size() > maxPanicLogSize {
		_ = os.Rename(path, filepath.Join(filepath.Dir(path), panicLogOldName))
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	// Held open for the life of the process: closing it would close fd 2.
	_ = syscall.Dup2(int(file.Fd()), 2)
}
