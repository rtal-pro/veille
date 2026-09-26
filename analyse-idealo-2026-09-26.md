# Analyse — idealo (comparateur de prix) : que copier, que laisser

*26/09/2026 — fiche d'étude, pas de code. Légende : **[PROUVÉ]** = chiffre/fait lu dans une
source citée ; **[PROBABLE]** = déduction de ma part ; **[INCONNU]** = non vérifié.*

> Limite de méthode : idealo.fr, solutions.idealo.com et Wikipedia sont bloqués par le proxy
> de cet environnement. Tout ce qui suit vient d'extraits de moteur de recherche, pas d'une
> lecture directe des pages. Les chiffres d'audience/offres divergent selon les sources :
> je les donne tels quels, avec leur source, sans les réconcilier.

## 1. Ce qu'est idealo

- Comparateur de prix de produits de consommation, société **idealo internet GmbH** (Berlin),
  détenue majoritairement par **Axel Springer** (74,9 % depuis juillet 2006). **[PROUVÉ]** [1][2]
- Présent en Allemagne (marché principal) et en France (idealo.fr), entre autres. idealo.fr
  est classé n° 1 de la catégorie « comparaison des prix » en France (Similarweb, juillet
  2026). **[PROUVÉ]** [3]
- Ordres de grandeur annoncés — **incohérents entre sources** :
  - marchands : 14 200 boutiques (fiche App Store) vs « 50 000+ » (plusieurs sources) ;
  - offres : 144 M (App Store) vs 330 M vs 600 M ; ~3,8 M produits, ~1,5 Md de listings ;
  - trafic : ~5 M visites/mois en France ; 96 M visiteurs uniques/mois au global.
  **[PROUVÉ que ces chiffres sont publiés ; aucun n'est vérifié]** [2][3][4][5]
- CA : fourchette 100–250 M$ selon un agrégateur (LeadIQ). **[PROUVÉ publié, fiabilité faible]** [2]

## 2. Le modèle économique

| Levier | Détail | Statut |
|---|---|---|
| **CPC marchand** | Le marchand intègre son flux gratuitement, puis paie chaque clic qui renvoie un visiteur vers sa boutique. | [PROUVÉ] [1][6] |
| Tarif standard DE | 0,51 € le clic depuis le 01/04/2025 (nouveaux contrats) ; +0,02 €/an à chaque date anniversaire ; certaines catégories ont leur propre CPC. | [PROUVÉ] [1][6] |
| Plancher | 20 € HT minimum par mois **et par offre** (formulation de la page tarifs), même si les clics facturés sont inférieurs. | [PROUVÉ] [6] |
| Tarif FR | Page `partner.idealo.com/fr/prix` existe, montant non lisible dans les extraits. | [INCONNU] [6] |
| Retail media | idealo vend aussi de la publicité/visibilité aux marques (« idealo Solutions — Digital Commerce & Retail Media »). | [PROUVÉ que l'offre existe ; poids dans le CA inconnu] [7] |
| Checkout intégré | Un achat direct sur idealo a existé côté DE ; les extraits trouvés ne le confirment pas pour 2026. | [INCONNU] |

**Lecture** [PROBABLE] : c'est une place de marché d'audience. La valeur ne vient pas du
logiciel mais de deux actifs qui se nourrissent : le trafic acheteur (SEO produit + appli +
marque) et le catalogue de flux marchands normalisés. Le marchand paie parce que le trafic
est là ; le trafic vient parce que le catalogue est exhaustif.

## 3. Fonctionnalités côté acheteur (à reproduire en priorité si clone)

**[PROUVÉ]** d'après les fiches App Store / Play Store et les pages d'aide [4][8] :

1. **Recherche + arborescence de catégories** (high-tech, maison/jardin, sport, puériculture,
   parapharmacie…).
2. **Fiche produit unifiée** : un produit canonique (EAN/référence) regroupant N offres
   marchandes, triées par prix total (prix + livraison), avec fiche technique, images, avis.
3. **Historique de prix** (courbe du prix le plus bas dans le temps).
4. **Alerte prix** (email / push quand un seuil est atteint).
5. **Favoris / listes**.
6. **Bons plans / « deals »** mis en avant.
7. **Appli mobile** (iOS/Android) avec scan.

## 4. Côté technique (ce qui rend la copie difficile)

- Stack annoncée dans leurs offres d'emploi : **Kotlin/Java, TypeScript/React, NestJS, Kafka,
  AWS + Terraform, PostgreSQL/MySQL**. **[PROUVÉ]** [9]
- **Le cœur dur = le matching produit** : rapprocher des millions de lignes de flux
  hétérogènes (CSV/API marchands) vers un produit canonique. idealo combine logique floue,
  matching automatique par IA **et de grandes équipes humaines de contrôle qualité**
  (équipe « Product Enrichment » dédiée). **[PROUVÉ]** [9]
- Ingestion : flux CSV ou API fournis par les marchands, rafraîchis en continu (Kafka
  → **[PROBABLE]** pipeline événementiel de mise à jour des prix/stocks).

## 5. Le contexte concurrentiel — pourquoi le marché généraliste est fermé

- **Google Shopping** occupe le haut des SERP. En novembre 2025, le tribunal régional de
  Berlin a condamné Google à verser **465 M€** à idealo (374 M€ de dommages + 91 M€
  d'intérêts ; idealo en réclamait 3,3 Md€) pour auto-favoritisme de Google Shopping,
  dans la suite de la décision de la Commission européenne de 2017 confirmée en 2024.
  **[PROUVÉ]** [10][11]
- Le même contexte a tué plusieurs comparateurs FR (Achetez Facile, Price Runner France…) ;
  survivants : **Kelkoo**, **leDénicheur** (groupe Leboncoin), Google Shopping, idealo.
  **[PROUVÉ]** [12]
- Depuis la décision UE, des comparateurs tiers peuvent diffuser des annonces dans les
  emplacements Shopping en tant que **CSS** (Comparison Shopping Service partner). **[PROUVÉ]** [12]

**Conclusion [PROBABLE]** : copier idealo *en généraliste* face à idealo, Google, Kelkoo et
leDénicheur n'a pas de chemin crédible pour un solo-dev. Le moat est le couple trafic ×
catalogue, pas le code ; il faut 10–20 ans de SEO et des équipes de matching.

## 6. Ce qu'un solo-dev peut réellement copier

Toujours **[PROBABLE]** — hypothèses à instruire, pas des conclusions :

1. **Comparateur vertical de niche** où le matching est trivial (référence unique fiable)
   et où idealo est faible : pièces détachées par référence OEM, consommables (cartouches,
   filtres, ampoules par culot), composants PC d'occasion, matériel pro (outillage,
   fournitures dentaires/labo), produits B2B absents des comparateurs grand public.
   Critère : le catalogue tient en < 50 000 références et 20–200 marchands.
2. **Monétisation en affiliation** (Awin, Effiliation, Amazon Partenaires) plutôt qu'en CPC
   direct : aucun commercial à embaucher au démarrage, les marchands n'ont rien à signer.
3. **Briques idealo reproductibles à faible coût** : historique de prix + alerte prix
   (c'est ce que font déjà Keepa/CamelCamelCamel sur Amazon seul), fiche produit
   agrégée, pages SEO « meilleur prix <référence> ».
4. **Stack minimale** : ingestion des flux d'affiliation (CSV/XML) en cron → Postgres
   (on a déjà Supabase + pg_trgm pour le rapprochement flou) → site statique/SSR indexable
   → alertes par email.
5. **Ce qu'il ne faut pas copier** : la marque, le logo, la charte, les textes et les
   données d'idealo (CGU + droit des bases de données ; le site est de toute façon
   protégé par anti-bot).

### Tests d'absorption à lancer avant d'écrire une ligne

- Pour la niche choisie : idealo.fr / leDénicheur / Google Shopping couvrent-ils déjà ces
  références avec ≥ 3 offres par produit ? Si oui → mort.
- Existe-t-il ≥ 10 marchands FR de la niche présents sur un réseau d'affiliation ?
- Volume de recherche mensuel sur « prix + référence » dans la niche.

Ces trois tests collent au format « 4 jambes prouvées par URL » de l'Instructeur : la fiche
peut être passée telle quelle comme lead au pipeline.

## Sources

1. [idealo Listing — Costs & Conditions (CPC Pricing)](https://solutions.idealo.com/idealo-listing/costs-conditions) · [partner.idealo.com — Pricing (UK)](https://partner.idealo.com/partner-idealo-com/uk/pricing)
2. [LeadIQ — idealo internet GmbH](https://leadiq.com/c/idealo-internet-gmbh/5a1d7e18240000240057dde2) · [Wikipedia — Idealo](https://en.wikipedia.org/wiki/Idealo)
3. [Similarweb — idealo.fr (juillet 2026)](https://www.similarweb.com/fr/website/idealo.fr/)
4. [App Store — idealo comparateur de prix](https://apps.apple.com/ml/app/idealo-comparateur-de-prix/id454415640?l=fr-FR) · [Google Play — idealo](https://play.google.com/store/apps/details?id=de.idealo.android&hl=en_US)
5. [Forbes France — idealo, leader des comparateurs](https://www.forbes.fr/brandvoice/idealo-le-leader-des-comparateurs-de-prix-et-des-guides-dachat/) · [Dolum — découverte d'idealo](https://www.dolum.fr/finance/idealo-comparateur-prix/)
6. [partner.idealo.com — Prix (FR)](https://partner.idealo.com/fr/prix)
7. [idealo Solutions — Retail Media](https://solutions.idealo.com/)
8. [DataFeedWatch — Selling on idealo](https://www.datafeedwatch.com/blog/your-guide-to-selling-on-idealo)
9. [idealo jobs — Backend Kotlin/AWS/Kafka](https://jobs.idealo.com/o/senior-backend-engineer-mwd-javakotlin-aws-kafka) · [idealo jobs — Product Enrichment (NestJS/React/AWS)](https://jobs.idealo.com/o/full-stack-engineer-nestjsreactaws-product-enrichment-mwd?lang=en)
10. [TechCrunch — Google must pay €572M (idealo + Producto)](https://techcrunch.com/2025/11/14/german-court-rules-google-must-pay-e572m-for-violating-antitrust-rules-in-price-comparison-sector/)
11. [Kluwer Competition Law Blog — Google Shopping v. Idealo](https://legalblogs.wolterskluwer.com/competition-blog/google-shopping-v-idealo-the-largest-damages-award-in-competition-law-history-by-a-german-court-commentary-on-the-judgment-of-the-berlin-ii-regional-court-dated-november-13-2025-16-o-19519-kart-2/)
12. [iProspect — Google Shopping s'ouvre aux comparateurs concurrents](https://iprospect.com/fr/fr/publications/le-blog/google-shopping-concurrence) · [Dropizi — Top comparateurs 2026](https://www.dropizi.fr/blog/comparateur-prix)

---

## 7. Recherche de niche (26/09/2026) : 15 niches passées aux 3 tests

Méthode : 3 recherches parallèles, WebSearch uniquement. idealo.fr était inaccessible
partout : sa couverture reste **[INCONNU]** pour toutes les niches. Aucun volume de
mots-clés public n'a été trouvé : **[INCONNU]** partout. La base de la veille (`prospection_clones`)
ne contenait aucun comparateur grand public déjà instruit.

| Niche | T1 absorption | T2 offre / affiliation | Verdict |
|---|---|---|---|
| Pièces auto (réf. OEM) | MagicParts, Vos-Pièces-Auto, La Bonne Réf [PROUVÉ] | Oscaro 6-8 %, Autodoc 4-8 % | **MORT** |
| Pièces moto | mes-pieces-moto, achatmoinscher [PROUVÉ] | Motoblouz ~4 % | **MORT** |
| Motoculture | Sparepilot : 480 k pièces, références croisées OEM [PROUVÉ] | ≥10 marchands | **MORT** |
| Fournitures dentaires | Coompy, Comparapex (abonnement), ComparaDent, DentalHub [PROUVÉ] | ≥9 marchands | **MORT** (modèle validé, place prise) |
| Outillage pro BTP | pas de spécialiste, mais EAN de marque → généralistes | ManoMano 7 % | **MORT** |
| Lait 1er âge | — | publicité interdite (L.121-51) [PROUVÉ] | **MORT** |
| Cartouches d'encre | acheter-encre, easycartouche ; leDénicheur 27 offres/réf [PROUVÉ] | Inkadoo 20 % compatibles | DOUTEUX (saturé, déclin) |
| Parapharmacie / compléments | Unooc, paracompa, touslesprix [PROUVÉ] | 8-10 % (meilleures commissions) | DOUTEUX (occupé) |
| Croquettes | **petscompare.fr** = exactement ce projet [PROUVÉ] | Zooplus 1-3 %, Wanimo 4-10 % | DOUTEUX (petfood 6,7 Md€) |
| Pièces vélo | LeGuide, 123comparer [PROUVÉ] | Alltricks 3-7 % | DOUTEUX (1,12 Md€, bon rapprochement) |
| Couches | leDénicheur [PROUVÉ] | marges faibles | DOUTEUX |
| Beauté / coiffure pro | aucun spécialiste [PROUVÉ] | ≥10 marchands, Awin | DOUTEUX (vendu aussi aux particuliers) |
| CHR / emballages | aucun spécialiste [PROUVÉ] | ≥10, Nisbets Awin | DOUTEUX (rapprochement dur) |
| Paramédical (IDEL) | aucun comparateur [PROUVÉ] | ≥10, Girodmedical ≤10 % | DOUTEUX (99 200 IDEL, petits paniers) |
| Pièces électroménager | Prix.net a une catégorie, **pas de spécialiste par réf.** [PROUVÉ/PROBABLE] | ≥10 marchands ; affiliation Spareka/1001pieces non prouvée | DOUTEUX, le plus prometteur des pièces |
| **Filtres par compatibilité + piscine/spa** | **aucun spécialiste repéré** [PROUVÉ] ; leDénicheur couvre les références de marque (Brita, Bayrol) | Kwanko/Awin piscine 4,5-5 % ; SOS Accessoire, Jeremplace… | **VIVANT sous réserve** |

### Niche retenue [PROBABLE] : « le bon consommable pour MON appareil, au meilleur prix »

On fusionne les deux candidats les mieux placés : pièces d'usure électroménager et filtres/piscine.
L'utilisateur saisit **le modèle de son appareil**, qu'il s'agisse d'une hotte, d'un aspirateur,
d'un frigo américain, d'une carafe, d'une piscine ou d'un spa. Le site renvoie les consommables
compatibles (filtre, sac, courroie, joint, cartouche), triés par prix total entre les
marchands, avec une alerte de réassort et une alerte prix.

- **Pourquoi ça résiste aux généralistes** : idealo, leDénicheur et Google comparent une *référence*.
  Ici, la difficulté est de savoir *quelle* référence va sur *quel* appareil. La table de
  compatibilité est à la fois le coût d'entrée et le fossé. C'est le même mécanisme que Sparepilot
  en motoculture, qui a fait de ses références croisées son avantage [PROUVÉ que Sparepilot le revendique].
- **Récurrence** : un filtre ou un sac se rachète tous les 3 à 12 mois, donc l'alerte de réassort
  a une vraie raison d'exister [PROBABLE].
- **Demande** : 1,9 M de réparations financées par le Bonus Réparation en 3 ans, 3,7 M de piscines
  familiales [PROUVÉ]. Le volume de recherche « filtre + modèle » reste [INCONNU].

### Ce qui peut encore la tuer (à vérifier, dans cet ordre)

1. **Affiliation** : ≥10 marchands affiliés sur la niche ? Non prouvé pour Spareka, SOS Accessoire,
   1001pieces ni pour les pure players piscine. À vérifier dans les annuaires Awin, Effiliation et Kwanko.
2. **Source de la compatibilité** : les flux des marchands contiennent-ils un champ « compatible avec »
   exploitable, ou faut-il construire la table à la main ? [INCONNU], c'est le point qui décide du coût.
3. **Volume** : Google Keyword Planner sur 20 requêtes du type « filtre hotte <marque modèle> ».
4. **Couverture idealo** : vérifier à la main sur 10 références, puisque le site était bloqué ici.
5. **Saisonnalité piscine** : le trafic sera concentré d'avril à août [PROBABLE]. L'électroménager lisse sur l'année.

Repli si le test 1 ou 2 échoue : paramédical pour infirmiers libéraux (terrain libre, mais petits
paniers), puis croquettes en challenger de petscompare.

Sources supplémentaires : petscompare.fr · sparepilot.com/about · coompy.fr · comparapex.fr ·
magicparts.co · prix.net/categories/pieces-detachees-electromenager-26253.html ·
ledenicheur.fr/s/brita-maxtra-pro/ · ui.awin.com/merchant-profile/13256 ·
decouvrir.ecosystem.eco/actualites/bonus-reparation-3ans ·
idees-piscine.com/marche-de-la-piscine-un-automne-2025-prometteur-qui-confirme-le-rebond/ ·
drees.solidarites-sante.gouv.fr/sites/default/files/2024-06/DM15.pdf ·
renseignementeconomique.fr/le-marche-du-petfood-pese-6-7-milliards-en-2025-et-profite-aux-enseignes-specialisees ·
ordre.pharmacien.fr (interdiction publicité préparations pour nourrissons)
