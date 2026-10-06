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
	host     string
	conn     net.Conn
	rtt      time.Duration
	score    float64
}

func main() {
	var domainsFlag string
	var timeout time.Duration
	var window time.Duration
	var dn42Bonus time.Duration
	var fallback bool

	flag.StringVar(&domainsFlag, "domains", getenv("SSH_RACE_DOMAINS", ""), "comma-separated suffixes to try for bare hostnames")
	flag.DurationVar(&timeout, "timeout", 3*time.Second, "dial timeout for each candidate")
	flag.DurationVar(&window, "window", 25*time.Millisecond, "smart evaluation window after the first handshake")
	flag.DurationVar(&dn42Bonus, "dn42-bonus", 15*time.Millisecond, "latency preference bonus for DN42 internal network")
	flag.BoolVar(&fallback, "fallback", true, "try the original host after suffix candidates")
	flag.Parse()

	if flag.NArg() != 2 {
		fmt.Fprintln(os.Stderr, "usage: ssh-race [-domains dn42,dora.im,ts,et] [-timeout 3s] [-window 25ms] [-dn42-bonus 15ms] [-fallback=true] host port")
		os.Exit(2)
	}

	host := flag.Arg(0)
	port := flag.Arg(1)
	suffixes := splitList(domainsFlag)
	candidates := buildCandidates(host, suffixes, fallback)

	conn, chosen, err := dialRace(candidates, port, timeout, window, dn42Bonus)
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
	}
	for _, field := range fields {
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

func isDN42(host string) bool {
	h := strings.ToLower(host)
	if strings.HasSuffix(h, ".dn42") || h == "dn42" {
		return true
	}
	ip := net.ParseIP(host)
	if ip != nil {
		if ip4 := ip.To4(); ip4 != nil {
			// DN42 IPv4: 172.20.0.0/14 (172.20.0.0 - 172.23.255.255)
			if ip4[0] == 172 && ip4[1] >= 20 && ip4[1] <= 23 {
				return true
			}
		} else {
			// DN42 IPv6: fd00::/8
			if len(ip) >= 1 && ip[0] == 0xfd {
				return true
			}
		}
	}
	return false
}

func computeScore(host string, rtt time.Duration, dn42Bonus time.Duration) float64 {
	score := float64(rtt.Milliseconds())
	if isDN42(host) {
		score -= float64(dn42Bonus.Milliseconds())
	}
	return score
}

func dialRace(candidates []string, port string, timeout time.Duration, window time.Duration, dn42Bonus time.Duration) (net.Conn, string, error) {
	if len(candidates) == 0 {
		return nil, "", fmt.Errorf("no candidates to try")
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	dialer := &net.Dialer{Timeout: timeout}
	resChan := make(chan dialResult, len(candidates))
	errs := make(chan error, len(candidates))

	var wg sync.WaitGroup
	wg.Add(len(candidates))

	for _, candidate := range candidates {
		candidate := candidate
		go func() {
			defer wg.Done()
			start := time.Now()
			conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(candidate, port))
			elapsed := time.Since(start)

			if err != nil {
				select {
				case errs <- fmt.Errorf("%s: %w", candidate, err):
				default:
				}
				return
			}

			score := computeScore(candidate, elapsed, dn42Bonus)
			resChan <- dialResult{
				host:     candidate,
				conn:     conn,
				rtt:      elapsed,
				score:    score,
			}
		}()
	}

	// 等待第一个成功的连接
	var finalists []dialResult
	var timer *time.Timer
	var timerCh <-chan time.Time

	allDone := make(chan struct{})
	go func() {
		wg.Wait()
		close(allDone)
	}()

	loop:
	for {
		select {
		case res := <-resChan:
			finalists = append(finalists, res)
			if timer == nil {
				// 第一个连接成功建立，开启微评估窗口
				timer = time.NewTimer(window)
				timerCh = timer.C
			}
		case <-timerCh:
			// 窗口超时，停止接收新连接，在已建立的连接中择优
			break loop
		case <-allDone:
			// 所有任务均已执行完毕
			if timer != nil {
				timer.Stop()
			}
			// 抽空管道内剩余结果
			for {
				select {
				case res := <-resChan:
					finalists = append(finalists, res)
				default:
					break loop
				}
			}
		}
	}

	// 终止其他仍在等待的拨号任务
	cancel()

	if len(finalists) == 0 {
		close(errs)
		return nil, "", collectDialErrors(errs)
	}

	// 在 finalists 中挑选综合得分最低（最优）的连接
	bestIdx := 0
	for i := 1; i < len(finalists); i++ {
		if finalists[i].score < finalists[bestIdx].score {
			bestIdx = i
		}
	}

	// 关闭未选中的多余连接
	for i, f := range finalists {
		if i != bestIdx {
			_ = f.conn.Close()
		}
	}

	return finalists[bestIdx].conn, finalists[bestIdx].host, nil
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
