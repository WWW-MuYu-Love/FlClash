package core

import (
	"errors"

	"core/mitm"
)

// handleMitmCertificate returns the current CA, or nil when none exists yet.
func handleMitmCertificate() *mitm.Certificate {
	if err := mitm.Default().Init(); err != nil {
		return nil
	}
	return mitm.Default().Certificate()
}

// handleGenerateMitmCertificate replaces the CA with a fresh one.
func handleGenerateMitmCertificate() (*mitm.Certificate, error) {
	if err := mitm.Default().Init(); err != nil {
		return nil, err
	}
	return mitm.Default().GenerateCertificate()
}

// handleValidateMitm checks the merged module rules and returns per-list
// issues, keyed by list key then 1-based line number.
func handleValidateMitm(rules mitm.Config) mitm.RuleIssues {
	return mitm.ValidateRules(&rules)
}

// handleIssueMitmCertificate signs a leaf for host with the current CA.
func handleIssueMitmCertificate(params struct {
	Host string `json:"host"`
}) (string, error) {
	if err := mitm.Default().Init(); err != nil {
		return "", err
	}
	if params.Host == "" {
		return "", errors.New("missing host")
	}
	return mitm.Default().IssueLeaf(params.Host)
}

// handleMitmExchanges lists the recorded exchanges for a connection.
func handleMitmExchanges(params struct {
	ID string `json:"id"`
}) *mitm.ExchangeList {
	return mitm.Default().Exchanges(params.ID)
}

// handleMitmExchange returns one recorded exchange, or nil.
func handleMitmExchange(params struct {
	ID int `json:"id"`
}) *mitm.Exchange {
	return mitm.Default().Exchange(params.ID)
}

// handleMitmBody returns one side of a recorded exchange, or nil.
func handleMitmBody(params struct {
	ID       int  `json:"id"`
	Response bool `json:"response"`
}) *mitm.Body {
	return mitm.Default().Body(params.ID, params.Response)
}

// handleRunMitmScript has no JS engine yet; module scripts are a later stage.
func handleRunMitmScript(params struct {
	Name string `json:"name"`
}) (mitm.ScriptOutput, error) {
	return mitm.ScriptOutput{}, errors.New("script execution is not supported yet: the JS engine is not integrated")
}
