//go:build linux

package core

import (
	"os"
	"syscall"
)

// arm64 kernels have no dup2, so Go's syscall package has no Dup2 there
// (and therefore none on Android either); Dup3 with no flags is the
// same redirect.
func dupFileToStderr(file *os.File) error {
	return syscall.Dup3(int(file.Fd()), 2, 0)
}
