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
#   5. Une page payée UNE fois : le cache (`firecrawl_cache`) est consulté AVANT
#      le plafond. Le contenu brut était jusqu'ici lu, résumé en deux lignes,
#      puis jeté avec le runner — donc racheté au passage suivant. Il est
#      maintenant conservé et resservi à 0 crédit.
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
#   FIRECRAWL_CACHE_JOURS   durée de vie du cache /map et /scrape (défaut 14)
#   FIRECRAWL_CACHE_JOURS_SEARCH  idem pour /search, plus court (défaut 3)
#   FIRECRAWL_CACHE_MAX_KO  taille au-delà de laquelle on ne garde pas en base (défaut 400)
#   FC_NOCACHE=1            force un appel frais (à justifier dans le journal)
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
# Cache à deux étages : un dossier local (même run, aucun aller-retour base) et
# la table firecrawl_cache (tous les agents, tous les runs, plusieurs jours).
CACHE_DIR="${FC_CACHE_DIR:-/tmp/fc-cache}"
CACHE_MAX_KO="${FIRECRAWL_CACHE_MAX_KO:-400}"

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

# --- Cache ------------------------------------------------------------------
psql_file() {
  [ -n "${SUPABASE_DB_URL:-}" ] || return 1
  command -v psql >/dev/null 2>&1 || return 1
  psql "$SUPABASE_DB_URL" -q -f "$1" >/dev/null 2>&1
}

# Clé stable : les mêmes paramètres dans un ordre différent doivent tomber sur
# la même entrée, sinon le cache ne sert jamais deux fois (jq -S trie les clés).
cle_cache() { printf '%s|%s' "$1" "$(printf '%s' "$2" | jq -S -c . 2>/dev/null)" | md5sum | cut -d' ' -f1; }

# /search vieillit vite (c'est une SERP, souvent avec tbs:"qdr:w"), /map et
# /scrape beaucoup moins. Deux durées de vie plutôt qu'une moyenne fausse.
ttl_cache() {
  case "$1" in
    search) printf '%s' "${FIRECRAWL_CACHE_JOURS_SEARCH:-3}" ;;
    *)      printf '%s' "${FIRECRAWL_CACHE_JOURS:-14}" ;;
  esac
}

lire_cache_local() {
  local f="$CACHE_DIR/$1.json" e="$CACHE_DIR/$1.exp"
  [ -s "$f" ] && [ -s "$e" ] || return 1
  [ "$(cat "$e")" -gt "$(date +%s)" ] 2>/dev/null || return 1
  cat "$f"
}

ecrire_cache_local() {
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 0
  printf '%s' "$2" > "$CACHE_DIR/$1.json" 2>/dev/null || return 0
  printf '%s' "$(( $(date +%s) + $3 * 86400 ))" > "$CACHE_DIR/$1.exp" 2>/dev/null || true
}

# base64 dans les deux sens : le corps de réponse peut contenir n'importe quel
# octet, y compris des apostrophes et des retours ligne. On ne l'interpole
# jamais tel quel dans du SQL.
lire_cache_base() {
  local b
  b=$(psql_tac "select encode(convert_to(contenu,'UTF8'),'base64') from firecrawl_cache where cle='$1' and expire_le >= current_date") || return 1
  [ -n "$b" ] || return 1
  printf '%s' "$b" | tr -d '\n' | base64 -d 2>/dev/null
}

