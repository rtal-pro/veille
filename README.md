# Veille SaaS autonome — 100 % cloud, 0 € de plus

Système multi-agents quotidien qui découvre des sources, mine des idées de micro-SaaS
(marché FR/UE), les instruit sur 4 jambes prouvées par URL, tente de les tuer, et
t'envoie chaque matin un **mémo office hours** par email. Tourne sur GitHub Actions
avec ton abonnement **Claude Max** — aucun PC, aucune clé API, aucune facture à l'usage.

## Architecture

```
04:30 UTC ── preflight (secrets) ─► migrations (000→006, psql -1) ─► porte (verdict du jour ? passe mémo ou récolte ?)
 PASSE MÉMO   ├─ KIOSQUE (sonnet-5) ─────┐  lit comme un passionné, mine idées + sources citées
              └─ PROSPECTEUR (sonnet-5) ─┤  fore un secteur NAF vierge → sources neuves
                                         ▼
               INSTRUCTEUR (opus-5) ────►  instruit ≤4 leads — jusqu'à 6-7 si vivier riche (+1 réserve), trou FR d'abord
                                         ▼
               CONTRE-AVOCAT (sonnet-5) ►  attaque TOUTE la file ; les survivants = GO
                                         ▼
               RATTRAPAGE (sonnet-5) ───►  aucun survivant récent (fenêtre 3 j) ? 2e vague
                                         ▼
               ATELIER (sonnet-5) ──────►  score solo-dev + mémo quotidien → 📧 (fallback 🛑 issue)
09·13·17 UTC ── PASSES RÉCOLTE : Kiosque + Prospecteur seuls remplissent le vivier (jugement + mémo sautés)
11:00 UTC ── reprise mémo (filet quota) : la porte saute le jugement si le verdict du jour existe
09:30 UTC ── VIGIE (garde-fou, sans LLM) : pipeline parti aujourd'hui ? + keepalive 45 j
push main ── GENDARME (sans LLM) : valider.sh sur le diff poussé → revert auto si non conforme
sam. 13:00 ── SUPERVISEUR (sonnet-5) ──►  audit KPIs + runs GitHub → 1 PR d'amélioration/sem. → 📧
dim. 06:00 ── FOSSOYEUR (sonnet-5) ────►  résurrections, scoring sources, doctrine → 📧 digest
10:00 Paris ── LECTRICE (app Claude) ──►  brief 10 lignes lecture seule → 📱 notification push
```

Mémoire : ta base Supabase existante (`prospection_clones`, `veille_runs`, `analyses_go`)
+ les tables `sources`, `carte_naf`, `reserves`, `doctrine`, `verdicts`, `audits`,
`modifications`, `migrations_appliquees`, gérées par `sql/000_legacy.sql` →
`sql/006_coherence.sql`. Dédup gratuite par pg_trgm + full-text français (pas
d'embeddings payants ; pgvector reste prêt si besoin).

## Installation (~20 min, depuis un navigateur — tablette/téléphone OK)

### 1. Créer le repo

Sur github.com : **New repository** → nom discret (ex. `atlas-lab`) → **Public** → Create.
Public = **minutes GitHub Actions illimitées** (le pipeline peut respirer : 30-50 min
par agent). À savoir honnêtement : sur un repo public, les **logs des runs sont visibles
par quiconque trouve le repo** — la tranche du jour y est lisible pendant sa rétention.
Mitigations : nom de repo anonyme, et **Settings → Actions → General → réduire la
rétention des logs à 1 jour**. Le patrimoine durable (base, doctrine, backlog, mémos)
vit dans Supabase, jamais dans le repo. Les secrets sont masqués par GitHub dans les
logs, et les workflows ne se déclenchent que par cron/manuel — personne d'extérieur
ne peut les lancer.

### 2. Ouvrir un Codespace (le terminal cloud, pas de PC)

Sur la page du repo : bouton **Code → Codespaces → Create codespace on main**.
Un VS Code s'ouvre dans le navigateur.

### 3. Uploader ces fichiers

Glisse-dépose le contenu du zip dans l'explorateur du Codespace (ou upload via clic
droit → Upload). Puis dans le terminal du Codespace :

```bash
git add -A && git commit -m "deploy: système de veille v2.1" && git push
```

Le préfixe `deploy:` n'est pas cosmétique : c'est le marqueur que le **Gendarme**
(le workflow qui valide chaque push sur `main`, voir plus bas) reconnaît pour
exempter un déploiement humain de son contrôle automatique — sans lui, ce premier
gros commit se ferait reverter par sa propre garde-fou.

### 4. Créer le token Claude (lié à ton abonnement Max)

