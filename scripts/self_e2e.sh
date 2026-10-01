#!/bin/sh
# turtles self-verification gate.
#
# Run the (possibly mutated) turtles binary in the current working directory
# against fixtures/basic and validate its JSON report. The fixture target is
# hard-coded so a self-mutation run can never recurse into ".".
#
# Required on PATH: moon, python3. Exits non-zero if the mutated binary
# crashes, misreports the fixture run, or leaves survivors/timeouts.
set -eu

report_dir="$(mktemp -d)"
trap 'rm -rf "$report_dir"' EXIT

validate() {
python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    report = json.load(handle)

assert report["schema"] == 3, report.get("schema")
assert len(report["mutants"]) == 6, len(report["mutants"])
assert report["summary"]["killed"] == 6, report["summary"]
assert report["summary"]["survived"] == 0, report["summary"]
assert report["summary"]["timeout"] == 0, report["summary"]
assert report["summary"]["unviable"] == 0, report["summary"]
PY
}

# Report into an existing directory: a mutated binary that drops
# allow_exist=true fails here.
moon run cmd/turtles -- --dir fixtures/basic --timeout 60 \
  --json "$report_dir/report.json"
validate "$report_dir/report.json"

# Report into a nested, non-existent directory: a mutated binary that drops
# recursive=true fails here. Both runs must succeed and report cleanly.
moon run cmd/turtles -- --dir fixtures/basic --timeout 60 \
  --json "$report_dir/nested/deep/report.json"
validate "$report_dir/nested/deep/report.json"
