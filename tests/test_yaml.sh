#!/usr/bin/env bash
# All workflow YAML files must parse.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import yaml, glob, sys
files = sorted(glob.glob('.github/workflows/*.yml'))
if not files: sys.exit("no workflow files found")
for f in files:
    with open(f) as fh:
        yaml.safe_load(fh)
print(f"OK yaml ({len(files)} workflows)")
PY
