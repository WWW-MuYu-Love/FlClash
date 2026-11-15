package mitm

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"

	"github.com/metacubex/mihomo/log"
)

// persistentStoreName is the file under <home>/mitm/ holding script data.
const persistentStoreName = "persistent_store.json"

// persistentStore is the $persistentStore/$prefs backing for module scripts:
// one JSON file, namespaced by script name the way Surge scopes its store.
// A write is atomic (temporary file plus rename) and the file is 0600; an
// empty path keeps everything in memory.
type persistentStore struct {
	mu   sync.Mutex
	path string
	data map[string]map[string]string
}

func newPersistentStore(path string) *persistentStore {
	s := &persistentStore{path: path, data: map[string]map[string]string{}}
	if path == "" {
		return s
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return s
	}
	var loaded map[string]map[string]string
	if err := json.Unmarshal(raw, &loaded); err != nil {
		log.Warnln("[MITM] persistent store is corrupt, starting empty")
		return s
	}
	if loaded != nil {
		s.data = loaded
	}
	return s
}

func (s *persistentStore) read(namespace, key string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if keys, ok := s.data[namespace]; ok {
		value, ok := keys[key]
		return value, ok
	}
	return "", false
}

func (s *persistentStore) write(namespace, key, value string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	keys := s.data[namespace]
	if keys == nil {
		keys = map[string]string{}
		s.data[namespace] = keys
	}
	keys[key] = value
	return s.saveLocked()
}

func (s *persistentStore) remove(namespace, key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if keys, ok := s.data[namespace]; ok {
		delete(keys, key)
		if len(keys) == 0 {
			delete(s.data, namespace)
		}
	}
	return s.saveLocked()
}

func (s *persistentStore) saveLocked() bool {
	if s.path == "" {
		return true
	}
	raw, err := json.Marshal(s.data)
	if err != nil {
		return false
	}
	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return false
	}
	tmp, err := os.CreateTemp(dir, ".persistent-store-*")
	if err != nil {
		return false
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(raw); err != nil {
		tmp.Close()
		return false
	}
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return false
	}
	if err := tmp.Close(); err != nil {
		return false
	}
	if err := os.Rename(tmpName, s.path); err != nil {
		return false
	}
	return true
}
