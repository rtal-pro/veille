#!/usr/bin/env bash
# Every table/column/function the prompts rely on must exist in sql/*.sql.
set -euo pipefail
cd "$(dirname "$0")/.."
missing=0
need() { grep -qi -- "$1" sql/*.sql || { echo "MISSING in sql/: $1"; missing=1; }; }
for ident in prospection_clones veille_runs analyses_go sources carte_naf reserves \
             doctrine verdicts audits modifications migrations_appliquees \
             statut_pipeline rapport_attaque score_atelier condition_resurrection \
             statut_jambes dont_go doublons_evites metriques memoire \
             v_sante_pipeline sante_agents derniere_revision; do
  need "$ident"
done
# Workflow/prompt contracts
grep -q "type = 'quotidien'" .github/workflows/veille-quotidienne.yml || { echo "MISSING porte type filter"; missing=1; }
grep -q "budget_respecte" prompts/_constitution.md || { echo "MISSING budget_respecte contract"; missing=1; }
grep -q "superviseur: " prompts/superviseur.md || { echo "MISSING squash subject contract"; missing=1; }
grep -rq "mtkhevwhiriazikfvrbe" prompts/ && { echo "LEAK: project id in prompts/"; missing=1; }
[ "$missing" = "0" ] && echo "OK coherence"
exit $missing
