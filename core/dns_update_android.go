//go:build android

package core

import "github.com/metacubex/mihomo/dns"

func applySystemDNS(addr []string) {
	dns.UpdateSystemDNS(addr)
	dns.FlushCacheWithDefaultResolver()
}