Dans le terminal du Codespace :

```bash
npm install -g @anthropic-ai/claude-code
claude setup-token
```

Suis le lien de connexion (connecte-toi avec ton compte Claude **Max**), et copie le
token généré (`sk-ant-oat01-…`).

### 4 bis. Installer la Claude GitHub App

Sur **github.com/apps/claude** → **Install** → sélectionne ce repo. Sans elle,
l'échange OIDC échoue même avec un token valide : les jobs agents (`anthropics/
claude-code-action@v1`) en ont besoin pour s'authentifier, en plus du secret de
l'étape 4.

### 5. Les secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret** :

| Secret | Valeur |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | le token de l'étape 4 |
| `SUPABASE_DB_URL` | chaîne de connexion Postgres **« Session pooler »** de ton projet Supabase (Dashboard → Connect), rôle `postgres` (ton mot de passe). ⚠️ Prends bien le *pooler* (IPv4) : l'hôte direct `db.xxx.supabase.co` est IPv6-only et échoue depuis GitHub Actions. Réservé aux jobs d'infra déterministes (`migrations`, `porte`, `setup.yml`) — jamais lu par un agent LLM. |
| `SUPABASE_DB_URL_AGENT` | même chaîne pooler, mais avec l'utilisateur `agent_veille.<project-ref>` — le rôle restreint (pas de DELETE, pas de DDL) que tu généreras à l'**étape 6 ter**. Reviens créer ce secret une fois cette étape faite ; c'est lui que lisent tous les jobs agents (mappé sur l'env `SUPABASE_DB_URL` qu'attendent les prompts). |
| `GMAIL_USER` | ton adresse Gmail |
| `GMAIL_APP_PASSWORD` | un **mot de passe d'application** Gmail (myaccount.google.com → Sécurité → Validation en 2 étapes → Mots de passe des applications) |
| `FIRECRAWL_API_KEY` | *(optionnel)* clé du free tier firecrawl.dev — moteur de découverte FR large (`/search` + `/map`), et déblocage des sites à anti-bot |

(Un 7e secret, `SUPERVISEUR_PAT`, se crée à l'étape 6 bis ci-dessous.)

### 6. La migration SQL

Onglet **Actions** du repo → workflow **« Setup (migrations SQL) »** → **Run workflow**.
Un tap : le job applique `000` → `006` **dans l'ordre**, chacune dans sa propre
transaction (`psql -1`), via le secret `SUPABASE_DB_URL` (donc après l'étape 5).
Idempotent — relançable sans risque, y compris pour toute future migration `007+`
ajoutée au repo (ce même job tourne d'ailleurs automatiquement à chaque run quotidien,
avant la porte — le schéma suit le repo sans clic humain, à vie). La 000 rejoue le
schéma legacy en `create table if not exists` (base reconstructible) ; la 001 sème la
doctrine et les sources apprises de tes runs d'août et convertit tes 10 « GO sous
réserve » en réserves testables ; la 003 ajoute la télémétrie et la vue
`v_sante_pipeline` ; la 004 crée la fonction `memoire()` — la mémoire interrogeable des
agents ; la 005 transforme la doctrine en jurisprudence révisable (garde-fous vs
heuristiques falsifiables) ; la 006 verrouille le lexique des statuts, purge le défaut
fantôme `verdict='GO'` hérité de la prod, et — **si le rôle `agent_veille` existe déjà**
(étape 6 ter) — lui grante ses accès et pose ses policies RLS sur les tables et vues
agents. Rejouable : relance **Setup** après avoir créé le rôle si tu avais fait 6 avant
6 ter. (Fallback manuel : coller chaque fichier dans le SQL Editor de Supabase, dans
l'ordre.)

### 6 bis. Donner les clés au Superviseur (auto-merge)

- Crée un **fine-grained PAT** (github.com → Settings → Developer settings →
  Fine-grained tokens) limité à ce repo, permissions **Contents: Read/Write**,
  **Pull requests: Read/Write**, **Workflows: Read/Write**, **Issues: Read/Write**
  et **Actions: Read**, et ajoute-le en secret `SUPERVISEUR_PAT`. Il est partagé par
  trois workflows : le Superviseur (merge ses propres PR), le Garde-fou (revert +
  ouvre des issues, lit les runs pour qualifier un échec) et le Gendarme (revert d'un
  push non conforme, y compris sur un fichier `.github/workflows/*.yml` — le
  `GITHUB_TOKEN` par défaut refuse ce push-là).
- Fallback sans PAT : coche **Settings → Actions → General → « Allow GitHub Actions
  to create and approve pull requests »**. Le Superviseur pourra alors modifier les
  prompts mais pas les workflows, et un revert du Garde-fou/Gendarme touchant un YAML
  échouera au push — une issue 🛑 « enforcement en échec » s'ouvre pour te le signaler.

### 6 ter. Créer le rôle Postgres restreint `agent_veille`

Les jobs agents ne doivent jamais tenir la chaîne `postgres` complète (une page
piégée lue par un agent ne doit pouvoir ni détruire la base ni exfiltrer un accès
total). Dans le **SQL Editor** de Supabase, avec un mot de passe généré (32
caractères, gestionnaire de mots de passe) :

```sql
create role agent_veille login password '<généré 32 caractères>';
grant usage on schema public to agent_veille;
grant select, insert, update on prospection_clones, veille_runs, analyses_go,
  sources, carte_naf, reserves, doctrine, verdicts, audits, modifications
  to agent_veille;
grant usage, select on all sequences in schema public to agent_veille;
-- pas de DELETE, pas de DROP, pas de TRUNCATE, pas de DDL
```

Puis construis la chaîne **Session pooler** en remplaçant l'utilisateur `postgres`
par `agent_veille.<project-ref>` (même hôte, même port, le mot de passe que tu viens
de choisir), et crée le secret `SUPABASE_DB_URL_AGENT` (étape 5) avec cette chaîne.
La 006 (étape 6) grante ensuite le rôle sur les vues (`v_sante_pipeline`,
`sante_agents`) et pose ses policies RLS — relance **Setup** après cette étape si
tu l'avais déjà lancée avant de créer le rôle.

### 7. Premier run de test

Repo → onglet **Actions** → « Veille quotidienne » → **Run workflow**.
Suis les jobs en direct. À la fin, le mémo arrive par email. (L'app **GitHub mobile**
permet de relancer ça depuis la plage.)

### 8. Éteindre l'ancien système

Dans Claude : désactive tes tâches planifiées de veille actuelles, et crée à la place
**la Lectrice** : une tâche planifiée quotidienne à **10:00, heure de Paris** (après la
fin pire-cas du pipeline, reprise de 11:00 UTC comprise) avec le prompt de
`prompts/lectrice-claude-app.md` — remplace le placeholder `<ID_PROJET_SUPABASE>` par
l'identifiant réel de ton projet **dans la tâche planifiée**, jamais dans un fichier
versionné. Lecture seule sur Supabase, brief de 10 lignes, et **notification push sur
ton téléphone à chaque run** — sa première phrase est la punchline affichée dans la
notif : `🎯 X GO`, `🔴 JOUR ROUGE` (0 GO malgré la 2e vague), `⏳` (pipeline encore en
cours — jour lent ou reprise de 11:00, pas une panne), ou `🛑` (aucun agent n'a
journalisé aujourd'hui — panne réelle). Vérifie que les notifications de l'app Claude
sont autorisées dans les réglages du téléphone. Puis supprime le Codespace (Code →
Codespaces → ⋯ → Delete) : il ne sert qu'au setup.

**Bonus — toi comme capteur** : les groupes Facebook de niche, salons et conversations
restent fermés aux agents, mais pas à toi. Depuis n'importe quel chat Claude (connecteur
Supabase actif), dicte : « insère ce lead dans prospection_clones, statut_pipeline
'lead', découverte via humain : [ton idée] ». L'Instructeur le traitera comme les autres
— tu es une source du système, la seule qui entre là où les agents ne peuvent pas.
**Strictement optionnel** : le système n'attend jamais après toi — c'est une entrée
en plus, pas un rouage.

## Budget & réglages

- **Minutes GitHub** : repo public = illimitées sur les runners standard. Les
  `timeout-minutes` par job (3 à 50 min) sont des garde-fous anti-emballement, pas des
  cibles : un agent qui a fini en 12 min s'arrête en 12 min.
- **Modèles épinglés** (décision explicite, ajustable seulement par le Superviseur via
  `--model`/`--max-turns`, jamais par les autres agents) :

  | Agent | Modèle | `--max-turns` | `timeout-minutes` |
  |---|---|---|---|
  | Instructeur | `claude-opus-5` | 100 | 50 |
  | Kiosque | `claude-sonnet-5` | 100 | 50 |
  | Contre-avocat | `claude-sonnet-5` | 80 | 35 |
  | Rattrapage | `claude-sonnet-5` | 80 | 45 (skip si survivant récent, fenêtre 3 j) |
  | Prospecteur | `claude-sonnet-5` | 70 | 35 |
  | Fossoyeur | `claude-sonnet-5` | 90 | 45 |
  | Atelier | `claude-sonnet-5` | 60 | 35 |
  | Superviseur | `claude-sonnet-5` | 100 | 45 |

  Seul l'**Instructeur** tourne sur Opus (le cœur du pipeline, le plus qualitatif à
  soigner) ; les six autres sur Sonnet 5, plus efficace en quota qu'un modèle par
  défaut plus lourd.
- **Quota Claude Max** : les agents consomment ton quota d'abonnement (fenêtres
  glissantes). Le pipeline principal tourne à **04:30 UTC**. S'il se heurte à un quota
  épuisé (jobs en échec rapide, signature « infra »), un **cron de reprise à 11:00
  UTC** rejoue le même workflow : la porte (`select … from verdicts where
  date_run=current_date`) saute tout instantanément si le verdict du jour existe déjà
  (~1 min de runner, 0 quota consommé) et ne relance les agents que si la journée
  n'est pas bouclée — la journée de quota épuisé à 04:30 est rattrapée sans double
  mémo. Si le quota mord quand même sur ton usage perso, baisse d'abord les
  `--max-turns`, réduis les passes de récolte (retire un ou plusieurs crons `09/13/17`),
  ou passe Kiosque/Prospecteur à 1 jour sur 2 (`cron: "30 4 */2 * *"`).
