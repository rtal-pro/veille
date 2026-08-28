#!/usr/bin/env bash
# ============================================================================
# fc.sh — GUICHET UNIQUE FIRECRAWL : comptabilité exacte + plafond partagé.
#
# POURQUOI CE FICHIER EXISTE
# Jusqu'au 2026-08-28, les agents appelaient l'API Firecrawl en `curl` direct,
# avec pour seul garde-fou une phrase de la constitution (« règle d'or : ~33
# crédits/jour »). Mais le pipeline lance 8 à 12 PROCESSUS D'AGENTS
# INDÉPENDANTS par jour (4 passes de récolte × kiosque + prospecteur, plus le
# jugement, le tout doublé les lendemains de jour rouge). Chacun respectait
# « son » budget dans son coin ; personne ne comptait le total ; rien n'était
# journalisé. Un budget par run dans un système multi-processus n'est pas un
# budget — c'est une multiplication. Constat des 3 premiers jours : la moitié
# du stock gratuit brûlée, sans qu'aucune trace ne permette de dire à quoi.
#
# CE QUE CE SCRIPT GARANTIT
#   1. Une ligne en base (`firecrawl_appels`) par appel, avec son coût RÉEL,
#      mesuré par différence de solde avant/après (et non estimé).
#   2. Un plafond GLOBAL au jour, partagé par tous les agents et tous les runs,
#      lu dans cette même table — le seul compteur qui fait foi.
#   3. Une réserve intouchable pour l'usage le plus rentable du crédit : le
#      déblocage (`scrape`) d'une page à anti-bot qui porte une preuve.
#   4. Un refus PROPRE (exit 3) : jamais une panne. L'agent retombe sur
#      WebSearch / WebFetch / curl gratuit et continue sa mission.
#
# USAGE
#   scripts/fc.sh solde                    # solde live + consommation du jour
#   scripts/fc.sh search '{"query":"…","limit":10,"location":"France"}'
#   scripts/fc.sh map    '{"url":"https://…","search":"mot-clé"}'
#   scripts/fc.sh scrape '{"url":"https://…"}'
#
# La réponse JSON de Firecrawl sort sur STDOUT (pipe-able vers jq) ; tout le
# reste (diagnostics, refus, coûts) sort sur STDERR.
#
# CODES DE SORTIE
#   0  appel effectué
#   2  usage incorrect (endpoint inconnu, JSON invalide)
#   3  REFUS BUDGÉTAIRE — attendu, non bloquant : bascule sur le web gratuit
#   4  Firecrawl indisponible (clé absente, erreur HTTP, réseau)
#
# RÉGLAGES (variables d'environnement, toutes optionnelles)
#   FIRECRAWL_BUDGET_JOUR   plafond global de crédits par jour   (défaut 10)
#   FIRECRAWL_CAP_RUN       plafond par processus d'agent        (défaut 6)
#   FIRECRAWL_RESERVE       solde en dessous duquel seul `scrape` passe (défaut 40)
#   FC_AGENT                nom de l'agent appelant (posé par le workflow)
# ============================================================================
set -uo pipefail

API="${FIRECRAWL_API:-https://api.firecrawl.dev}"
BUDGET_JOUR="${FIRECRAWL_BUDGET_JOUR:-10}"
CAP_RUN="${FIRECRAWL_CAP_RUN:-6}"
RESERVE="${FIRECRAWL_RESERVE:-40}"
AGENT="${FC_AGENT:-inconnu}"
RUN_ID="${GITHUB_RUN_ID:-local}"
# Compteur local au processus : seul rempart si la base est injoignable.
COMPTEUR_RUN="${FC_COMPTEUR:-/tmp/fc-credits-run}"

err() { printf '%s\n' "$*" >&2; }

# --- Accès base (jamais bloquant : une base muette ne doit pas tuer l'agent) --
psql_tac() {
  [ -n "${SUPABASE_DB_URL:-}" ] || return 1
  command -v psql >/dev/null 2>&1 || return 1
  psql "$SUPABASE_DB_URL" -tAc "$1" 2>/dev/null
}

sql_lit() { printf "%s" "$1" | sed "s/'/''/g"; }

# Consommation du jour, tous agents et tous runs confondus.
consomme_jour() {
  local n
  n=$(psql_tac "select coalesce(sum(credits),0) from firecrawl_appels where date_run = current_date and not refuse") || return 1
  [ -n "$n" ] || return 1
  printf '%s' "$n"
}

