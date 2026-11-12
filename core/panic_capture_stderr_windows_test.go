//go:build windows

package core

import (
	"os"
	"syscall"
)

type savedStderr struct {
	handle syscall.Handle
	file   *os.File
}

func saveStderr() (savedStderr, error) {
	handle, err := syscall.GetStdHandle(syscall.STD_ERROR_HANDLE)
	return savedStderr{handle: handle, file: os.Stderr}, err
}

func restoreStderr(saved savedStderr) error {
	os.Stderr = saved.file
	return setStdHandle(saved.handle)
}
