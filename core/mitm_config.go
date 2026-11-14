package core

import (
	"os"

	"core/mitm"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
	"go.yaml.in/yaml/v3"
)

// mitmSection is the shape of the `mitm` key in the running config file.
type mitmSection struct {
	Mitm *mitm.Config `yaml:"mitm"`
}

// applyMitmConfig reads the `mitm` section from the running config file and
// applies it to the MITM engine, together with the mixed port the engine
// dials as its SOCKS5 upstream. A missing section disables MITM. When MITM
// is enabled the engine is initialized so its CA and handler are ready
// before the tunnel starts diverting connections.
func applyMitmConfig(cfg *config.Config) {
	mitm.Default().SetMixedPort(cfg.General.MixedPort)
	buf, err := os.ReadFile(runningConfigPath())
	if err != nil {
		mitm.Default().SetConfig(nil)
		log.Warnln("[MITM] no mitm section in config: cannot read config file: %v", err)
		return
	}
	var section mitmSection
	if err := yaml.Unmarshal(buf, &section); err != nil {
		mitm.Default().SetConfig(nil)
		log.Warnln("[MITM] no mitm section in config: cannot parse config file: %v", err)
		return
	}
	if section.Mitm == nil {
		mitm.Default().SetConfig(nil)
		log.Warnln("[MITM] no mitm section in config")
		return
	}
	mitm.Default().SetConfig(section.Mitm)
	log.Infoln(
		"[MITM] applied: enable=%v decrypt-tls=%v hostnames=%d",
		section.Mitm.Enable,
		section.Mitm.DecryptTLS,
		len(section.Mitm.Hostname),
	)
	if section.Mitm.Enable && section.Mitm.DecryptTLS {
		if err := mitm.Default().Init(); err != nil {
			log.Warnln("[MITM] init failed: %v", err)
		}
	}
}