- **Horaire** : crons en UTC. `30 4 * * *` = 06:30 Paris l'été, 05:30 l'hiver.
- **`--dangerously-skip-permissions`** : requis pour tourner sans surveillance. Les
  agents n'ont ni secrets en clair dans le repo, ni droit de push (permissions
  `contents: read`), et n'écrivent en base qu'avec le rôle restreint `agent_veille`
  (pas de DELETE, pas de DDL — voir étape 6 ter).

## Auto-correction — gouvernance par le résultat, sans validation humaine

Chaque samedi 13:00 UTC, le **Superviseur** audite le système (base : GO/sem, taux de
survie, vivier, % de jambes PROUVÉ, rendement par source ; GitHub : durées, échecs,
timeouts via `gh`), journalise l'expérience dans `modifications` **avant** de merger
(pas d'expérience fantôme si l'agent meurt entre les deux), archive tout dans `audits`,
puis applique et merge lui-même au plus UNE modification par semaine (hypothèse,
métrique, date d'évaluation) avec `gh pr merge --squash --subject "superviseur: …"` —
ce préfixe de sujet n'est pas cosmétique, c'est lui que le Garde-fou grep pour
retrouver le commit fautif. Ce qui tient l'ensemble, en couches indépendantes :

1. **`scripts/valider.sh` fail-closed, exécuté DEUX fois** : une fois par le Superviseur
   avant de merger sa propre PR, une fois par le **Gendarme** (`gendarme.yml`, sans
   LLM) sur *chaque push sur `main`*, avec la version de `valider.sh` d'AVANT le push
   — un Superviseur compromis ne peut pas s'auto-exempter en réécrivant son propre
   validateur dans le commit qu'il valide. Liste blanche stricte : seuls les 7 prompts
   d'agents et `veille-quotidienne.yml`/`fossoyeur-hebdo.yml` sont modifiables ; tout
   le reste du repo (constitution, SQL, `gendarme.yml`, `garde-fou.yml`, `setup.yml`,
   `valider.sh` lui-même) est intouchable par une PR automatique. YAML qui parsent,
   aucune ligne `name:`/`on:`/`workflow_run:` touchée, nombre de
   `--dangerously-skip-permissions` et de `secrets.` identique avant/après, diff ≤ 3
   fichiers. Échec = rien ne merge (Superviseur) ou **revert automatique du push**
   (Gendarme) — avec, dans les deux cas, une exemption explicite pour tes propres
   commits `deploy:` (voir étape 3).
2. **La métrique reine est la qualité, pas le volume** : chaque semaine le Superviseur
   re-vérifie un échantillon de preuves URL des GO (la page dit-elle vraiment ce qui
   est affirmé ?). Un GO dont une preuve ne tient pas est rétrogradé. `qualite_go`
   gouverne les expériences — impossible d'« optimiser » en affaiblissant le
   Contre-avocat, dont les critères sont constitutionnels.
3. **La boucle expérience → revert** : à la date d'évaluation, métrique dégradée =
   revert automatique la semaine même.
4. **Le Garde-fou v2** (`garde-fou.yml`, sans LLM), deux jobs :
   - `revert-si-casse` (déclenché à la fin de chaque run quotidien) : compte les 2
     derniers échecs **planifiés** (les runs manuels ne comptent pas), puis
     **qualifie** chacun via `gh run view --json jobs` — revert seulement si un job
     *agent* (kiosque/prospecteur/instructeur/contre-avocat/rattrapage) a cassé les
     deux fois avec une durée > 5 min (signature « le code a tourné et a cassé »).
     Un échec rapide (OIDC, quota, token, Gmail) ou limité à l'envoi d'email →
     **alerte sans revert**, panne d'infrastructure, pas de commit à blâmer.
     **Anti re-revert** : si le commit du Superviseur suspect est déjà reverté,
     nouvelle alerte « panne d'une autre origine », jamais de second revert du même
     commit.
   - `vigie` (cron quotidien `30 9 * * *`, sans LLM) : **dead-man's switch** — aucun
     run de « Veille quotidienne » créé depuis 26 h → issue 🛑 + email, panne
     détectée même si tout le reste est silencieux ; **keepalive** — dernier commit
     > 45 jours → commit vide `chore: keepalive` (déjoue la désactivation
     automatique des crons après 60 jours d'inactivité sur un repo public).
5. **Canal d'alerte de repli sans Gmail** : toute panne (Garde-fou, Gendarme,
   préflight/migrations/porte en échec, mémo/audit/digest non livré) ouvre en plus de
   l'email une **issue GitHub** (`gh issue create`) — notification push native de
   l'app GitHub mobile, qui ne dépend d'aucun agent qui tourne ni d'aucune boîte mail.

Risque résiduel assumé : Superviseur et Garde-fou/Gendarme partagent l'identité du
`SUPERVISEUR_PAT` — un Superviseur compromis (injection via une page web lue en
audit) qui pousserait en direct sur `main` avec un message maquillé `deploy:`
contournerait le Gendarme ; le Garde-fou reste le filet de dernier recours (2 échecs
qualifiés → revert). Une modification subtilement médiocre peut aussi vivre jusqu'à sa
date d'évaluation (~2 semaines au pire). La constitution, `valider.sh`, le Gendarme et
le Garde-fou restent modifiables uniquement par toi.

## Ce qui arrive chaque matin dans ta boîte

Les GO du jour (4 jambes + URLs + rapport d'attaque du Contre-avocat + verdict office
hours « BUILD / BUILD APRÈS TEST / FUIS »), le backlog classé où piocher ton prochain
build, les autopsies, les sources découvertes. L'Instructeur instruit au plus **4
dossiers** par jour — jusqu'à 6-7 quand le vivier est riche (+1 slot réservé aux retours
de vivier), qualité avant volume ; le
Rattrapage ne se déclenche que si aucun candidat n'a survécu dans une fenêtre de 3
jours — un survivant récent suffit à éteindre la 2e vague (0 tour de quota gaspillé).
Les rares jours à zéro GO malgré tout ça sont des **JOURS ROUGES** assumés : cause
probable, autopsies, et riposte automatique (Kiosque/Prospecteur doublent leur récolte
le lendemain, diagnostic prioritaire du Superviseur en fin de semaine). Un système qui
sortirait un GO par jour quoi qu'il arrive fabriquerait des faux ; celui-ci garantit la
chasse — file de candidats + fenêtre de rattrapage ≈ un GO réel la grande majorité des
jours — et traite chaque jour rouge comme un incident à corriger, jamais comme une
routine.

