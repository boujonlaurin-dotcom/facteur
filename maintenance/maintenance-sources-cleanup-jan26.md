# Maintenance : Nettoyage et Optimisation des Sources RSS

**Date** : 2026-01-22  
**Auteur** : BMAD Agent  
**Type** : Data Cleaning / Optimization  

---

## Contexte

L'expérience utilisateur dans l'app est dégradée par :
1. Un volume d'articles trop important de certaines sources (notamment L'Opinion).
2. Des doublons dans les sources (Heu?reka apparaît deux fois).
3. Une source obsolète toujours active (Dirty Biology devait être retirée).

## Actions réalisées

### 1. Désactivation de Dirty Biology
- **Raison** : Source à retirer suite à décision éditoriale.
- **Action DB** : `is_active = false`
- **Action CSV** : Suppression de `sources.csv` et passage en `INDEXED` (désactivé) dans `sources_master.csv`.

### 2. Fusion des doublons Heu?reka
- **Problème** : Deux entrées avec la même URL de chaîne YouTube mais des `feed_url` différents.
  - `https://www.youtube.com/channel/UC7sXGI8p8PvKosLWagkK9wQ` (URL brute, non fonctionnelle comme RSS)
  - `https://www.youtube.com/feeds/videos.xml?channel_id=UC7sXGI8p8PvKosLWagkK9wQ` (flux XML valide)
- **Action** : Conservation de l'entrée avec le flux XML, suppression/désactivation de l'autre.

### 3. Rééquilibrage de la pluralité (Droite)
- **Problème** : L'Opinion produit beaucoup d'articles, saturant le flux curé.
- **Action** : 
  - **L'Opinion** : Passage de `CURATED` à `INDEXED` (reste disponible en recherche, mais ne pollue plus le flux RSS principal).
  - **Contrepoints** : Promotion de `INDEXED` à `CURATED` (Libéral, économie).
  - **L'Incorrect** : Promotion de `INDEXED` à `CURATED` (Conservateur, société).

## Fichiers impactés

| Fichier | Modification |
|---------|--------------|
| `sources/sources_master.csv` | Mise à jour des statuts CURATED/INDEXED |
| `sources/sources.csv` | Ajout de Contrepoints et L'Incorrect, suppression de Dirty Biology |
| Base de données (Supabase) | Mise à jour via script `packages/api/scripts/cleanup_sources_jan26.py` |

## Vérification

Script de diagnostic : `packages/api/check_sources_duplicates.py`

```bash
cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur/packages/api && source venv/bin/activate && python3 check_sources_duplicates.py
```

## Liens

- **Stories impactées** : 
  - `3.2.import-catalogue-sources.md` (catalogue initial)
  - `7.1.profiling-sources.md` (biais et fiabilité)
