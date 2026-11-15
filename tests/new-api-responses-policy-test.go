package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"strings"
)

const policyKey = "global.chat_completions_to_responses_policy"

type nixPolicy struct {
	Enable        bool
	AllChannels   bool
	ChannelIds    []int
	ChannelTypes  []int
	ModelPatterns []string
}

type nativePolicy struct {
	Enabled       bool     `json:"enabled"`
	AllChannels   bool     `json:"all_channels"`
	ChannelIds    []int    `json:"channel_ids"`
	ChannelTypes  []int    `json:"channel_types"`
	ModelPatterns []string `json:"model_patterns"`
}

type fixture struct {
	Policy *nixPolicy
	Script string
}

func require(ok bool, format string, args ...any) {
	if !ok {
		panic(fmt.Sprintf(format, args...))
	}
}

func sql(query string) string {
	out, err := exec.Command("psql", "-X", "-v", "ON_ERROR_STOP=1", "-t", "-A", "-c", query).CombinedOutput()
	require(err == nil, "psql failed: %v\n%s", err, out)
	return strings.TrimSuffix(string(out), "\n")
}

func compile(patterns []string) ([]*regexp.Regexp, error) {
	var compiled []*regexp.Regexp
	for _, pattern := range patterns {
		r, err := regexp.Compile(pattern)
		if err != nil {
			return nil, err
		}
		compiled = append(compiled, r)
	}
	return compiled, nil
}

