package mitm

import (
	"testing"
)

func TestMatchHostnameList(t *testing.T) {
	cases := []struct {
		lines []string
		host  string
		want  bool
	}{
		{nil, "example.com", false},
		{[]string{"example.com"}, "example.com", true},
		{[]string{"example.com"}, "other.com", false},
		{[]string{"-example.com"}, "example.com", false},
		{[]string{"*.example.com"}, "a.example.com", true},
		{[]string{"*.example.com"}, "a.b.example.com", true},
		{[]string{"*.example.com"}, "example.com", true},
		{[]string{"*.example.com"}, "other.com", false},
		{[]string{"*"}, "anything.example", true},
		// First match decides: an exclusion ahead of an inclusion wins.
		{[]string{"-a.example.com", "*.example.com"}, "a.example.com", false},
		{[]string{"*.example.com", "-a.example.com"}, "a.example.com", true},
		{[]string{"EXAMPLE.COM"}, "example.com", true},
	}
	for _, c := range cases {
		if got := matchHostnameList(c.lines, c.host); got != c.want {
			t.Errorf("matchHostnameList(%v, %q) = %v, want %v", c.lines, c.host, got, c.want)
		}
	}
}

func TestGenerateCA(t *testing.T) {
	key, leaf, err := GenerateCA()
	if err != nil {
		t.Fatalf("GenerateCA: %v", err)
	}
	if key == nil || leaf == nil {
		t.Fatal("GenerateCA returned nil")
	}
	if !leaf.IsCA {
		t.Error("generated certificate is not a CA")
	}
	if leaf.Subject.CommonName != "FlClash CA" {
		t.Errorf("subject = %q, want FlClash CA", leaf.Subject.CommonName)
	}
	if cert := DescribeCertificate(leaf); cert == nil || cert.Fingerprint == "" || cert.PEM == "" {
		t.Error("DescribeCertificate returned an empty description")
	}
}

func TestIssueLeaf(t *testing.T) {
	key, leaf, err := GenerateCA()
	if err != nil {
		t.Fatalf("GenerateCA: %v", err)
	}
	pem, err := IssueLeaf(key, leaf, "example.com")
	if err != nil {
		t.Fatalf("IssueLeaf: %v", err)
	}
	if pem == "" {
		t.Error("IssueLeaf returned empty PEM")
	}
}

func TestValidateRules(t *testing.T) {
	cfg := &Config{
		Hostname:      []string{"example.com", ""},
		URLRewrite:    []string{"https://a.com https://b.com", "onlyone"},
		HeaderRewrite: []string{"https://a.com X-Test: 1"},
	}
	issues := ValidateRules(cfg)
	if len(issues["hostname"]) != 1 {
		t.Errorf("hostname issues = %v, want 1", issues["hostname"])
	}
	if len(issues["url-rewrite"]) != 1 {
		t.Errorf("url-rewrite issues = %v, want 1", issues["url-rewrite"])
	}
	if len(issues["header-rewrite"]) != 0 {
		t.Errorf("header-rewrite issues = %v, want 0", issues["header-rewrite"])
	}
}
