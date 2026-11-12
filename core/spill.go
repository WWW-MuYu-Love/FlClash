package core

import (
	"os"
	"path/filepath"
	"time"

	"github.com/metacubex/mihomo/constant"
)

// Android copies a reply into the Java heap three times and the desktop IPC
// frame stops at maxIPCFrameSize. The directory name is mirrored in Dart.
const (
	responseSpillThreshold = 1 << 20
	spilledResponseDirName = "responses"
	// spilledResponseMaxAge bounds the init-time sweep below: the host reads
	// a spilled response after the method returns, and the other core may
	// have spilled one of its own into the shared home directory moments
	// earlier, so only files older than this are safe to remove.
	spilledResponseMaxAge = 10 * time.Minute
)

var spillThreshold = responseSpillThreshold

func spilledResponseDir() string {
	return filepath.Join(constant.Path.HomeDir(), spilledResponseDirName)
}

// The host deletes each file as soon as it reads it, which a directory an
// elevated Core just made would refuse until the debounced reclaim.
func makeSpilledResponseDir() (string, error) {
	dir := spilledResponseDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	reclaimDirOwnership(dir)
	return dir, nil
}

func spillResponse(id string, data []byte) []byte {
	if len(data) <= spillThreshold {
		return data
	}
	path, err := writeSpilledResponse(data)
	if err != nil {
		logError("spill response %s: %v", id, err)
		return data
	}
	return encodeResponse(MethodResponse{ID: id, File: path})
}

func writeSpilledResponse(data []byte) (path string, err error) {
	dir, err := makeSpilledResponseDir()
	if err != nil {
		return "", err
	}
	file, err := os.CreateTemp(dir, "*.json")
	if err != nil {
		return "", err
	}
	path = file.Name()
	defer func() {
		if err != nil {
			_ = os.Remove(path)
		}
	}()
	// An elevated Core still answers a host running as the app user.
	if err := file.Chmod(0o644); err != nil {
		_ = file.Close()
		return "", err
	}
	if _, err := file.Write(data); err != nil {
		_ = file.Close()
		return "", err
	}
	if err := file.Close(); err != nil {
		return "", err
	}
	scheduleReclaimOwnership()
	return path, nil
}

func clearSpilledResponses() {
	entries, err := os.ReadDir(spilledResponseDir())
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-spilledResponseMaxAge)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil || info.ModTime().After(cutoff) {
			continue
		}
		_ = os.Remove(filepath.Join(spilledResponseDir(), entry.Name()))
	}
}