func main() {
	data, err := os.ReadFile(os.Args[1])
	require(err == nil, "read fixtures: %v", err)
	var fixtures map[string]fixture
	require(json.Unmarshal(data, &fixtures) == nil, "invalid fixtures JSON")
	sql("CREATE TABLE options (key text PRIMARY KEY, value text NOT NULL); INSERT INTO options VALUES ('unrelated', 'unchanged');")

	// Execute only the actual options helper and policy call, never credentials or channel bootstrap.
	helperRE := regexp.MustCompile(`(?ms)^\s*upsert_opt\(\) \{.*?^\s*\}`)
	callRE := regexp.MustCompile(`(?m)^\s*upsert_opt "global[.]chat_completions_to_responses_policy" [^\n]*$`)
	var emitted, defaults nativePolicy
	for _, name := range []string{"defaults", "fra0", "disabled", "custom", "unmanaged", "invalidRegex"} {
		f := fixtures[name]
		syntax := exec.Command("bash", "-n")
		syntax.Stdin = strings.NewReader(f.Script)
		out, err := syntax.CombinedOutput()
		require(err == nil, "%s: invalid full bootstrap shell syntax: %v\n%s", name, err, out)
		helper := helperRE.FindString(f.Script)
		require(helper != "", "%s: missing options helper", name)
		calls := callRE.FindAllString(f.Script, -1)
		if f.Policy == nil {
			require(len(calls) == 0, "unmanaged policy must not write a row")
			continue
		}
		require(len(calls) == 1, "%s: expected exactly one policy write", name)
		// Remove only runuser's identity switch, retaining the real psql arguments and input.
		script := "set -eu\nrunuser() { shift 3; \"$@\"; }\n" + helper + "\n" + calls[0] + "\n"
		for i := 0; i < 2; i++ {
			out, err := exec.Command("bash", "-c", script).CombinedOutput()
			require(err == nil, "%s: emitted shell/SQL failed: %v\n%s", name, err, out)
		}
		value := sql("SELECT value FROM options WHERE key = '" + policyKey + "';")
		var actual nativePolicy
		decoder := json.NewDecoder(strings.NewReader(value))
		decoder.DisallowUnknownFields()
		require(decoder.Decode(&actual) == nil, "%s: invalid native JSON keys", name)
		expected := nativePolicy{f.Policy.Enable, f.Policy.AllChannels, f.Policy.ChannelIds, f.Policy.ChannelTypes, f.Policy.ModelPatterns}
		require(reflect.DeepEqual(actual, expected), "%s: persisted JSON changed during shell/SQL quoting: %s", name, value)
		require(sql("SELECT count(*) FROM options;") == "2", "%s: write was not isolated/idempotent", name)
		require(sql("SELECT value FROM options WHERE key = 'unrelated';") == "unchanged", "%s: unrelated option changed", name)
		_, err = compile(actual.ModelPatterns)
		if name == "invalidRegex" {
			require(err != nil, "invalid Go pattern must fail compilation")
		} else {
			require(err == nil, "%s: invalid Go pattern: %v", name, err)
		}
		if name == "fra0" {
			emitted = actual
		}
		if name == "defaults" {
			defaults = actual
		}
		if name == "custom" {
			// Even a successful later shell command must not hide a failed options write.
			sql("ALTER TABLE options RENAME TO unavailable_options;")
			out, err := exec.Command("bash", "-c", script+"true\n").CombinedOutput()
			require(err != nil && strings.Contains(string(out), "ERROR"), "SQL failure was not surfaced: %s", out)
			sql("ALTER TABLE unavailable_options RENAME TO options;")
		}
	}

	patterns, err := compile(defaults.ModelPatterns)
	require(err == nil, "compile emitted defaults: %v", err)
	require(defaults.Enabled && defaults.AllChannels, "global conversion must be enabled by default")
	require(reflect.DeepEqual(emitted, defaults), "fra0 must use the global policy without host exceptions")
	match := func(model string) bool {
		for _, r := range patterns {
			if r.MatchString(model) {
				return true
			}
		}
		return false
	}
	canonical := []string{
		"gpt-5-codex", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-codex-max",
		"gpt-5.2-codex", "gpt-5.3-codex", "gpt-5-pro", "gpt-5.2-pro", "gpt-5.4-pro", "gpt-5.5-pro",
		"o1-pro", "o3-pro", "o3-deep-research", "o4-mini-deep-research", "codex-mini-latest",
		"computer-use-preview", "gpt-daybreak-red-latest", "gpt-daybreak-blue-latest", "gpt-5.6-cyber",
	}
	snapshots := []string{
		"computer-use-preview-2025-03-11", "gpt-5-pro-2025-10-06", "gpt-5.2-pro-2025-12-11",
		"gpt-5.4-pro-2026-03-05", "gpt-5.5-pro-2026-04-23", "o1-pro-2025-03-19",
		"o3-pro-2025-06-10", "o3-deep-research-2025-06-26", "o4-mini-deep-research-2025-06-26",
	}
	require(len(canonical) == 19 && len(snapshots) == 9, "coverage fixture counts changed")
	for _, model := range append(canonical, snapshots...) {
		for _, prefix := range []string{"", "openai/"} {
			for _, suffix := range []string{"", ":free", "@high", ":route_1@reasoning=high", "-variant.v2"} {
				require(match(prefix+model+suffix), "expected match: %s", prefix+model+suffix)
			}
		}
	}
	// Naming tests only, not claims that these future models exist or are available.
	for _, model := range []string{"gpt-7.2-codex-max", "gpt-7.2-pro", "o7-mini-deep-research", "o7-pro"} {
		require(match(model) && match("openai/"+model+"@high"), "future family name did not match: %s", model)
	}
	// Global policy deliberately selects all GPT names, not just Responses-only families.
	gptNames := []string{
		"gpt-4o", "gpt-5", "gpt-5-mini", "gpt-5.5", "gpt-6-astra", "gpt-6-luna", "gpt-6-cyber",
		"gpt-6.1-sol", "gpt-oss-120b", "custom-local:gpt-6.1-sol", "provider/GPT-6.1-SOL",
		"gpt-rosalind-research", "gpt-5.5-cyber-preview", "gpt-daybreak-green-latest",
		"gpt-5.6-cybernetic", "gpt-5-codexlike", "GPT", "alias-gPt-backend", "mygptmodel",
		"azure/gpt-5-pro", "other/openai/gpt-5-pro", "xgpt-5-pro", "gpt-5-pro/extra", "gpt-5-pro:",
		"gpt-5-pro@", "gpt-5-pro ", "gpt-5-pro\n", "GPT-5-PRO", "gpt-5-codex+high",
		"gpt-6.1-solstice", "gpt-6.2-sol", "other/gpt-6.1-sol", "gpt-6.1-sol/extra", "gpt-6.1-sol@",
	}
	for _, model := range gptNames {
		require(match(model) && match("openai/"+model), "global GPT name did not match: %q", model)
	}
	negative := []string{
		"", "o3", "o4-mini", "claude-opus-4-6", "gemini-3-pro", "deepseek-chat",
		"o3-proxy", "codexish", "computer-use-previewish", "other/codex-mini-latest", "g-p-t",
	}
	for _, model := range negative {
		require(!match(model) && !match("openai/"+model), "unexpected match: %q", model)
	}
	_, err = compile([]string{"*gpt*"})
	require(err != nil, "glob syntax must not be accepted as a Go regexp")
	fmt.Println("Responses policy: globally enabled GPT matching, retained non-GPT families, disabled/unmanaged states and PostgreSQL persistence passed")
}