consomme_run() { [ -f "$COMPTEUR_RUN" ] && cat "$COMPTEUR_RUN" || printf '0'; }

ajoute_run() {
  local total
  total=$(( $(consomme_run) + $1 ))
  printf '%s' "$total" > "$COMPTEUR_RUN" 2>/dev/null || true
}

journalise() {  # endpoint requete credits solde source_cout http refuse motif
  local q; q=$(sql_lit "$(printf '%s' "$2" | cut -c1-500)")
  local m; m=$(sql_lit "$8")
  psql_tac "insert into firecrawl_appels
      (agent, endpoint, requete, credits, credits_restants, source_cout, http_status, refuse, motif, run_id)
    values ('$(sql_lit "$AGENT")', '$(sql_lit "$1")', '$q', $3,
            $( [ -n "$4" ] && printf '%s' "$4" || printf 'null' ),
            '$5',
            $( [ -n "$6" ] && printf '%s' "$6" || printf 'null' ),
            $7, '$m', '$(sql_lit "$RUN_ID")')" >/dev/null \
    || err "fc.sh: journalisation en base impossible (appel tout de même compté localement)"
}

# --- Solde live -------------------------------------------------------------
# L'endpoint de solde n'est pas facturé. Son chemin a bougé entre versions
# d'API : on essaie v2 puis v1, et on accepte les trois formes de nommage
# rencontrées. Aucune n'est garantie à vie — d'où la dégradation propre vers
# le barème, avec `source_cout` qui dit toujours laquelle a servi.
solde() {
  local v r
  for v in v2 v1; do
    r=$(curl -s --max-time 20 -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
          "$API/$v/team/credit-usage" 2>/dev/null) || continue
    printf '%s' "$r" | jq -e -r \
      '(.data.remaining_credits // .data.remainingCredits // .remaining_credits // .remainingCredits) | numbers' \
      2>/dev/null && return 0
  done
  return 1
}

# --- Barème (plafond haut, utilisé pour AUTORISER avant l'appel) ------------
# Tarif public : /search = 2 crédits par tranche de 10 résultats, +1 par page
# effectivement scrapée ; /map = 1 quel que soit le nombre d'URLs ; /scrape = 1.
bareme() {
  local ep="$1" payload="$2" limite pages
  case "$ep" in
    map|scrape) printf '1' ;;
    search)
      limite=$(printf '%s' "$payload" | jq -r '.limit // 5' 2>/dev/null)
      case "$limite" in ''|*[!0-9]*) limite=5 ;; esac
      pages=$(( (limite + 9) / 10 * 2 ))
      if printf '%s' "$payload" | jq -e 'has("scrapeOptions")' >/dev/null 2>&1; then
        pages=$(( pages + limite ))
      fi
      printf '%s' "$pages" ;;
    *) printf '1' ;;
  esac
}

# --- Rapport de solde -------------------------------------------------------
rapport() {
  local s c
  s=$(solde) || s=""
  c=$(consomme_jour) || c=""
  err "── Firecrawl ──"
  err "  solde live        : ${s:-inconnu}"
  err "  consommé aujourd'hui (tous agents) : ${c:-inconnu (base injoignable)}"
  err "  plafond du jour   : $BUDGET_JOUR   → reste ${c:+$(( BUDGET_JOUR - c ))}"
  err "  plafond de ce run : $CAP_RUN       → consommé ici $(consomme_run)"
  err "  réserve déblocage : $RESERVE (en dessous, seul /scrape passe)"
  [ -n "$s" ] || err "  (solde live indisponible : les coûts seront estimés au barème)"
}

# ============================================================================
EP="${1:-}"
[ -n "${FIRECRAWL_API_KEY:-}" ] || {
  err "fc.sh: FIRECRAWL_API_KEY absent — Firecrawl indisponible, utilise WebSearch/WebFetch/curl."
  exit 4
}

if [ "$EP" = "solde" ]; then rapport; exit 0; fi

case "$EP" in
  search|map|scrape) ;;
  *) err "usage: fc.sh {search|map|scrape} '<json>'  |  fc.sh solde"; exit 2 ;;
esac

