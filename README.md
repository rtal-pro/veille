# Veille SaaS autonome — 100 % cloud, 0 € de plus

Système multi-agents quotidien qui découvre des sources, mine des idées de micro-SaaS
(marché FR/UE), les instruit sur 4 jambes prouvées par URL, tente de les tuer, et
t'envoie chaque matin un **mémo office hours** par email. Tourne sur GitHub Actions
avec ton abonnement **Claude Max** — aucun PC, aucune clé API, aucune facture à l'usage.

## Architecture

```
04:30 UTC ─┬─ KIOSQUE ────────┐  lit comme un passionné, mine idées + sources citées
           └─ PROSPECTEUR ────┤  fore un secteur NAF vierge → sources neuves
                              ▼
               INSTRUCTEUR ───►  instruit ≤5 leads (trou FR d'abord) + 1 réserve
                              ▼
               CONTRE-AVOCAT ─►  attaque TOUTE la file ; les survivants = GO
                              ▼
               ATELIER ───────►  score solo-dev + mémo quotidien → 📧 email
dim. 06:00 ──  FOSSOYEUR ─────►  résurrections, scoring sources, doctrine → 📧 digest
```

Mémoire : ta base Supabase existante (`prospection_clones`, `veille_runs`) + nouvelles
tables `sources`, `carte_naf`, `reserves`, `doctrine`, `verdicts`. Dédup gratuite par
pg_trgm + full-text français (pas d'embeddings payants ; pgvector reste prêt si besoin).

## Installation (~20 min, depuis un navigateur — tablette/téléphone OK)

### 1. Créer le repo

Sur github.com : **New repository** → nom `veille-saas` → **Private** → Create.
(Privé = tes idées restent confidentielles. Quota gratuit privé : 2 000 min/mois ;
le pipeline est calibré ~55-70 min/jour max, donc ça passe — voir « Budget » plus bas.)

### 2. Ouvrir un Codespace (le terminal cloud, pas de PC)

Sur la page du repo : bouton **Code → Codespaces → Create codespace on main**.
Un VS Code s'ouvre dans le navigateur.

### 3. Uploader ces fichiers

Glisse-dépose le contenu du zip dans l'explorateur du Codespace (ou upload via clic
droit → Upload). Puis dans le terminal du Codespace :

```bash
git add -A && git commit -m "Système de veille v1" && git push
```

### 4. Créer le token Claude (lié à ton abonnement Max)

Dans le terminal du Codespace :

```bash
npm install -g @anthropic-ai/claude-code
claude setup-token
```

Suis le lien de connexion (connecte-toi avec ton compte Claude **Max**), et copie le
token généré (`sk-ant-oat01-…`).

### 5. Les secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret** :

| Secret | Valeur |
|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | le token de l'étape 4 |
| `SUPABASE_DB_URL` | chaîne de connexion Postgres **« Session pooler »** de ton projet Supabase (Dashboard → Connect). ⚠️ Prends bien le *pooler* (IPv4) : l'hôte direct `db.xxx.supabase.co` est IPv6-only et échoue depuis GitHub Actions. |
| `GMAIL_USER` | ton adresse Gmail |
| `GMAIL_APP_PASSWORD` | un **mot de passe d'application** Gmail (myaccount.google.com → Sécurité → Validation en 2 étapes → Mots de passe des applications) |
| `FIRECRAWL_API_KEY` | *(optionnel)* clé du free tier firecrawl.dev, pour les sites à anti-bot |

### 6. La migration SQL

Supabase Dashboard → **SQL Editor** → colle le contenu de `sql/001_init.sql` → Run.
(Idempotente, ré-exécutable. Elle sème aussi la doctrine et les sources apprises de
tes runs d'août, et convertit tes 10 « GO sous réserve » en réserves testables.)

### 7. Premier run de test

Repo → onglet **Actions** → « Veille quotidienne » → **Run workflow**.
Suis les jobs en direct. À la fin, le mémo arrive par email. (L'app **GitHub mobile**
permet de relancer ça depuis la plage.)

### 8. Éteindre l'ancien système

Dans Claude : désactive tes tâches planifiées de veille actuelles — sauf si tu veux en
garder UNE comme « lectrice » qui interroge Supabase et te briefe en conversation.
Puis supprime le Codespace (Code → Codespaces → ⋯ → Delete) : il ne sert qu'au setup.

## Budget & réglages

- **Minutes GitHub** (plan gratuit, repo privé : 2 000 min/mois). Pipeline calibré par
  des `timeout-minutes` stricts : ~55-70 min/jour grand max, généralement bien moins.
  Si tu t'approches de la limite (Settings → Billing) : passe kiosque/prospecteur à
  1 jour sur 2 (`cron: "30 4 */2 * *"`), ou repo public (minutes illimitées — mais
  workflows visibles ; les idées restent dans Supabase, pas dans le repo).
- **Quota Claude Max 20** : les agents consomment ton quota d'abonnement (fenêtres
  glissantes). Le pipeline tourne à 04:30 UTC pour ne pas mordre sur ton usage de la
  journée. Kiosque/Prospecteur/Fossoyeur tournent sur Sonnet (léger), Instructeur/
  Contre-avocat/Atelier sur le modèle par défaut. Ajustable via `--model` dans les YAML.
- **Horaire** : crons en UTC. `30 4 * * *` = 06:30 Paris l'été, 05:30 l'hiver.
- **`--dangerously-skip-permissions`** : requis pour tourner sans surveillance. Les
  agents n'ont ni secrets en clair dans le repo, ni droit de push (permissions
  `contents: read`), et n'écrivent que dans Supabase.

## Ce qui arrive chaque matin dans ta boîte

Les GO du jour (4 jambes + URLs + rapport d'attaque du Contre-avocat + verdict office
hours « BUILD / BUILD APRÈS TEST / FUIS »), le backlog classé où piocher ton prochain
build, les autopsies, les sources découvertes — et les jours à zéro GO, la vérité et
ce que le système a appris à la place. Un système qui sortirait un GO par jour quoi
qu'il arrive fabriquerait des faux : ici la garantie, c'est le mémo, et un entonnoir
qui s'élargit tout seul.

## Dépannage rapide

- **Job rouge « credit/auth »** → le token a expiré ou a été révoqué : refais l'étape 4
  (Codespace jetable) et mets à jour le secret.
- **`psql: connection failed`** → tu as mis l'hôte direct au lieu du **Session pooler**.
- **Pas d'email** → vérifie le mot de passe d'application Gmail (pas ton mot de passe
  normal) et que la validation en 2 étapes est active.
- **Action Claude : input inconnu** → l'action évolue ; vérifie la syntaxe du jour sur
  https://code.claude.com/docs/en/github-actions
