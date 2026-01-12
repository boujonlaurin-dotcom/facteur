# Facteur Sources Catalog

Ce répertoire contient le catalogue des sources curées pour le projet Facteur.

## Gestion du catalogue (`sources.csv`)

Le fichier `sources.csv` est la source de vérité pour les sources "Trusted". Pour chaque ajout, les colonnes suivantes doivent être renseignées avec soin selon la stratégie **FQS (Facteur Quality Score)**.

### Colonnes stratégiques

| Colonne | Valeurs | Description (Critères FQS) |
| :--- | :--- | :--- |
| **Bias** | `left`, `center-left`, `center`, `center-right`, `right`, `alternative`, `specialized` | Le positionnement politique ou thématique dominant de la source. |
| **Reliability** | `low`, `medium`, `high` | Score de confiance basé sur le **FQS** (voir ci-dessous). |

### Le Facteur Quality Score (FQS)

Avant d'ajouter une source avec une `Reliability` élevée (`high`), elle doit être évaluée sur 100 points :

1. **Indépendance & Transparence (40%)** : La rédaction est-elle protégée des intérêts actionnariaux ? La ligne est-elle claire ?
2. **Rigueur Journalistique (35%)** : Sourcing systématique, absence de clickbait, vérification des faits.
3. **Accessibilité & UX (25%)** : Le média est-il "slow-media friendly" ? (Peu de pubs, paywall non-bloquant pour les résumés).

> [!TIP]
> **Seuil d'inclusion MVP** : Une source avec un FQS < 70 ne devrait pas être incluse dans le catalogue par défaut pour garantir la promesse de "clarté apaisante".

## Import technique

Pour synchroniser les modifications du CSV avec la base de données (Supabase), exécutez le script suivant :

```bash
python packages/api/scripts/import_sources.py
```

Le script utilise un **upsert** basé sur l'URL du flux RSS détecté.
