package mitm

import (
	"fmt"
	"net/url"
	"strings"
)

// matchHostnameList reports whether host is covered by the hostname lines.
// Lines use Surge syntax: a leading '-' excludes, '*' matches a whole label,
// and the first match decides. An empty list matches nothing.
func matchHostnameList(lines []string, host string) bool {
	host = strings.ToLower(strings.TrimSpace(host))
	// Strip a port when one is present.
	if h, _, err := splitHostPort(host); err == nil {
		host = h
	}
	for _, line := range lines {
		line = strings.ToLower(strings.TrimSpace(line))
		if line == "" {
			continue
		}
		negate := strings.HasPrefix(line, "-")
		pattern := strings.TrimPrefix(line, "-")
		if matchHostnamePattern(pattern, host) {
			return !negate
		}
	}
	return false
}

// matchHostnamePattern matches one hostname line against a host. '*' matches
// exactly one label; a leading "*." matches any number of leading labels.
func matchHostnamePattern(pattern, host string) bool {
	if pattern == "*" {
		return true
	}
	if strings.HasPrefix(pattern, "*.") {
		suffix := pattern[1:] // ".example.com"
		return host == pattern[2:] || strings.HasSuffix(host, suffix)
	}
	pLabels := strings.Split(pattern, ".")
	hLabels := strings.Split(host, ".")
	if len(pLabels) != len(hLabels) {
		return false
	}
	for i := range pLabels {
		if pLabels[i] == "*" {
			continue
		}
		if pLabels[i] != hLabels[i] {
			return false
		}
	}
	return true
}

// splitHostPort splits host:port, tolerating a bare hostname.
func splitHostPort(hostport string) (string, string, error) {
	if i := strings.LastIndex(hostport, ":"); i >= 0 {
		return hostport[:i], hostport[i+1:], nil
	}
	return hostport, "", fmt.Errorf("no port")
}

// RuleIssues maps a list key to line-numbered problems, as mitm.validate
// answers it.
type RuleIssues map[string]map[int]string

// ValidateRules checks the merged module rules and returns per-list issues.
// A line is an issue when it is blank, has no operator where one is required,
// or names a host/URL the core cannot parse.
func ValidateRules(cfg *Config) RuleIssues {
	issues := RuleIssues{}
	add := func(list, line string, num int, err error) {
		if err == nil {
			return
		}
		if issues[list] == nil {
			issues[list] = map[int]string{}
		}
		issues[list][num] = err.Error()
	}
	for i, line := range cfg.Hostname {
		add("hostname", line, i+1, validateHostnameLine(line))
	}
	for i, line := range cfg.URLRewrite {
		add("url-rewrite", line, i+1, validateRewriteLine(line, "url-rewrite"))
	}
	for i, line := range cfg.HeaderRewrite {
		add("header-rewrite", line, i+1, validateRewriteLine(line, "header-rewrite"))
	}
	for i, line := range cfg.BodyRewrite {
		add("body-rewrite", line, i+1, validateRewriteLine(line, "body-rewrite"))
	}
	for i, line := range cfg.MapLocal {
		add("map-local", line, i+1, validateRewriteLine(line, "map-local"))
	}
	for i, line := range cfg.Script {
		add("script", line, i+1, validateRewriteLine(line, "script"))
	}
	return issues
}

func validateHostnameLine(line string) error {
	line = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "-"))
	if line == "" {
		return fmt.Errorf("empty hostname")
	}
	if strings.ContainsAny(line, " /?#") {
		return fmt.Errorf("hostname must not contain %q", line)
	}
	return nil
}

// validateRewriteLine checks a rewrite line has the shape
// "<pattern> <operator> <replacement>".
func validateRewriteLine(line, list string) error {
	parts := strings.Fields(strings.TrimSpace(line))
	if len(parts) == 0 {
		return fmt.Errorf("empty line")
	}
	if len(parts) < 2 {
		return fmt.Errorf("missing operator and replacement")
	}
	if _, err := url.Parse(parts[0]); err != nil {
		return fmt.Errorf("bad pattern: %v", err)
	}
	return nil
}
