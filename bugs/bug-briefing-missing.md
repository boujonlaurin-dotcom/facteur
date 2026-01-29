# Bug: Briefing quotidien absent du feed

## Status: InProgress

## Date: 24/01/2026

## Symptôme

- La carte "À la une" ne s'affiche plus dans le feed.
- Le container "Briefing terminé" n'apparaît plus après lecture du briefing.

## Impact

- Le Top 3 quotidien n'est plus visible, même quand l'utilisateur est sur le feed principal.
- Perte d'un repère clé (briefing lu) et baisse de perception de valeur.

## Hypothèses principales

1. **Briefing non renvoyé par l'API** si un filtre est actif (paramètre `mode`).
2. **Aucun DailyTop3 généré** pour l'utilisateur (job non exécuté ou onboarding incomplet).
3. **Réponse API incompatible** avec le parsing mobile (champs manquants).

## Pistes de vérification

- Inspecter la réponse `/api/feed` (paramètres `mode`, `offset`, `saved`).
- Vérifier la table `daily_top3` (aujourd'hui + user concerné).
- Confirmer l'exécution du job `daily_top3` (scheduler ou endpoint interne).

## Contrainte

- Ne pas casser le mode filtres (ne doit pas masquer le feed).
