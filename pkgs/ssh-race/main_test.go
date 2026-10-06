package main

import (
	"reflect"
	"testing"
	"time"
)

func TestBuildCandidatesBareHost(t *testing.T) {
	got := buildCandidates("test", []string{"dn42", "dora.im", "mag", "et"}, true)
	want := []string{"test.dn42", "test.dora.im", "test.mag", "test.et", "test"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestBuildCandidatesFullyQualifiedHost(t *testing.T) {
	got := buildCandidates("github.com", []string{"dn42", "dora.im", "mag", "et"}, true)
	want := []string{"github.com"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestSplitList(t *testing.T) {
	got := splitList("dn42, dora.im mag et\n")
	want := []string{"dn42", "dora.im", "mag", "et"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("splitList() = %#v, want %#v", got, want)
	}
}

func TestIsDN42(t *testing.T) {
	cases := []struct {
		host string
		want bool
	}{
		{"sjc0.dn42", true},
		{"sjc0.tippy.dn42", true},
		{"172.20.232.1", true},
		{"172.22.1.1", true},
		{"fd53:90fd:4bb6::1", true},
		{"sjc0.dora.im", false},
		{"1.1.1.1", false},
		{"10.0.0.1", false},
	}
	for _, c := range cases {
		if got := isDN42(c.host); got != c.want {
			t.Errorf("isDN42(%q) = %v, want %v", c.host, got, c.want)
		}
	}
}

func TestComputeScore(t *testing.T) {
	bonus := 15 * time.Millisecond
	dn42Score := computeScore("sjc0.dn42", 50*time.Millisecond, bonus)
	publicScore := computeScore("sjc0.dora.im", 45*time.Millisecond, bonus)

	// DN42: 50ms - 15ms = 35. Public: 45ms. DN42 should win (lower score)!
	if dn42Score >= publicScore {
		t.Errorf("expected dn42Score (%f) < publicScore (%f)", dn42Score, publicScore)
	}
}
