//go:build linux

package core

import "syscall"

func saveStderr() (int, error) {
	return syscall.Dup(2)
}

func restoreStderr(saved int) error {
	err := syscall.Dup3(saved, 2, 0)
	_ = syscall.Close(saved)
	return err
}
