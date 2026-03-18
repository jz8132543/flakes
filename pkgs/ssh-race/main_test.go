package main

import (
	"reflect"
	"testing"
)

func TestBuildCandidatesBareHost(t *testing.T) {
	got := buildCandidates("nue0", []string{"et", "mag", "dora.im"}, true)
	want := []string{"nue0.et", "nue0.mag", "nue0.dora.im", "nue0"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestBuildCandidatesFullyQualifiedHost(t *testing.T) {
	got := buildCandidates("github.com", []string{"et", "mag", "dora.im"}, true)
	want := []string{"github.com"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestSplitList(t *testing.T) {
	got := splitList("et, mag dora.im\n")
	want := []string{"et", "mag", "dora.im"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("splitList() = %#v, want %#v", got, want)
	}
}
