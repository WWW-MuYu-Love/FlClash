package mitm

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// resourcesDirName is the home-relative directory for module files.
const resourcesDirName = "resources"

const maxResourceSize = 16 << 20

func (e *Engine) resolveResource(name string) (string, error) {
	dir := filepath.Join(e.HomeDir(), resourcesDirName)
	cleaned := filepath.Clean(name)
	if filepath.IsAbs(cleaned) {
		if cleaned != dir && !strings.HasPrefix(cleaned, dir+string(os.PathSeparator)) {
			return "", fmt.Errorf("resource %q is outside the resources directory", name)
		}
		return cleaned, nil
	}
	joined := filepath.Join(dir, cleaned)
	if !strings.HasPrefix(joined, dir+string(os.PathSeparator)) {
		return "", fmt.Errorf("resource %q is outside the resources directory", name)
	}
	return joined, nil
}

func (e *Engine) readResource(name string) ([]byte, error) {
	path, err := e.resolveResource(name)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("resource %q: %w", name, err)
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxResourceSize+1))
	if err != nil {
		return nil, fmt.Errorf("resource %q: %w", name, err)
	}
	if len(data) > maxResourceSize {
		return nil, fmt.Errorf("resource %q exceeds %d bytes", name, maxResourceSize)
	}
	return data, nil
}
