# QA Handoff — Story 15.1 Mode Serein Refine

Feature : refonte du mode serein — suppression de l'écran onboarding `SensitiveThemesQuestion`, ajout d'un CTA « Personnaliser mon mode serein » sous la question "Rester serein ?", et déplacement de la configuration (granulaire, tri-state par thème + par topic individuel) dans **Paramètres > Mes Intérêts** via le switch Normal/Serein existant, déplacé en top-right de la page.

## Écrans impactés

| Écran | Route | Modifié |
|-------|-------|---------|
| Onboarding — "Rester serein ?" | `/onboarding` (section 2) | Ajout CTA `TextButton` "Personnaliser mon mode serein" |
| Onboarding — `SensitiveThemesQuestion` | supprimé | Route + écran entier retirés |
| Paramètres — Mes Intérêts | `/settings/interests` | AppBar.bottom = `SereinToggleChip` top-right ; mode Serein → checkbox tri-state thème + checkbox par topic ; section "Sujets sensibles" dépliable retirée |

## Pré-requis

- Environnement staging (API + front mobile web `flutter run -d chrome`)
- Compte utilisateur **neuf** (onboarding frais)
- Compte utilisateur **existant** déjà configuré avec un mode serein (pour scénario E3)
- SQL one-shot à exécuter avant test E3 : `docs/qa/scripts/backfill_serein_personalized.sql`

## Scénarios — Happy path

### Scénario 1 — Fresh onboarding, "Oui, rester serein" sans personnalisation

1. Démarrer un onboarding neuf.
2. Arriver sur la question "🌿 Rester serein ?".
3. **Attendu** :
   - Deux boutons : "Oui, rester serein" (primary) / "Non, tout voir" (outlined).
   - Sous les boutons : `TextButton` "Personnaliser mon mode serein" (visible en permanence).
   - Aucun écran intermédiaire `SensitiveThemesQuestion` n'apparaît après le choix.