ecrire_cache_base() {  # cle endpoint requete contenu credits ttl
  local ko=$(( ${#4} / 1024 ))
  [ "$ko" -le "$CACHE_MAX_KO" ] || { err "fc.sh: réponse de ${ko} Ko > ${CACHE_MAX_KO} Ko — gardée en cache local seulement."; return 0; }
  local b64 f
  b64=$(printf '%s' "$4" | base64 | tr -d '\n')
  f=$(mktemp) || return 0
  # Passer par un fichier, pas par -c : un corps de plusieurs centaines de Ko
  # dépasserait la limite d'arguments du shell.
  printf "insert into firecrawl_cache (cle, endpoint, requete, contenu, octets, credits_payes, agent_origine, expire_le)
          values ('%s','%s','%s', convert_from(decode('%s','base64'),'UTF8'), %s, %s, '%s', current_date + %s)
          on conflict (cle) do update set contenu = excluded.contenu, octets = excluded.octets,
            credits_payes = excluded.credits_payes, expire_le = excluded.expire_le;\n" \
    "$1" "$(sql_lit "$2")" "$(sql_lit "$(printf '%s' "$3" | cut -c1-500)")" "$b64" "${#4}" "$5" "$(sql_lit "$AGENT")" "$6" > "$f"
  psql_file "$f" || err "fc.sh: mise en cache en base impossible (cache local conservé)"
  rm -f "$f"
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
sans_cle() {
  err "fc.sh: FIRECRAWL_API_KEY absent — Firecrawl indisponible, utilise WebSearch/WebFetch/curl."
  exit 4
}

if [ "$EP" = "solde" ]; then
  [ -n "${FIRECRAWL_API_KEY:-}" ] || sans_cle
  rapport; exit 0
fi

case "$EP" in
  search|map|scrape) ;;
  *) err "usage: fc.sh {search|map|scrape} '<json>'  |  fc.sh solde"; exit 2 ;;
esac

PAYLOAD="${2:-}"
printf '%s' "$PAYLOAD" | jq -e . >/dev/null 2>&1 || {
  err "fc.sh: payload JSON invalide. Rappel : les guillemets internes doivent être échappés, ou utilise un heredoc."
  exit 2
}
CLE_REQ=$(printf '%s' "$PAYLOAD" | jq -r '.query // .url // ""' 2>/dev/null)

# ------------------------------------------------------------------- cache
# Consulté AVANT tout garde-fou budgétaire : une réponse déjà payée ne coûte
# rien, n'entame ni le plafond du jour ni la réserve, et doit donc rester
# disponible même quand le budget est épuisé.
CLE=$(cle_cache "$EP" "$PAYLOAD")
if [ "${FC_NOCACHE:-0}" != "1" ]; then
  if CACHE=$(lire_cache_local "$CLE") && [ -n "$CACHE" ]; then
    err "fc.sh: $EP servi par le cache local — 0 crédit."
    journalise "$EP" "$CLE_REQ" 0 "" "cache-local" "" false ""
    printf '%s\n' "$CACHE"
    exit 0
  fi
  if CACHE=$(lire_cache_base "$CLE") && [ -n "$CACHE" ]; then
    err "fc.sh: $EP servi par le cache en base — 0 crédit."
    ecrire_cache_local "$CLE" "$CACHE" "$(ttl_cache "$EP")"
    psql_tac "update firecrawl_cache set hits = hits + 1, dernier_hit = now() where cle='$CLE'" >/dev/null
    journalise "$EP" "$CLE_REQ" 0 "" "cache-base" "" false ""
    printf '%s\n' "$CACHE"
    exit 0
  fi
fi

# ---------------------------------------------------------------- garde-fous
# La clé n'est exigée qu'ici : au-dessus, une réponse déjà en cache est déjà
# payée et doit rester lisible même clé absente ou révoquée (c'est arrivé le
# 26/08 : trois agents ont journalisé « Token missing » et perdu leur recours).
[ -n "${FIRECRAWL_API_KEY:-}" ] || sans_cle
COUT_MAX=$(bareme "$EP" "$PAYLOAD")
SOLDE_AVANT=$(solde) || SOLDE_AVANT=""

refuser() {
  err "fc.sh: REFUS — $1"
  err "fc.sh: ce n'est pas une panne. Continue avec WebSearch / WebFetch / curl."
  journalise "$EP" "$CLE_REQ" 0 "$SOLDE_AVANT" "refus" "" true "$1"
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
journalise "$EP" "$CLE_REQ" "$COUT" "$SOLDE_APRES" "$SRC" "$HTTP" false ""

if [ "$CURL_RC" -ne 0 ] || ! printf '%s' "$HTTP" | grep -q '^2'; then
  err "fc.sh: Firecrawl a répondu HTTP ${HTTP:-?} (coût compté : $COUT). Bascule sur WebSearch/WebFetch."
  printf '%s\n' "$CORPS" >&2
  exit 4
fi

TTL=$(ttl_cache "$EP")
ecrire_cache_local "$CLE" "$CORPS" "$TTL"
ecrire_cache_base "$CLE" "$EP" "$CLE_REQ" "$CORPS" "$COUT" "$TTL"

err "fc.sh: $EP ok — $COUT crédit(s) [$SRC], solde ${SOLDE_APRES:-?}, cumul du jour $(( ${CONSO_JOUR:-0} + COUT ))/$BUDGET_JOUR (en cache ${TTL} j)"
printf '%s\n' "$CORPS"
