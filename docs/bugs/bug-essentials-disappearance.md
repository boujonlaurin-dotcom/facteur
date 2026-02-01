# Bug: "Essentiels du jour" Disappearance

## 🚨 Description
La feature "Essentiels du jour" (Daily Top 3) n'apparaît plus pour les utilisateurs (nouveaux comme existants) en production.
Le job semble ne pas générer de briefing, ou celui-ci n'est pas récupéré.

## 🔬 Observation
- **Comportement**: Section absente du Feed.
- **Scope**: Tous les utilisateurs (confirmé par User).
- **Date**: "Aujourd'hui nji hier" (30-31 Jan 2026).

## 🕵️ Hypothèses
1. **Rec Service Failure**: `_get_candidates` ne retourne rien ou plante.
2. **Persistence Failure**: Le job plante au moment de l'insertion (Constraint?).
3. **Retrieval Mismatch**: Le `generated_at` est incompatible avec le filtre `today_start` de `feed.py`.
4. **Scheduler**: Le job ne tourne simplement pas (mais ça n'expliquerait pas un échec silencieux si lancé manuellement, ce qu'on va vérifier).

## 🛠️ Plan d'Investigation
1. Script de debug local pour forcer l'exécution du job.
2. Vérifier les candidats retournés par `_get_candidates`.
3. Vérifier les dates en base de données.
