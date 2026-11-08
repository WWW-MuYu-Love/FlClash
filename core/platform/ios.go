//go:build ios

package platform

import "net"

// iOS runs inside the Network Extension, which already owns the tunnel, so
// no socket needs protecting and no per-connection owner exists to resolve.
func ShouldBlockConnection() bool {
	return false
}

func QuerySocketUidFromProcFs(source, target net.Addr) int {
	return -1
}
