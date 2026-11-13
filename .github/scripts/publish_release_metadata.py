#!/usr/bin/env python3
"""Publish Edge release metadata to releases.nofire.ai (NOFireAI/engineering#1983).

The NOFire AI dashboard reads edge/latest.json to pick the chart version its
install commands use. For the chart version in Chart.yaml this:

1. waits until the Helm repo serves it, so latest.json never names a version
   `helm repo update` cannot find yet;
2. writes edge/<version>.json once (never replaced);
3. moves edge/latest.json to <version>, unless it already names the same or a
   newer version, or <version> is a pre-release.

Safe to re-run. Uses only the standard library and the tools on the runner:
the AWS CLI (credentials for the release metadata role), gh and helm.

Run from the chart's root: python3 .github/scripts/publish_release_metadata.py
"""

import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BUCKET = "releases.nofire.ai"
CHART_REPO = "https://nofireai.github.io/edge-helm-chart"


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def fail(message, result=None):
    sys.exit(f"::error::{message}" + (f"\n{result.stderr}" if result else ""))


def chart_field(key):
    """A top-level scalar from Chart.yaml, e.g. appVersion."""
    for line in Path("Chart.yaml").read_text().splitlines():
        name, _, value = line.partition(":")
        if name == key and value.strip():
            return value.strip().strip("\"'")
    fail(f"Chart.yaml has no {key}")


def parse_version(version):
    """(major, minor, patch) for a plain x.y.z, else None."""
    parts = version.split(".") if isinstance(version, str) else []
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        return None
    return tuple(int(p) for p in parts)


def wait_for_helm_repo(name, version):
    # GitHub Pages deploys after the gh-pages push; give it 10 minutes.
    run("helm", "repo", "add", "--force-update", "nofire", CHART_REPO)
    for _ in range(40):
        run("helm", "repo", "update", "nofire")
        if run("helm", "show", "chart", f"nofire/{name}", "--version", version).returncode == 0:
            return
        time.sleep(15)
    fail(f"{name} {version} is not in the Helm repo after 10 minutes")


def s3(*args):
    return run("aws", "s3api", *args, "--bucket", BUCKET)


def put(key, body, cache_control, *condition):
    return s3("put-object", "--key", key, "--body", body,
              "--content-type", "application/json",
              "--cache-control", cache_control, *condition)


def lost_race(result):
    # S3's answer when a conditional write's condition no longer holds.
    return "PreconditionFailed" in result.stderr or "ConditionalRequestConflict" in result.stderr


def main():
    name, version = chart_field("name"), chart_field("version")
    wait_for_helm_repo(name, version)

    release = run("gh", "release", "view", f"{name}-{version}", "--json", "publishedAt,url")
    if release.returncode != 0:
        fail(f"no GitHub release {name}-{version}", release)
    release = json.loads(release.stdout)

    work = Path(tempfile.mkdtemp())
    body = work / "metadata.json"
    body.write_text(json.dumps({
        "schema": 1,
        "chart": {"name": name, "version": version, "repo": CHART_REPO},
        "edge": {"version": chart_field("appVersion")},
        "releasedAt": release["publishedAt"],
        "releaseUrl": release["url"],
    }, indent=2) + "\n")
    print(body.read_text())

    result = put(f"edge/{version}.json", str(body),
                 "public, max-age=31536000, immutable", "--if-none-match", "*")
    if result.returncode != 0 and not lost_race(result):
        fail(f"writing edge/{version}.json failed", result)
    print(f"edge/{version}.json is published")

    new = parse_version(version)
    if new is None:
        print(f"{version} is not a plain release, leaving latest.json alone")
        return

    # Read with the role, from S3 rather than through Cloudflare's cache. Only
    # NoSuchKey means there is no latest.json; any other error stops here. The
    # write only lands if latest.json still holds what was read, so of two
    # releases racing, the loser reads again and compares again.
    current_file = work / "latest.json"
    for _ in range(5):
        result = s3("get-object", "--key", "edge/latest.json", str(current_file))
        if result.returncode == 0:
            current = json.loads(current_file.read_text()).get("chart", {}).get("version")
            condition = ("--if-match", json.loads(result.stdout)["ETag"])
        elif "NoSuchKey" in result.stderr:
            current, condition = None, ("--if-none-match", "*")
        else:
            fail("reading edge/latest.json failed", result)

        held = parse_version(current)
        if held is not None and held >= new:
            print(f"latest.json holds {current}, leaving it")
            return
        result = put("edge/latest.json", str(body), "public, max-age=300", *condition)
        if result.returncode == 0:
            print(f"latest.json now holds {version} (was {current or 'nothing'})")
            return
        if not lost_race(result):
            fail("writing edge/latest.json failed", result)
        print("latest.json changed while this ran, reading it again")
    fail("latest.json kept changing, gave up after 5 attempts")


if __name__ == "__main__":
    main()
