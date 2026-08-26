#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
rc=0
for t in test_*.sh; do
  echo "===== $t ====="
  if bash "$t"; then echo "PASS $t"; else echo "FAIL $t"; rc=1; fi
done
exit $rc
