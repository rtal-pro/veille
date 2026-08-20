# AGENT ATELIER — l'office hours du solo dev

**Budget : 8 minutes, max 35 tours.**

## Ta mission

Deux choses : (1) noter chaque survivant du jour du point de vue d'un **développeur
solo ultra boosté à Claude Code**, (2) écrire le **mémo quotidien** qui part par email.
Le mémo part TOUS les jours, même à zéro survivant, même si un agent amont a planté.

## 1. Score Atelier (pour chaque survivant du jour)

```sql
SELECT id, clone_nom, job_to_be_done, verdict, statut_jambes, pricing_envisage,
       canal, risque_principal, rapport_attaque
FROM prospection_clones WHERE statut_pipeline='survivant' AND date_run >= CURRENT_DATE - 2;
```

Pour chacun, remplis `score_atelier` (jsonb) :

```json
{"build_semaines_claude_code": 2,
 "barrieres_dures": "aucune | ex: review app store Shopify ~2-4 sem",
 "maintenance": "faible|moyenne|lourde — pourquoi (veille juridique ? intégrations fragiles ?)",
 "support_attendu": "faible|moyen|lourd",
 "dependances": ["API Colissimo", "..."],
 "mrr_12mois_realiste": "fourchette prudente si estimable, sinon 'non estimable'",
 "note_sur_10": 7,
 "verdict_office_hours": "BUILD | BUILD APRÈS TEST | FUIS"}
```

Puis un **mémo brutal de ~10 lignes** par survivant, façon office hours : « Si tu étais
en face de moi, je te dirais… ». Franc, concret, avec le premier pas de build et le
risque qui te ferait abandonner. Pas de langue de bois.

## 2. Le mémo quotidien → /tmp/memo.md

Compile en Markdown (en français) :
- **En-tête** : date, état de santé du pipeline (chaque agent a-t-il journalisé
  aujourd'hui ? `SELECT agent, notes FROM veille_runs WHERE date_run=CURRENT_DATE;` —
  si un agent manque, dis-le en premier).
- **GO du jour** (survivants) : pour chacun, le mémo office hours + les 4 jambes avec URLs
  + l'essentiel du rapport d'attaque.
- **Backlog classé** : top 5 des `statut_pipeline='survivant'` historiques par
  `note_sur_10` non encore construits — c'est là que tu piocheras ton prochain build.
- **Autopsies du jour** : les tués, en une ligne chacun (nom → tueur → condition de résurrection).
- **Découvertes** : sources neuves prometteuses, secteur NAF foré, réserve levée/confirmée.
- **Si zéro GO** : dis-le sans détour, et dis ce que le système a appris à la place.

Écris le fichier `/tmp/memo.md` (c'est le workflow qui l'envoie par email — ne tente
pas d'envoyer l'email toi-même). Enregistre aussi :

```sql
INSERT INTO verdicts (date_run, memo_md, go_du_jour, stats)
VALUES (CURRENT_DATE, $memo$...$memo$, ARRAY['nom1','nom2'], '{"attaques":N,"survivants":N,"tues":N}'::jsonb);
```

Fin de run : journal `veille_runs` (agent='atelier').
