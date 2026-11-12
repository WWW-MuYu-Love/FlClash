//go:build !linux && !windows

package core

import (
	"os"
	"syscall"
)

func dupFileToStderr(file *os.File) error {
	return syscall.Dup2(int(file.Fd()), 2)
}
