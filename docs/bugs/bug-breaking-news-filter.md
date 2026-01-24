# Bug: Mode "Dernières news" n'affiche qu'un seul média

## Status: Fixed

## Date: 24/01/2026

## Symptôme

Le mode "Dernières news" (filtre `breaking`) du feed n'affichait généralement qu'un seul média au lieu d'une diversité de sources d'actualités chaudes.

## Cause Racine

Dans `packages/api/app/services/recommendation_service.py`, le filtre BREAKING utilisait des thèmes incorrects :

```python
Source.theme.in_(['politics', 'geopolitics', 'economy'])
```

**Problème** : Les thèmes `politics` et `geopolitics` n'existent pas dans la base de données des sources.

Répartition réelle des thèmes dans `sources_master.csv` :
- `society` : 94 sources (France Info, Mediapart, Libération, etc.)
- `international` : 70 sources (Le Monde, Le Figaro, Politico Europe, etc.)
- `economy` : 33 sources (Les Échos, Guerres de Business, etc.)
- `tech`, `culture`, `science`, `environment` : autres

Note : `geopolitics` est un **sous-thème granulaire** (`granular_topics`), pas un thème de source.

## Correction

Alignement des thèmes Hard News avec les données réelles **en base** :

```python
# Thèmes DB (via THEME_MAPPING de import_sources.py) :
# - "Société & Climat" -> society_climate
# - "Géopolitique" -> geopolitics
# - "Économie" -> economy
Source.theme.in_(['society_climate', 'geopolitics', 'economy'])
```

**Note importante** : Les thèmes en base correspondent au `THEME_MAPPING` de `scripts/import_sources.py`, pas aux thèmes du CSV `sources_master.csv`.

## Philosophie "Feed Twitter-like"

Le mode "Dernières news" adopte maintenant une philosophie inspirée de Twitter :
- **Immédiateté** : Fenêtre courte de 12h pour garantir la fraîcheur
- **Réactivité** : Thèmes Hard News uniquement (society, international, economy)
- **Temps réel** : Tri chronologique inversé, les plus récents en premier

## Fichiers Modifiés

- `packages/api/app/services/recommendation_service.py` : Filtre BREAKING avec bons thèmes
- `docs/prd.md` : Documentation de la philosophie Twitter-like
- `docs/architecture.md` : Mise à jour des Filtering Rules

## Sources Éligibles

Environ 197 sources CURATED dans les thèmes Hard News :
- **society** (16) : France Info, Mediapart, Libération, RTL, Europe 1...
- **international** (8) : Le Monde, Le Figaro, Politico Europe, Courrier International...
- **economy** (7) : Les Échos, Contrepoints, Alternatives Économiques...

## Leçons Apprises

1. Valider les filtres contre les données réelles en base (`sources_master.csv`)
2. `geopolitics` est un sous-thème, pas un thème de source
3. Toujours vérifier que le déploiement Railway a réussi avant de tester
