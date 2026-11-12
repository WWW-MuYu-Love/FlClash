//go:build !linux && !windows

package core

import "syscall"

func saveStderr() (int, error) {
	return syscall.Dup(2)
}

func restoreStderr(saved int) error {
	err := syscall.Dup2(saved, 2)
	_ = syscall.Close(saved)
	return err
}
