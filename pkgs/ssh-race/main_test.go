package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"io"
	"net"
	"os"
	"os/exec"
	"reflect"
	"testing"
	"time"
)

func TestBuildCandidatesBareHost(t *testing.T) {
	got := buildCandidates("test", []string{"dn42", "dora.im", "ts", "et"}, true)
	want := []string{"test.dn42", "test.dora.im", "test.ts", "test.et", "test"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestResolveCLI(t *testing.T) {
	if os.Getenv("SSH_RACE_TEST_CHILD") == "1" {
		flag.CommandLine = flag.NewFlagSet("ssh-race", flag.ExitOnError)
		os.Args = append([]string{"ssh-race", "--resolve", "-4"}, os.Args[len(os.Args)-2:]...)
		main()
		return
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	closed := make(chan error, 1)
	go func() {
		conn, err := listener.Accept()
		if err != nil {
			closed <- err
			return
		}
		defer conn.Close()
		_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		var b [1]byte
		_, err = conn.Read(b[:])
		closed <- err
	}()
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestResolveCLI$", "--", "127.0.0.1", port)
	cmd.Env = append(os.Environ(), "SSH_RACE_TEST_CHILD=1")
	// An open pipe with no data proves resolve does not wait for stdin.
	input, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer input.Close()
	defer writer.Close()
	cmd.Stdin = input
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("resolve: %v, stderr: %s", err, &stderr)
	}
	var result struct {
		Host    string `json:"host"`
		Address string `json:"address"`
	}
	if err := json.NewDecoder(&stdout).Decode(&result); err != nil {
		t.Fatal(err)
	}
	if result.Host != "127.0.0.1" || result.Address != "127.0.0.1" {
		t.Fatalf("unexpected endpoint: %+v", result)
	}
	if err := <-closed; err != io.EOF {
		t.Fatalf("resolve socket not closed without payload: %v", err)
	}
}

func TestDialRaceClosesLosers(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	const attempts = 8
	closed := make(chan error, attempts)
	go func() {
		for range attempts {
			conn, err := listener.Accept()
			if err != nil {
				closed <- err
				return
			}
			go func() {
				defer conn.Close()
				_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
				var b [1]byte
				_, err := conn.Read(b[:])
				closed <- err
			}()
		}
	}()
	_, port, _ := net.SplitHostPort(listener.Addr().String())
	candidates := make([]string, attempts)
	for i := range candidates {
		candidates[i] = "127.0.0.1"
	}
	conn, _, err := dialRace("tcp4", candidates, port, time.Second, time.Second, 0)
	if err != nil {
		t.Fatal(err)
	}
	_ = conn.Close()
	for range attempts {
		if err := <-closed; err != io.EOF {
			t.Fatalf("race socket was not closed: %v", err)
		}
	}
}

func TestDialRaceFailure(t *testing.T) {
	for _, candidates := range [][]string{nil, {"not a hostname"}} {
		if conn, _, err := dialRace("tcp4", candidates, "22", time.Millisecond, time.Millisecond, 0); err == nil || conn != nil {
			t.Fatalf("expected failed race, got %v, %v", conn, err)
		}
	}
}

func TestBuildCandidatesFullyQualifiedHost(t *testing.T) {
	got := buildCandidates("github.com", []string{"dn42", "dora.im", "ts", "et"}, true)
	want := []string{"github.com"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("buildCandidates() = %#v, want %#v", got, want)
	}
}

func TestSplitList(t *testing.T) {
	got := splitList("dn42, dora.im ts et\n")
	want := []string{"dn42", "dora.im", "ts", "et"}
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
