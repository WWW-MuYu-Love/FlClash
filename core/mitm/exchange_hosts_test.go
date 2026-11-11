package mitm

import (
	"reflect"
	"testing"
)

func TestExchangeHost(t *testing.T) {
	cases := []struct {
		url  string
		want string
	}{
		{"https://movies.muyu.love/play", "movies.muyu.love"},
		{"https://Movies.MuYu.Love:443/play", "movies.muyu.love"},
		{"http://127.0.0.1:8080/x", "127.0.0.1"},
		{"", ""},
		{"://bad", ""},
	}
	for _, c := range cases {
		if got := exchangeHost(c.url); got != c.want {
			t.Errorf("exchangeHost(%q) = %q, want %q", c.url, got, c.want)
		}
	}
}

func TestNormalizeHost(t *testing.T) {
	cases := []struct {
		host string
		want string
	}{
		{"movies.muyu.love", "movies.muyu.love"},
		{"Movies.MuYu.Love", "movies.muyu.love"},
		{"movies.muyu.love:443", "movies.muyu.love"},
		{"  cdn.muyu.love  ", "cdn.muyu.love"},
	}
	for _, c := range cases {
		if got := normalizeHost(c.host); got != c.want {
			t.Errorf("normalizeHost(%q) = %q, want %q", c.host, got, c.want)
		}
	}
}

func TestExchangeStoreHosts(t *testing.T) {
	s := NewExchangeStore(10)
	s.add(&Exchange{ID: 1, URL: "https://movies.muyu.love/play", Connection: "1"})
	s.add(&Exchange{ID: 2, URL: "https://cdn.muyu.love/a.js", Connection: "2"})
	s.add(&Exchange{ID: 3, URL: "https://Movies.Muyu.Love/other", Connection: "3"})
	s.add(&Exchange{ID: 4, URL: "https://movies.muyu.love:443/again", Connection: "4"})
	if got := s.Hosts(); !reflect.DeepEqual(got, []string{"cdn.muyu.love", "movies.muyu.love"}) {
		t.Errorf("Hosts() = %v, want [cdn.muyu.love movies.muyu.love]", got)
	}
}

func TestExchangeStoreListByHost(t *testing.T) {
	s := NewExchangeStore(10)
	s.add(&Exchange{ID: 1, URL: "https://movies.muyu.love/play", Connection: "1"})
	s.add(&Exchange{ID: 2, URL: "https://cdn.muyu.love/a.js", Connection: "2"})
	s.add(&Exchange{ID: 3, URL: "https://movies.muyu.love/other", Connection: "3"})
	// The query host is normalized the same way as the stored URLs.
	list := s.ListByHost("Movies.Muyu.Love:443", true)
	if len(list.Exchanges) != 2 {
		t.Fatalf("ListByHost() = %d exchanges, want 2", len(list.Exchanges))
	}
	if list.Exchanges[0].ID != 1 || list.Exchanges[1].ID != 3 {
		t.Errorf("ListByHost() ids = %v, want [1 3]", []int{list.Exchanges[0].ID, list.Exchanges[1].ID})
	}
	if !list.Capturing {
		t.Errorf("ListByHost() capturing = false, want true")
	}
	// A host with no exchanges lists none, and never reports closed: a
	// host outlives any one connection.
	empty := s.ListByHost("other.example", true)
	if len(empty.Exchanges) != 0 || empty.Closed {
		t.Errorf("ListByHost(other) = %+v, want no exchanges and closed=false", empty)
	}
}
