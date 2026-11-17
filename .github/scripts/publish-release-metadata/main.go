// publish-release-metadata publishes Edge release metadata to releases.nofire.ai
// (NOFireAI/engineering#1983).
//
// The NOFire AI dashboard reads edge/latest.json to pick the chart version its
// install commands use. For the chart version in Chart.yaml this:
//
//  1. waits until the Helm repo serves it, so latest.json never names a version
//     `helm repo update` cannot find yet;
//  2. writes edge/<version>.json once (never replaced);
//  3. moves edge/latest.json to <version>, unless it already names the same or a
//     newer version, or <version> is a pre-release.
//
// Safe to re-run. Standard library only; it calls the tools on the runner: the
// AWS CLI (credentials for the release metadata role), gh and helm.
//
// Run from the chart's root: go run ./.github/scripts/publish-release-metadata
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const (
	bucket    = "releases.nofire.ai"
	chartRepo = "https://nofireai.github.io/edge-helm-chart"
)

type result struct {
	ok             bool
	stdout, stderr string
}

func run(name string, args ...string) result {
	var stdout, stderr bytes.Buffer
	cmd := exec.Command(name, args...)
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	return result{err == nil, stdout.String(), stderr.String()}
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "::error::"+format+"\n", args...)
	os.Exit(1)
}

// chartField reads a top-level scalar from Chart.yaml, e.g. appVersion.
func chartField(key string) string {
	data, err := os.ReadFile("Chart.yaml")
	if err != nil {
		fail("reading Chart.yaml: %v", err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		name, value, found := strings.Cut(line, ":")
		if found && name == key && strings.TrimSpace(value) != "" {
			return strings.Trim(strings.TrimSpace(value), `"'`)
		}
	}
	fail("Chart.yaml has no %s", key)
	return ""
}

// parseVersion returns major, minor and patch for a plain x.y.z, else nil.
func parseVersion(version string) []int {
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		return nil
	}
	nums := make([]int, 3)
	for i, part := range parts {
		n, err := strconv.Atoi(part)
		if err != nil || n < 0 || strconv.Itoa(n) != part {
			return nil
		}
		nums[i] = n
	}
	return nums
}

// atLeast reports whether version a >= version b.
func atLeast(a, b []int) bool {
	for i := range a {
		if a[i] != b[i] {
			return a[i] > b[i]
		}
	}
	return true
}

func waitForHelmRepo(name, version string) {
	// GitHub Pages deploys after the gh-pages push; give it 10 minutes.
	run("helm", "repo", "add", "--force-update", "nofire", chartRepo)
	for range 40 {
		run("helm", "repo", "update", "nofire")
		if run("helm", "show", "chart", "nofire/"+name, "--version", version).ok {
			return
		}
		time.Sleep(15 * time.Second)
	}
	fail("%s %s is not in the Helm repo after 10 minutes", name, version)
}

func s3(args ...string) result {
	return run("aws", append(append([]string{"s3api"}, args...), "--bucket", bucket)...)
}

func put(key, body, cacheControl string, condition ...string) result {
	args := []string{"put-object", "--key", key, "--body", body,
		"--content-type", "application/json", "--cache-control", cacheControl}
	return s3(append(args, condition...)...)
}

// lostRace reports S3's answer when a conditional write's condition no longer holds.
func lostRace(r result) bool {
	return strings.Contains(r.stderr, "PreconditionFailed") ||
		strings.Contains(r.stderr, "ConditionalRequestConflict")
}

func main() {
	name, version := chartField("name"), chartField("version")
	waitForHelmRepo(name, version)

	release := run("gh", "release", "view", name+"-"+version, "--json", "publishedAt,url")
	if !release.ok {
		fail("no GitHub release %s-%s\n%s", name, version, release.stderr)
	}
	var published struct{ PublishedAt, URL string }
	if err := json.Unmarshal([]byte(release.stdout), &published); err != nil {
		fail("reading gh release output: %v", err)
	}

	work, err := os.MkdirTemp("", "release-metadata")
	if err != nil {
		fail("%v", err)
	}
	metadata, _ := json.MarshalIndent(map[string]any{
		"schema":     1,
		"chart":      map[string]string{"name": name, "version": version, "repo": chartRepo},
		"edge":       map[string]string{"version": chartField("appVersion")},
		"releasedAt": published.PublishedAt,
		"releaseUrl": published.URL,
	}, "", "  ")
	body := filepath.Join(work, "metadata.json")
	if err := os.WriteFile(body, append(metadata, '\n'), 0o644); err != nil {
		fail("%v", err)
	}
	fmt.Println(string(metadata))

	r := put("edge/"+version+".json", body, "public, max-age=31536000, immutable", "--if-none-match", "*")
	if !r.ok && !lostRace(r) {
		fail("writing edge/%s.json failed\n%s", version, r.stderr)
	}
	fmt.Printf("edge/%s.json is published\n", version)

	next := parseVersion(version)
	if next == nil {
		fmt.Printf("%s is not a plain release, leaving latest.json alone\n", version)
		return
	}

	// Read with the role, from S3 rather than through Cloudflare's cache. Only
	// NoSuchKey means there is no latest.json; any other error stops here. The
	// write only lands if latest.json still holds what was read, so of two
	// releases racing, the loser reads again and compares again.
	currentFile := filepath.Join(work, "latest.json")
	for range 5 {
		var current string
		var condition []string
		r := s3("get-object", "--key", "edge/latest.json", currentFile)
		switch {
		case r.ok:
			var doc struct{ Chart struct{ Version string } }
			if data, err := os.ReadFile(currentFile); err == nil {
				_ = json.Unmarshal(data, &doc) // a malformed file is replaced
			}
			var head struct{ ETag string }
			if err := json.Unmarshal([]byte(r.stdout), &head); err != nil || head.ETag == "" {
				fail("no ETag reading edge/latest.json\n%s", r.stdout)
			}
			current, condition = doc.Chart.Version, []string{"--if-match", head.ETag}
		case strings.Contains(r.stderr, "NoSuchKey"):
			condition = []string{"--if-none-match", "*"}
		default:
			fail("reading edge/latest.json failed\n%s", r.stderr)
		}

		if held := parseVersion(current); held != nil && atLeast(held, next) {
			fmt.Printf("latest.json holds %s, leaving it\n", current)
			return
		}
		r = put("edge/latest.json", body, "public, max-age=300", condition...)
		if r.ok {
			if current == "" {
				current = "nothing"
			}
			fmt.Printf("latest.json now holds %s (was %s)\n", version, current)
			return
		}
		if !lostRace(r) {
			fail("writing edge/latest.json failed\n%s", r.stderr)
		}
		fmt.Println("latest.json changed while this ran, reading it again")
	}
	fail("latest.json kept changing, gave up after 5 attempts")
}
