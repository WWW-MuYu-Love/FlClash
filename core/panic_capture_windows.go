//go:build windows

package core

import (
	"os"
	"syscall"
)

var procSetStdHandle = syscall.NewLazyDLL("kernel32.dll").NewProc("SetStdHandle")

const stdErrorHandle = ^uintptr(11)

// No dup2 on Windows: the runtime resolves STD_ERROR_HANDLE per write.
func dupFileToStderr(file *os.File) error {
	if err := setStdHandle(syscall.Handle(file.Fd())); err != nil {
		return err
	}
	os.Stderr = file
	return nil
}

func setStdHandle(handle syscall.Handle) error {
	r, _, err := procSetStdHandle.Call(stdErrorHandle, uintptr(handle))
	if r == 0 {
		return err
	}
	return nil
}