## Dépannage rapide

- **Job rouge « credit/auth »** → le token a expiré ou a été révoqué : refais l'étape 4
  (Codespace jetable) et mets à jour le secret.
- **`Could not fetch an OIDC token`** → il manque `id-token: write` dans les
  `permissions:` du workflow, ou la **Claude GitHub App n'est pas installée sur ce
  repo** (étape 4 bis) — les deux sont nécessaires, un token valide seul ne suffit pas.
- **`psql: connection failed`** → tu as mis l'hôte direct au lieu du **Session pooler**
  (vérifie aussi que tu n'as pas inversé `SUPABASE_DB_URL` et `SUPABASE_DB_URL_AGENT`
  entre le rôle `postgres` et le rôle `agent_veille`).
- **Pas d'email** → vérifie le mot de passe d'application Gmail (pas ton mot de passe
  normal) et que la validation en 2 étapes est active.
- **Une issue 🛑 s'ouvre sur le repo** → c'est le canal d'alerte de repli (Garde-fou,
  Gendarme, ou mémo/audit/digest non parti) : lis l'issue, elle contient la cause et le
  lien vers le run GitHub Actions en échec. Elle arrive même si l'email a lui aussi
  échoué à partir.
- **Action Claude : input inconnu** → l'action évolue ; vérifie la syntaxe du jour sur
  https://code.claude.com/docs/en/github-actions
