package mitm

import "net"

// networkInfo builds the $network object: the first usable v4/v6 address.
// The SSID is null, not guessed: it lives in the Swift extension and never reaches the Go engine.
func networkInfo() map[string]any {
	v4, v6 := primaryAddresses()
	return map[string]any{
		"v4":   map[string]any{"primaryAddress": v4},
		"v6":   map[string]any{"primaryAddress": v6},
		"wifi": map[string]any{"ssid": nil},
	}
}

func primaryAddresses() (v4, v6 string) {
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ip, _, err := net.ParseCIDR(addr.String())
			if err != nil || ip == nil {
				continue
			}
			if ip4 := ip.To4(); ip4 != nil {
				if v4 == "" && ip.IsGlobalUnicast() && !ip.IsLinkLocalUnicast() {
					v4 = ip4.String()
				}
			} else if v6 == "" && ip.IsGlobalUnicast() && !ip.IsLinkLocalUnicast() {
				v6 = ip.String()
			}
		}
	}
	return v4, v6
}
