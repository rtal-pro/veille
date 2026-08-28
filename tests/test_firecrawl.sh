#!/usr/bin/env bash
# Exercises scripts/fc.sh against a fake Firecrawl API: the budget gates must
# hold (they are the whole point of the wrapper), the cost must be measured by
# solde delta rather than trusted from the barème, and every failure mode must
# be a clean exit code the agent can branch on — never a crash.
set -uo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d); trap 'kill "${SRV:-0}" 2>/dev/null; rm -rf "$TMP"' EXIT
rc=0
ko() { echo "FAIL: $*"; rc=1; }

# --- Fake Firecrawl -------------------------------------------------------
# Serves the credit-usage endpoint and the three POST endpoints, decrementing
# a real credit counter so fc.sh's before/after delta measures something true.
cat > "$TMP/fake.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = {"credits": int(sys.argv[2])}
COUT = {"search": 2, "map": 1, "scrape": 1}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        if self.path.endswith("/team/credit-usage"):
            return self._send({"success": True,
                               "data": {"remaining_credits": STATE["credits"]}})
        self._send({"error": "not found"}, 404)
    def do_POST(self):
        ep = self.path.rsplit("/", 1)[-1]
        self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        if ep not in COUT:
            return self._send({"error": "not found"}, 404)
        STATE["credits"] -= COUT[ep]
        self._send({"success": True, "endpoint": ep})

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
python3 "$TMP/fake.py" "$PORT" 500 & SRV=$!
for _ in $(seq 50); do
  curl -sf "http://127.0.0.1:$PORT/v2/team/credit-usage" >/dev/null 2>&1 && break
  sleep 0.1
done

# No SUPABASE_DB_URL on purpose: the DB-blind path must still be bounded by the
# per-run cap. The shared daily counter is covered by test_migrations.sh (schema)
# and by the gate arithmetic below, not by a live database here.
export FIRECRAWL_API="http://127.0.0.1:$PORT"
export FIRECRAWL_API_KEY="fake-key"
export FC_AGENT="test"
unset SUPABASE_DB_URL 2>/dev/null || true

fc() { FC_COMPTEUR="$TMP/compteur" bash scripts/fc.sh "$@" 2>"$TMP/err"; }

cas() { # nom code_attendu commande...
  local nom="$1" want="$2"; shift 2
  local out; out=$("$@"); local got=$?
  [ "$got" = "$want" ] || { ko "$nom : exit $got (attendu $want)"; sed 's/^/    /' "$TMP/err"; return; }
  echo "  ok  $nom"
}

echo "— garde-fous d'usage —"
FIRECRAWL_API_KEY="" cas "clé absente → 4" 4 fc scrape '{"url":"https://x.tld"}'
cas "endpoint inconnu → 2" 2 fc crawl '{"url":"https://x.tld"}'
cas "JSON invalide → 2" 2 fc scrape '{url:'

echo "— appel nominal et coût mesuré —"
rm -f "$TMP/compteur"
cas "scrape autorisé → 0" 0 fc scrape '{"url":"https://x.tld"}'
grep -q '"success"' <<<"$(FC_COMPTEUR="$TMP/compteur2" bash scripts/fc.sh scrape '{"url":"https://x.tld"}' 2>/dev/null)" \
  || ko "la réponse Firecrawl ne ressort pas sur stdout"
# Coût pris sur le delta de solde (1), pas sur le barème : le compteur de run
# vaut exactement le nombre d'appels effectués.
[ "$(cat "$TMP/compteur")" = "1" ] || ko "compteur de run = $(cat "$TMP/compteur") (attendu 1)"

echo "— plafond de run —"
rm -f "$TMP/compteur"
FIRECRAWL_CAP_RUN=1 fc scrape '{"url":"https://x.tld"}' >/dev/null
FIRECRAWL_CAP_RUN=1 cas "2e appel au-delà du cap → 3" 3 fc scrape '{"url":"https://x.tld"}'
[ "$(cat "$TMP/compteur")" = "1" ] || ko "un appel refusé a été facturé ($(cat "$TMP/compteur"))"

echo "— réserve de déblocage —"
rm -f "$TMP/compteur"
# Solde 500, réserve 499 : /search entamerait la réserve, /scrape doit passer —
# c'est la priorité constitutionnelle (débloquer une preuve > découvrir large).
FIRECRAWL_RESERVE=499 cas "search sous la réserve → 3" 3 fc search '{"query":"x","limit":10}'
FIRECRAWL_RESERVE=499 cas "scrape sous la réserve → 0" 0 fc scrape '{"url":"https://x.tld"}'

echo "— barème /search (borne haute d'autorisation) —"
rm -f "$TMP/compteur"
# limit 10 sans scrapeOptions = 2 crédits ; un cap de 1 doit donc refuser AVANT
# l'appel, sinon le plafond serait franchi puis constaté après coup.
FIRECRAWL_CAP_RUN=1 cas "search limit=10 refusé sous cap=1 → 3" 3 fc search '{"query":"x","limit":10}'
[ ! -s "$TMP/compteur" ] || ko "un crédit a été consommé malgré le refus a priori"

echo "— rapport de solde —"
cas "solde → 0" 0 fc solde
grep -q "solde live" "$TMP/err" || ko "fc.sh solde n'affiche pas le solde"

[ "$rc" = 0 ] && echo "test_firecrawl: OK"
exit $rc
