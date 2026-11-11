package mitm

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"math/big"
	"time"
)

// Certificate is the CA description the app reads (MitmCertificate).
type Certificate struct {
	PEM         string    `json:"pem"`
	Fingerprint string    `json:"fingerprint"`
	Subject     string    `json:"subject"`
	NotBefore   time.Time `json:"not-before"`
	NotAfter    time.Time `json:"not-after"`
}

// DescribeCertificate renders a parsed CA certificate for the app.
func DescribeCertificate(leaf *x509.Certificate) *Certificate {
	sum := sha256.Sum256(leaf.Raw)
	return &Certificate{
		PEM:         string(pemEncodeCert(leaf.Raw)),
		Fingerprint: hex.EncodeToString(sum[:]),
		Subject:     leaf.Subject.CommonName,
		NotBefore:   leaf.NotBefore,
		NotAfter:    leaf.NotAfter,
	}
}

// GenerateCA creates a fresh CA key and self-signed certificate. The CA is
// named FlClash CA so the system trust store shows a recognizable name. RSA
// is used because the MITM engine loads the CA with utls.LoadX509KeyPair,
// which requires an RSA key.
func GenerateCA() (crypto.Signer, *x509.Certificate, error) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, nil, err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: "FlClash CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		IsCA:                  true,
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		return nil, nil, err
	}
	leaf, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, nil, err
	}
	return key, leaf, nil
}

// pemEncodeCert renders DER bytes as a PEM certificate block.
func pemEncodeCert(der []byte) []byte {
	return pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
}

// pemEncodeKey renders a private key as a PEM block. PKCS#8 ("PRIVATE KEY")
// is used because the MITM engine loads the CA with utls.LoadX509KeyPair,
// which does not accept the SEC 1 "EC PRIVATE KEY" form.
func pemEncodeKey(key crypto.Signer) ([]byte, error) {
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, fmt.Errorf("marshal CA key: %w", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), nil
}

// IssueLeaf signs a leaf certificate for host with the engine's CA and
// returns it as PEM. The leaf mirrors what the MITM engine issues per
// connection; the app uses it to verify a trust store accepted the CA.
func (e *Engine) IssueLeaf(host string) (string, error) {
	e.mu.RLock()
	ca := e.ca
	leaf := e.caCert
	e.mu.RUnlock()
	if ca == nil || leaf == nil {
		return "", fmt.Errorf("no CA certificate")
	}
	signer, ok := ca.PrivateKey.(crypto.Signer)
	if !ok {
		return "", fmt.Errorf("CA key is not a signer")
	}
	return IssueLeaf(signer, leaf, host)
}

// IssueLeaf signs a leaf certificate for host with the given CA.
func IssueLeaf(ca crypto.Signer, caCert *x509.Certificate, host string) (string, error) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return "", err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: host},
		DNSNames:              []string{host},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(1, 0, 0),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, caCert, key.Public(), ca)
	if err != nil {
		return "", err
	}
	return string(pemEncodeCert(der)), nil
}
