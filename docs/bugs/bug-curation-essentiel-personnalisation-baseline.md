# Baseline « qualité de la curation » — figée le 2026-08-01

Mesures de référence **avant** tout changement, à rejouer à l'identique après
chaque PR du lot :

```bash
psql "$DATABASE_URL_RO" -X -f docs/qa/scripts/baseline_curation.sql
```

Diagnostic : [`bug-curation-essentiel-personnalisation.md`](bug-curation-essentiel-personnalisation.md).

Fenêtre : 30 jours glissants au 2026-08-01. Périmètre : `daily_digest`,
`format_version = 'editorial_v3'`. `rank` 1-5 = ce que la carte « Ton Essentiel »
affiche ; 6-10 = généré puis tronqué, jamais vu.

> **Prérequis appliqué le 2026-08-01** : `ALTER ROLE claude_analytics_ro BYPASSRLS;`
> Avant ça, `daily_digest` / `contents` / `user_content_status` renvoyaient
> **0 ligne** au rôle analytics (RLS) — la jauge tournait sans erreur et
> rapportait un CTR vide. Vérifié après application : 20 135 / 73 282 / 5 561
> lignes visibles, et le rôle **reste en lecture seule** (`permission denied`
> sur `UPDATE`).

## Les 5 métriques de pilotage

| # | Métrique | Baseline 01/08/2026 | Cible après P0+P1 |
|---|---|---|---|
| M1 | Slots top-5 quasi-universels (`pour_vous`) | **80,8 %** | < 60 % |
| M2 | Slots top-5 issus d'une source suivie | **16,3 %** | ≥ 35 % |
| M3 | Part de `society` dans les slots top-5 | **42,7 %** | < 30 % |
| M4 | Part des 5 pourvoyeurs dans les slots top-5 | **62,8 %** | < 45 % |
| M5 | CTR global top-5 | **1,41 %** (348 / 24 595) | ne pas dégrader |

## Détail

**M1 — personnalisation réelle.** Un slot est « quasi-universel » si l'article
est dans le top-5 d'au moins 50 % des users servis ce jour-là.

| Mode | Slots | Quasi-universels | Réellement personnels (< 10 %) |
|---|---|---|---|
| `pour_vous` | 18 355 | **80,8 %** | **4,2 %** |
| `serein` | 6 240 | **85,3 %** | **0,9 %** |

**M2 — la personnalisation est sous la ligne de flottaison.**

| Zone | Slots | % source suivie | % mono-source |
|---|---|---|---|
| rang 1-5 (affiché) | 24 595 | **16,3 %** | 36,2 % |
| rang 6-10 (jamais vu) | 23 134 | **37,4 %** | 94,9 % |

**M3 — thèmes du top-5.** `society` 42,7 % · `environment` 17,1 % ·
`culture` 11,5 % · `international` 10,8 % · `tech` 9,5 % · `sport` 2,9 % ·
`science` 1,8 % · `custom` 1,4 % · **`politics` 1,3 %** · `economy` 1,0 %.

**M4/M5 — pourvoyeurs et CTR.**

| Groupe | Slots | % top-5 | Lus | CTR |
|---|---|---|---|---|
| Les 5 pourvoyeurs | 15 457 | **62,8 %** | 192 | **1,24 %** |
| Tout le reste | 9 138 | 37,2 % | 156 | **1,71 %** |
| Source **suivie** | 4 019 | 16,3 % | 144 | **3,58 %** |
| Source non suivie | 20 576 | 83,7 % | 204 | **0,99 %** |
| **Global top-5** | **24 595** | | **348** | **1,41 %** |

**M7 — `selection_reason` : taux d'accès au top-5.**

| Raison | Top-5 | Total | % atteint |
|---|---|---|---|
| Traité par 3 sources | 1 343 | 1 343 | **100 %** |
| Couvert par 2 sources | 10 249 | 11 424 | **89,7 %** |
| Couvert par 1 sources | 7 286 | 21 228 | 34,3 % |
| **Source suivie** | 1 608 | 9 471 | **17,0 %** |

## Corrections apportées au plan par la mesure

1. **La colonne « CTR top-5 » du §4 du plan est fausse.** Elle donnait
   Ouest-France à 0,02 %, Home Fil actu / France Info / CNEWS à 0,00 %. Mesuré :
   1,10 % / 1,08 % / 1,42 % / 1,83 %. C'était arithmétiquement impossible — avec
   62,8 % des slots à ~0 %, le CTR global ne pouvait pas être à 1,41 %.
   **L'écart réel est de 1,24 % contre 1,71 %, soit ×1,4 — pas un effondrement.**
   L'argument de B-2 tient sur la **composition** (62,8 % de la surface héros à
   5 sources qui n'apportent pas de couverture thématique, cf. test de survie
   à 68-88 %), **pas** sur un CTR nul.
2. **Le vrai gradient est ailleurs** et il est net : **source suivie 3,58 %
   contre 0,99 %, soit ×3,6.** C'est la mesure qui porte tout le dossier.
3. Les qualitatives battent les pourvoyeurs d'environ ×2 : La Croix 3,01 %,
   Le Monde 2,43 %, Courrier International 2,15 %.

## Réserve de puissance

348 lectures sur 24 595 slots. Toute comparaison de CTR entre deux variantes se
lira à **±5 pp** au mieux. **Les métriques M1-M4 sont déterministes** et se
lisent dès le premier batch : c'est sur elles qu'il faut juger, pas sur M5.
