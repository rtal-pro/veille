#!/usr/bin/env bash
# Fail-closed validator — CONSTITUTIONAL FILE (agents may never modify it).
# Usage: valider.sh [BASE] [HEAD]   (defaults: origin/main HEAD, auto-fetch)
# Called by: superviseur (before merging its own PR) and gendarme (on push range).
set -euo pipefail

BASE="${1:-origin/main}"
HEADREF="${2:-HEAD}"
if [ "$#" -eq 0 ]; then git fetch origin main -q; fi
RANGE="$BASE...$HEADREF"

echo "— Validation du diff $RANGE —"
# --no-renames: a pure content-preserving rename onto a whitelisted filename
# (e.g. `git mv prompts/_constitution.md prompts/rattrapage.md` when rattrapage.md
# doesn't already exist) collapses to a single --name-only line showing only the
# whitelisted destination, hiding the constitutional file's deletion from rule 2.
# Not exploitable against the *current* file layout (every whitelisted name is
# already occupied by a real file, so similarity-based rename detection never
# fires there today) but a fail-closed gate must not depend on that coincidence.
FILES=$(git diff --no-renames --name-only "$RANGE")
[ -n "$FILES" ] || { echo "VALIDATION OK (diff vide)"; exit 0; }

# 1. Workflow YAML files must parse (working-tree state = HEAD side)
python3 - <<'PY'
import yaml, glob
files = glob.glob('.github/workflows/*.yml')
for f in files:
    with open(f) as fh:
        yaml.safe_load(fh)
print(f"YAML OK ({len(files)} workflows)")
PY

# 2. WHITELIST: only agent prompts and the two agent-facing workflows are editable.
ALLOWED='^(prompts/(kiosque|prospecteur|instructeur|contre-avocat|rattrapage|atelier|fossoyeur)\.md|\.github/workflows/(veille-quotidienne|fossoyeur-hebdo)\.yml)$'
BAD=$(echo "$FILES" | grep -vE "$ALLOWED" || true)
if [ -n "$BAD" ]; then
  echo "ERREUR : fichier(s) hors périmètre :"; echo "$BAD"; exit 1
fi

# 3. One intent per week: at most 3 files
N=$(echo "$FILES" | grep -c .)
if [ "$N" -gt 3 ]; then
  echo "ERREUR : diff trop large ($N fichiers > 3) — une expérience à la fois."; exit 1
fi

# 4. Trigger structure is frozen (cron VALUES stay editable: '- cron:' lines pass).
# NOTE: step-level "- name: <label>" lines (e.g. "- name: Préparer le mémo") are
# NOT caught by this regex — after the diff's [+-] marker and leading whitespace,
# the next character is the YAML list dash "-", not "n", so `name:` never matches
# at that position. Renaming a step therefore PASSES rule 4 (and rule 5, since a
# step label matches none of its patterns either). Verified empirically; this is
# accepted: only keys where `name:`/`on:`/`workflows:`/`workflow_run` is the FIRST
# non-space token match, at any indentation (e.g. a job-level `name:` would still
# be caught) — a leading list dash breaks the match, which is why step labels pass
# and a step's display label has no effect on trigger/permission semantics anyway.
if git diff "$RANGE" -- .github/workflows/ | grep -E '^[+-][[:space:]]*(name:|on:|workflows:|workflow_run)'; then
  echo "ERREUR : nom ou déclencheur de workflow touché — merge interdit."; exit 1
fi

# 5. Permissions & secrets frozen — but claude_args lines (model/turns) are allowed.
if git diff "$RANGE" -- .github/workflows/ | grep -E '^[+-]' | grep -v 'claude_args:' \
   | grep -E '(permissions:|id-token|contents:|issues:|actions:|pull-requests:|secrets\.)'; then
  echo "ERREUR : permissions/secrets touchés — merge interdit."; exit 1
fi

# 6. Safety flag count must be identical on both sides.
# `git grep -c` exits 1 when a pattern has zero matches (e.g. a mutation that
# guts all --dangerously-skip-permissions flags). Under `set -e pipefail` that
# would kill the whole script silently mid-pipeline before any ERREUR message
# is printed — still fail-closed (nonzero exit) but with no diagnostic. The
# `|| true` keeps count_at's own exit status 0 so the surrounding count
# comparison below can run and report which pattern's count changed.
count_at() { { git grep -c -e "$2" "$1" -- '.github/workflows/*.yml' 2>/dev/null || true; } \
             | awk -F: '{s+=$NF} END {print s+0}'; }
for pat in 'dangerously-skip-permissions' 'secrets\.'; do
  A=$(count_at "$BASE" "$pat"); B=$(count_at "$HEADREF" "$pat")
  if [ "$A" != "$B" ]; then
    echo "ERREUR : occurrences de '$pat' modifiées ($A -> $B) — merge interdit."; exit 1
  fi
done

echo "VALIDATION OK ($N fichier(s) modifié(s))"
