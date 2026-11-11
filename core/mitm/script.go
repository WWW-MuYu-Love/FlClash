package mitm

// ScriptOutput is the mitm.runScript answer (MitmScriptOutput). Script
// execution needs a JS engine, which is not integrated yet; until then the
// handler reports that instead of a result.
type ScriptOutput struct {
	Logs   []string `json:"logs"`
	Result string   `json:"result"`
	Error  string   `json:"error"`
}
