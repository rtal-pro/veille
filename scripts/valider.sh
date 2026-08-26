#!/usr/bin/env bash
# Fail-closed validator — CONSTITUTIONAL FILE (agents may never modify it).
# Usage: valider.sh [BASE] [HEAD]   (defaults: origin/main HEAD, auto-fetch)
# Called by: superviseur (before merging its own PR) and gendarme (on push range).
set -euo pipefail

# CWD-independence: rule 1's YAML glob and every git pathspec below (rules
# 4/4bis/5/6) are relative to the current directory. Invoked from anywhere
# other than the repo root (e.g. from inside prompts/), the glob would find
# 0 workflows and the pathspecs would match nothing, silently validating an
# empty/wrong file set instead of the real diff — a fail-open bug. Anchor to
# the repo root unconditionally, before anything else runs.
cd "$(git rev-parse --show-toplevel)"

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

# 2bis. No deletions. A deleted whitelisted prompt (e.g. `git rm
# prompts/contre-avocat.md`) still shows up as an allowed PATH under rule 2 —
# the path itself matches the whitelist regardless of whether the file still
# exists — so deleting it silently disarms an agent without touching any
# workflow. Reject any deletion outright, regardless of whitelist status.
DELETED=$(git diff --no-renames --diff-filter=D --name-only "$RANGE")
if [ -n "$DELETED" ]; then
  echo "ERREUR : suppression de fichier interdite :"; echo "$DELETED"; exit 1
fi

# 3. One intent per week: at most 3 files
N=$(echo "$FILES" | grep -c .)
if [ "$N" -gt 3 ]; then
  echo "ERREUR : diff trop large ($N fichiers > 3) — une expérience à la fois."; exit 1
fi

# 4. The workflow-level `name:`/`on:` KEY LINES themselves are frozen (cron
# VALUES nested under `on:` stay editable: '- cron:' lines pass). This only
# ever froze those specific lines, never the *children* introduced under
# `on:` (a new `push:`/`issue_comment:` trigger one level down) or anything
# else inside the file body — see rule 4bis below for that.
# NOTE: step-level "- name: <label>" lines (e.g. "- name: Préparer le mémo") are
# NOT caught by this regex — after the diff's [+-] marker and leading whitespace,
# the next character is the YAML list dash "-", not "n", so `name:` never matches
# at that position. Renaming a step therefore PASSES rule 4 (rule 4bis explicitly
# allows it too — a step's display label has no effect on trigger/permission
# semantics). Verified empirically; only keys where `name:`/`on:`/`workflows:`/
# `workflow_run` is the FIRST non-space token match, at any indentation (e.g. a
# job-level `name:` would still be caught) — a leading list dash breaks the match.
if git diff "$RANGE" -- .github/workflows/ | grep -E '^[+-][[:space:]]*(name:|on:|workflows:|workflow_run)'; then
  echo "ERREUR : nom ou déclencheur de workflow touché — merge interdit."; exit 1
fi

# 4bis. Rules 3-6 gate WHICH files/lines are frozen, but nothing so far stops
# arbitrary edits INSIDE the two whitelisted workflows: a `run:` step body can
# be replaced (e.g. exfiltrate an env secret via curl), a bare trigger child
# can be added under `on:` (`push:`, `issue_comment:`, ...) without touching
# the `on:` line rule 4 watches, or a brand-new step (`uses:`/`run:`) can be
# appended — all invisible to rules 4-6. Close this with an explicit allowlist
# of the ONLY line shapes the Superviseur may add/remove in these two files:
# claude_args (model/turn edits), cron values, timeout-minutes, agent prompt
# text, a step's own display label, and blank lines. Anything else — run:,
# uses:, permissions/env/comments, new steps, on:'s children — is rejected.
# A `secrets.` reference is rejected unconditionally on ANY modified line in
# these two files, checked before the shape allowlist below — most notably on
# an otherwise-legal claude_args line, since rule 5 explicitly exempts any
# line containing `claude_args:` from its permissions/secrets check, which
# would otherwise let a secret be smuggled into claude_args undetected. (For
# this specific mutation rule 6's occurrence-count check independently catches
# it too — verified empirically, count changes — but 4bis is what actually
# fires first and is the only rule that would also catch a subtler variant
# where an attacker nets the count back to zero by pairing the addition with a
# removal on another claude_args line elsewhere — the only other line shape
# rule 5 doesn't itself watch for secrets.)
# CONSTRAINT: this also means a `secrets.` ref on an otherwise-allowed
# cron/timeout-minutes/prompt line would be rejected too. Verified today: none
# of the allowed-shape lines in either whitelisted workflow carry one (checked
# via `grep -n 'secrets\.' .github/workflows/{veille-quotidienne,fossoyeur-hebdo}.yml`
# — all hits are on env:/claude_code_oauth_token:/username:/password:/to:
# lines, none on prompt:/timeout-minutes:/cron:). If a future prompt ever
# needs to legitimately interpolate a secret, this rule would have to gain an
# explicit exception for that case.
WHITELISTED_WORKFLOWS=(.github/workflows/veille-quotidienne.yml .github/workflows/fossoyeur-hebdo.yml)
BAD_LINES=""
while IFS= read -r dline; do
  [ -z "$dline" ] && continue
  case "$dline" in
    '+++'*|'---'*) continue ;;
  esac
  body="${dline#[+-]}"
  if [[ "$body" == *'secrets.'* ]]; then
    BAD_LINES+="$dline"$'\n'; continue
  fi
  stripped="${body#"${body%%[![:space:]]*}"}"
  if [ -z "$stripped" ]; then continue; fi
  if [[ "$stripped" =~ ^claude_args: ]]; then continue; fi
  if [[ "$stripped" =~ ^-[[:space:]]*cron: ]] || [[ "$stripped" =~ ^cron: ]]; then continue; fi
  if [[ "$stripped" =~ ^-[[:space:]]*name: ]]; then continue; fi
  if [[ "$stripped" =~ ^timeout-minutes: ]]; then continue; fi
  if [[ "$stripped" =~ ^prompt: ]]; then continue; fi
  BAD_LINES+="$dline"$'\n'
done < <(git diff "$RANGE" -- "${WHITELISTED_WORKFLOWS[@]}" | grep -E '^[+-]' || true)
if [ -n "$BAD_LINES" ]; then
  echo "ERREUR : ligne non éditable dans un workflow (seuls cron/timeout/model/max-turns/prompt le sont)"
  echo "$BAD_LINES"; exit 1
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
