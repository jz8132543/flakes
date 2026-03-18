package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

type dialResult struct {
	host string
	conn net.Conn
}

func main() {
	var domainsFlag string
	var timeout time.Duration
	var fallback bool

	flag.StringVar(&domainsFlag, "domains", getenv("SSH_RACE_DOMAINS", ""), "comma-separated suffixes to try for bare hostnames")
	flag.DurationVar(&timeout, "timeout", 3*time.Second, "dial timeout for each candidate")
	flag.BoolVar(&fallback, "fallback", true, "try the original host after suffix candidates")
	flag.Parse()

	if flag.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "usage: ssh-race [-domains et,mag,dora.im] [-timeout 3s] [-fallback=true] host port")
		os.Exit(2)
	}

	host := flag.Arg(0)
	port := flag.Arg(1)
	suffixes := splitList(domainsFlag)
	candidates := buildCandidates(host, suffixes, fallback)

	conn, chosen, err := dialRace(candidates, port, timeout)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(255)
	}
	defer conn.Close()

	fmt.Fprintf(os.Stderr, "ssh-race: selected %s\n", chosen)

	if err := pump(conn); err != nil && !errors.Is(err, net.ErrClosed) && !errors.Is(err, io.EOF) {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(255)
	}
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func splitList(value string) []string {
	if value == "" {
		return nil
	}
	fields := strings.FieldsFunc(value, func(r rune) bool {
		return r == ',' || r == ' ' || r == '\t' || r == '\n' || r == '\r'
	})
	out := make([]string, 0, len(fields))
	for _, field := range fields {
		field = strings.TrimSpace(field)
		if field != "" {
			out = append(out, field)
		}
	}
	return out
}

func buildCandidates(host string, suffixes []string, fallback bool) []string {
	if !isBareHostname(host) || len(suffixes) == 0 {
		return []string{host}
	}

	candidates := make([]string, 0, len(suffixes)+1)
	for _, suffix := range suffixes {
		candidates = append(candidates, host+"."+suffix)
	}
	if fallback {
		candidates = append(candidates, host)
	}
	return candidates
}

func isBareHostname(host string) bool {
	if host == "" {
		return false
	}
	if strings.ContainsAny(host, ":.") {
		return false
	}
	return net.ParseIP(host) == nil
}

func dialRace(candidates []string, port string, timeout time.Duration) (net.Conn, string, error) {
	if len(candidates) == 0 {
		return nil, "", fmt.Errorf("no candidates to try")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	dialer := &net.Dialer{Timeout: timeout}
	success := make(chan dialResult, 1)
	errs := make(chan error, len(candidates))

	var wg sync.WaitGroup
	wg.Add(len(candidates))
	for _, candidate := range candidates {
		candidate := candidate
		go func() {
			defer wg.Done()
			conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(candidate, port))
			if err != nil {
				select {
				case errs <- fmt.Errorf("%s: %w", candidate, err):
				default:
				}
				return
			}

			select {
			case success <- dialResult{host: candidate, conn: conn}:
				cancel()
			default:
				_ = conn.Close()
			}
		}()
	}

	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()

	for {
		select {
		case result := <-success:
			return result.conn, result.host, nil
		case <-done:
			select {
			case result := <-success:
				return result.conn, result.host, nil
			default:
			}
			close(errs)
			return nil, "", collectDialErrors(errs)
		}
	}
}

func collectDialErrors(errs <-chan error) error {
	parts := make([]string, 0)
	for err := range errs {
		if err != nil {
			parts = append(parts, err.Error())
		}
	}
	if len(parts) == 0 {
		return fmt.Errorf("all connection attempts failed")
	}
	return fmt.Errorf("all connection attempts failed:\n%s", strings.Join(parts, "\n"))
}

func pump(conn net.Conn) error {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		_, _ = io.Copy(conn, os.Stdin)
		if closer, ok := conn.(interface{ CloseWrite() error }); ok {
			_ = closer.CloseWrite()
		}
	}()

	go func() {
		defer wg.Done()
		_, _ = io.Copy(os.Stdout, conn)
		_ = conn.Close()
	}()

	wg.Wait()
	return nil
}
