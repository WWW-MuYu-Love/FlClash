//go:build with_low_memory

package main

import "runtime/debug"

// The Network Extension runs under jetsam's low-memory limit; the
// low-memory archive caps the Go heap so the extension is not killed
// while the app's archive runs uncapped.
const lowMemoryLimit = 32 * 1024 * 1024

func init() {
	debug.SetMemoryLimit(lowMemoryLimit)
}