4. Taper "Oui, rester serein" → le bouton "Continuer" apparaît.
5. Taper "Continuer" → passage direct à la section 3.
6. Terminer l'onboarding.
7. **Attendu** : le digest généré respecte les défauts `SEREIN_EXCLUDED_THEMES` (pas d'articles dont `Source.theme` ∈ {politics, international, economy, society} ni contenant des mots-clés anxiogènes).

### Scénario 2 — Fresh onboarding → CTA "Personnaliser"

1. Onboarding neuf jusqu'à la question "Rester serein ?".
2. Taper "Personnaliser mon mode serein".
3. **Attendu** :
   - Navigation via `pushNamed` vers `/settings/interests?serein=1`.
   - La page "Mes Intérêts" s'affiche avec le `SereinToggleChip` **positionné sur Serein** (fond pastel sauge).
4. En mode Serein :
   - Chaque `ThemeSection` affiche un **checkbox tri-state** dans son header.
   - Chaque `TopicRow` affiche un **checkbox à gauche** (à la place du point terracotta).
   - Le slider de priorité est **caché**.
5. Par défaut : tous les thèmes/topics sont **cochés** SAUF ceux des macro-thèmes exclus (society / international / economy / politics) qui sont **décochés**.
6. Décocher un thème neutre (e.g. "Tech") : header passe à false, tous les topics enfants se décochent.
7. Taper back. Retour sur `DigestModeQuestion` : "Oui, rester serein" est pré-sélectionné, "Continuer" disponible.
8. Terminer l'onboarding.
9. **Attendu** : le digest exclut "Tech" (aucun article tech) en plus des défauts.

### Scénario 3 — Settings : toggle Normal/Serein top-right

1. Se connecter avec un utilisateur ayant terminé son onboarding.
2. Ouvrir `Paramètres > Mes Intérêts`.
3. **Attendu** : AppBar = "Mes Intérêts", en dessous à droite le `SereinToggleChip` en mode Normal par défaut.
4. Taper le segment "Serein" → transition animée, chip vert sauge.
5. **Attendu** :
   - La section "Types de contenu" disparaît.
   - La section "Sujets mis en sourdine" disparaît.
   - Le bouton "Ajouter un sujet personnalisé" disparaît (FAB + block).
   - Checkbox tri-state sur thème, checkbox par topic (sans slider, sans icône mute).
   - Swipe-to-unfollow désactivé (le `Dismissible` ne wrap plus en mode serein).
6. Décocher un topic individuel (e.g. "Donald Trump").
7. Re-taper "Normal" → retour à l'affichage standard avec sliders et muted.

### Scénario 4 — Persistance

1. Scénario 3 effectué : switch Serein ON, décoche un thème, décoche un topic.
2. Quitter l'app, la relancer.
3. Rouvrir `Paramètres > Mes Intérêts`, retaper Serein.
4. **Attendu** : les mêmes cases sont encore décochées (persisté via `user_preferences.sensitive_themes`, `user_preferences.serein_personalized='true'`, et `user_topic_profiles.excluded_from_serein`).

## Scénarios — Edge cases

### E1 — Cascade tri-state sur le header de thème

1. En mode Serein, dans un thème à 3 topics, décocher 1 seul topic.
2. **Attendu** : le checkbox du header passe en **indéterminé** (tri-state `null`, dash visuel).
3. Décocher les 2 autres → header passe à **false**.
4. Cocher le header depuis false → les 3 topics se cochent en cascade ET le thème sort de `excludedThemeSlugs`.

### E2 — Back depuis CTA sans rien changer

1. Onboarding → "Personnaliser" → arrive sur Mes Intérêts en Serein.
2. Ne rien changer, taper back immédiatement.
3. **Attendu** : retour sur `DigestModeQuestion` avec "Oui, rester serein" pré-sélectionné. Aucun flag `serein_personalized` posé côté API — le filtre reste sur défauts.

### E3 — Utilisateur existant avec `sensitive_themes` pré-migration

1. En staging, sélectionner un compte avec `user_preferences.sensitive_themes` non-null mais **pas** de `serein_personalized`.
2. Exécuter `docs/qa/scripts/backfill_serein_personalized.sql`.
3. Vérifier que le digest de cet utilisateur reste identique à avant (pas de régression de contenu affiché).

### E4 — `SereinToggleChip` sans overflow

1. Ouvrir `Paramètres > Mes Intérêts` sur viewport étroit (iPhone SE / 375px).
2. **Attendu** : le chip s'affiche intégralement sous l'AppBar, aligné à droite, sans texte tronqué (protégé par `FittedBox` interne).

## Critères d'acceptation

- [ ] Section 2 de l'onboarding compte 5 questions (non plus 6 quand serein est choisi).
- [ ] `SensitiveThemesQuestion` n'apparaît jamais.
- [ ] CTA "Personnaliser mon mode serein" toujours visible sous les boutons du choix serein.
- [ ] `MyInterestsScreen` en mode Serein affiche des cases cochables par thème (tri-state) et par topic, avec persistance immédiate optimiste.
- [ ] Le digest en mode Serein exclut l'union des thèmes décochés **+** des topics décochés.
- [ ] Par défaut, `SEREIN_EXCLUDED_THEMES` (society/international/economy/politics) reste bloqué tant que `serein_personalized` n'est pas posé.
- [ ] Aucun overflow UI sur iPhone SE.
- [ ] Aucune régression sur les flux existants (onboarding section 1/3, paramètres hors mode serein).

## Tests automatisés

- `flutter analyze` : 0 erreur sur les fichiers modifiés (warnings pré-existants conservés).
- `flutter test` mobile : 37 échecs **pré-existants** (baseline `main` identique). 0 régression introduite par ce refactor.
- `pytest tests/test_serein_filter.py` (hors tests DB) : 10/10 passent, incluant nouveaux tests `test_custom_themes_replace_defaults`.
- Les tests DB-backed (`TestSereinFilterWithIsSerene`, `TestSereinFilterFallbackKeywords`, etc.) nécessitent Postgres local (`make db-up`) — CI gère.

## Zones de risque

- **Migration Alembic** : nouveau head `sr01_add_serein_exclusion` fusionne 2 heads existants (`ln01` + `ss01_search_cache`) et ajoute la colonne `user_topic_profiles.excluded_from_serein`. À appliquer manuellement via Supabase SQL Editor (hors Railway).
- **Sémantique changée** : `sensitive_themes` stocké ne fait **plus union** avec les défauts — il les **remplace** dès que `serein_personalized=true`. Un utilisateur ayant `sensitive_themes=['tech']` voit **uniquement** tech filtré (society/politics repassent). Backfill SQL obligatoire avant déploiement.
- **UI sur petits écrans** : `SereinToggleChip` = 148px de large. Déplacement dans `AppBar.bottom` au lieu de `actions` pour éviter l'overflow lié au titre AppBar.

## Fichiers critiques à vérifier visuellement

```
apps/mobile/lib/features/custom_topics/screens/my_interests_screen.dart
apps/mobile/lib/features/custom_topics/widgets/theme_section.dart        # tri-state header
apps/mobile/lib/features/custom_topics/widgets/topic_row.dart            # checkbox left
apps/mobile/lib/features/onboarding/screens/questions/digest_mode_question.dart  # CTA
apps/mobile/lib/config/routes.dart                                        # ?serein=1 query
```

## Ressources

- Story doc : `docs/stories/core/15.1.mode-serein-refine.story.md`
- Plan : `~/.claude/plans/system-instruction-you-are-working-glistening-donut.md`
- Backfill SQL : `docs/qa/scripts/backfill_serein_personalized.sql`
