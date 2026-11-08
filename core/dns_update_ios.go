//go:build ios

package core

// On iOS the tunnel provider owns DNS (NEDNSSettings); mihomo's
// UpdateSystemDNS and FlushCacheWithDefaultResolver are Android-only,
// so there is nothing to apply here.
func applySystemDNS(addr []string) {}