PAYLOAD="${2:-}"
printf '%s' "$PAYLOAD" | jq -e . >/dev/null 2>&1 || {
  err "fc.sh: payload JSON invalide. Rappel : les guillemets internes doivent être échappés, ou utilise un heredoc."
  exit 2
}
CLE=$(printf '%s' "$PAYLOAD" | jq -r '.query // .url // ""' 2>/dev/null)

# ---------------------------------------------------------------- garde-fous
COUT_MAX=$(bareme "$EP" "$PAYLOAD")
SOLDE_AVANT=$(solde) || SOLDE_AVANT=""

refuser() {
  err "fc.sh: REFUS — $1"
  err "fc.sh: ce n'est pas une panne. Continue avec WebSearch / WebFetch / curl."
  journalise "$EP" "$CLE" 0 "$SOLDE_AVANT" "refus" "" true "$1"
  exit 3
}

CONSO_JOUR=$(consomme_jour) || CONSO_JOUR=""
if [ -n "$CONSO_JOUR" ]; then
  if [ $(( CONSO_JOUR + COUT_MAX )) -gt "$BUDGET_JOUR" ]; then
    refuser "plafond du jour atteint ($CONSO_JOUR/$BUDGET_JOUR crédits déjà consommés par l'ensemble des agents, cet appel en coûterait jusqu'à $COUT_MAX)"
  fi
else
  err "fc.sh: base injoignable — le compteur partagé du jour est aveugle, seul le plafond de run ($CAP_RUN) s'applique."
fi

if [ $(( $(consomme_run) + COUT_MAX )) -gt "$CAP_RUN" ]; then
  refuser "plafond de ce run atteint ($(consomme_run)/$CAP_RUN crédits)"
fi

if [ -n "$SOLDE_AVANT" ]; then
  if [ "$SOLDE_AVANT" -lt "$COUT_MAX" ]; then
    refuser "stock Firecrawl épuisé (solde $SOLDE_AVANT)"
  fi
  # La réserve protège le seul usage qu'aucun outil gratuit ne remplace :
  # débloquer une page à anti-bot qui porte une preuve déjà identifiée.
  if [ "$EP" != "scrape" ] && [ $(( SOLDE_AVANT - COUT_MAX )) -lt "$RESERVE" ]; then
    refuser "réserve de déblocage entamée (solde $SOLDE_AVANT, réserve $RESERVE) — au-dessous, seul /scrape d'une preuve bloquée passe"
  fi
fi

# ---------------------------------------------------------------- appel réel
REP=$(curl -s -w '\n%{http_code}' --max-time 120 \
        -X POST "$API/v2/$EP" \
        -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null)
CURL_RC=$?
HTTP=$(printf '%s' "$REP" | tail -n1)
CORPS=$(printf '%s' "$REP" | sed '$d')

# Coût réel : différence de solde avant/après. C'est la seule mesure exacte —
# le barème n'est qu'une borne haute pour décider d'autoriser.
SOLDE_APRES=$(solde) || SOLDE_APRES=""
if [ -n "$SOLDE_AVANT" ] && [ -n "$SOLDE_APRES" ] && [ "$SOLDE_APRES" -le "$SOLDE_AVANT" ]; then
  COUT=$(( SOLDE_AVANT - SOLDE_APRES )); SRC="delta"
else
  COUT="$COUT_MAX"; SRC="bareme"
fi

case "$HTTP" in
  2*) : ;;
  429) COUT=0; SRC="bareme" ;;   # rate-limit : rien n'a été servi, rien n'est facturé
  *)   [ "$SRC" = "bareme" ] && COUT=0 ;;
esac

ajoute_run "$COUT"
journalise "$EP" "$CLE" "$COUT" "$SOLDE_APRES" "$SRC" "$HTTP" false ""

if [ "$CURL_RC" -ne 0 ] || ! printf '%s' "$HTTP" | grep -q '^2'; then
  err "fc.sh: Firecrawl a répondu HTTP ${HTTP:-?} (coût compté : $COUT). Bascule sur WebSearch/WebFetch."
  printf '%s\n' "$CORPS" >&2
  exit 4
fi

err "fc.sh: $EP ok — $COUT crédit(s) [$SRC], solde ${SOLDE_APRES:-?}, cumul du jour $(( ${CONSO_JOUR:-0} + COUT ))/$BUDGET_JOUR"
printf '%s\n' "$CORPS"
