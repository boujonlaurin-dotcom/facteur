# QA / Déploiement : Guide rapide

Objectif : valider rapidement qu'un déploiement est sain, sans expertise CI.

## Le geste unique (recommandé)

```bash
docs/qa/scripts/verify_release.sh
```

## Options utiles

- Changer l'URL API :
```bash
API_BASE_URL=https://facteur-production.up.railway.app docs/qa/scripts/verify_release.sh
```

- Vérifier les migrations (si `DATABASE_URL` est disponible) :
```bash
DATABASE_URL=postgresql://... docs/qa/scripts/verify_release.sh
```

- Lancer le build APK (optionnel) :
```bash
RUN_FLUTTER_BUILD=1 docs/qa/scripts/verify_release.sh
```

## Quand le lancer

- Avant un déploiement
- Après un correctif critique
- Après une modification d'infra ou de migrations
