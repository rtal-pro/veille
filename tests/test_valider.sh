#!/usr/bin/env bash
# Attack scenarios against valider.sh v2. Each case: build a branch, expect PASS/FAIL.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T"; git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p prompts .github/workflows scripts
cp "$ROOT/prompts/"*.md prompts/ 2>/dev/null || true
cp "$ROOT/.github/workflows/"*.yml .github/workflows/
cp "$ROOT/scripts/valider.sh" scripts/
git add -A; git commit -qm base
git remote add origin .; git fetch -q origin  # so origin/main exists

caso() { # caso <expected pass|fail> <name> <mutation commands...>
  local exp=$1 name=$2; shift 2
  git checkout -qb "t-$name" main
  eval "$@" >/dev/null 2>&1 || true
  git add -A
  # NOTE (deviation from brief): `git diff --quiet` alone misses newly-created
  # untracked files (e.g. new-workflow's x.yml) — git diff never compares
  # untracked paths. Stage first, then check the staged diff against HEAD so
  # both modifications AND new files are caught by the anti-vacuous-mutation guard.
  git diff --cached --quiet && { echo "FAIL case '$name': mutation produced no diff"; exit 1; }
  git commit -qm "superviseur: $name" -q
  if bash scripts/valider.sh origin/main HEAD >/dev/null 2>&1; then got=pass; else got=fail; fi
  [ "$got" = "$exp" ] || { echo "FAIL case '$name': expected $exp got $got"; exit 1; }
  git checkout -q main
}
W=.github/workflows/veille-quotidienne.yml

# Legitimate experiments must PASS (regex-generic seds: they keep matching after
# Task 10 rewrites the workflow with new turn counts / models)
caso pass edit-prompt        "echo '<!-- tweak -->' >> prompts/kiosque.md"
caso pass edit-maxturns      "sed -i -E '0,/--max-turns [0-9]+/s/--max-turns [0-9]+/--max-turns 42/' $W"
caso pass edit-model         "sed -i -E '0,/--model [a-z0-9.-]+/s/--model [a-z0-9.-]+/--model claude-haiku-4-5/' $W"
caso pass edit-cron          "sed -i -E '0,/- cron: /s/- cron: \"[^\"]+\"/- cron: \"45 4 * * *\"/' $W"
# Pins a verified, non-obvious rule-4 boundary: a step's display label ("- name: X")
# is NOT the workflow-level `name:`/`on:` key the rule freezes (a leading list dash
# breaks the match), so renaming a step is allowed. Kept as an assertion, not just a
# comment in valider.sh, so future rule-4 edits can't silently invert this behavior.
caso pass rename-step        "sed -i -E '0,/^ +- name: /s/^( +- name: ).*/\1Prep memo/' $W"

# Attacks must FAIL
caso fail touch-constitution "echo x >> prompts/_constitution.md"
caso fail touch-superviseur  "echo x >> prompts/superviseur.md"
caso fail touch-validator    "echo x >> scripts/valider.sh"
caso fail new-workflow       "printf 'name: X\non: push\n' > .github/workflows/x.yml"
caso fail rename-workflow    "sed -i 's/^name: Veille quotidienne/name: Veille 2/' $W"
caso fail edit-trigger       "sed -i 's/^on:/on: # x/' $W"
caso fail add-permission     "sed -i 's/contents: read/contents: read\n  actions: write/' $W"
caso fail drop-safety-flag   "sed -i '0,/ --dangerously-skip-permissions/s///' $W"
caso fail add-secret-ref     "sed -i 's|FIRECRAWL_API_KEY: .*|FIRECRAWL_API_KEY: \${{ secrets.EXFIL }}|' $W"
caso fail wide-diff          "echo x >> prompts/kiosque.md; echo x >> prompts/atelier.md; echo x >> prompts/prospecteur.md; echo x >> prompts/instructeur.md"
caso fail touch-sql          "mkdir -p sql; echo '-- x' > sql/999_evil.sql"
echo "OK valider"
