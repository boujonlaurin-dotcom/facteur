/// Réconciliation du placement Essentiel/Flâner entre la DB (source de vérité
/// durable) et les prefs locales (cache de rendu).
///
/// **Le bug corrigé.** Jusqu'ici le *mode de placement* d'un favori (« Chaque
/// jour dans l'Essentiel » vs « Flâner ») ne vivait que dans les
/// SharedPreferences du device (`tournee_order_v1` / `pinned_tabs_order_v1`) —
/// le favori lui-même étant persisté en DB. À la réinstallation / nouveau
/// device / purge du stockage, le favori survivait mais son placement Essentiel
/// disparaissait silencieusement → la source « tombait » de l'Essentiel.
///
/// Ce module fait de la colonne DB `essentiel_mode` la source de vérité durable :
///
///  1. **Backfill local → DB** (one-shot, gardé par [_kReconciledKey]) : pour
///     chaque favori dont le backend ignore encore le placement
///     (`essentiel_mode == null`), on pousse le placement *local actuel* du
///     device. Capture l'état device **avant** qu'il ne puisse être perdu.
///  2. **Hydratation DB → local** (à chaque cold boot, idempotente) : pour
///     chaque favori dont le backend connaît le placement
///     (`essentiel_mode != null`), on aligne les prefs locales dessus. C'est ce
///     qui **restaure l'appartenance après réinstallation / nouveau device**.
///
/// La règle de rendu (`TourneeOrderState.sourceIsEssentiel`, et pour les thèmes
/// la présence dans `pinned_tabs_order_v1`) reste inchangée : elle lit les prefs,
/// désormais rendues durables par l'hydratation.
///
/// ⚠️ Asymétrie source/thème (conventions inverses, préservée telle quelle) :
///  - **Source** : Essentiel ⟺ clé `source:<id>` présente dans `tournee_order_v1`
///    (défaut = Flâner).
///  - **Thème** : Flâner ⟺ clé `theme:<slug>` présente dans `pinned_tabs_order_v1`
///    (défaut = Essentiel).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../my_interests/models/user_interests_state.dart'
    show InterestState, ThemeFavoriteRef;
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../feed/providers/tab_order_prefs_provider.dart'
    show tabOrderPrefsProvider, tabOrderSourceKey, tabOrderThemeKey;
import 'tournee_order_prefs_provider.dart'
    show tourneeOrderPrefsProvider, tourneeSourceKey, tourneeThemeKey;

/// Flag prefs : le backfill local → DB a été effectué une fois sur ce device.
const String _kReconciledKey = 'essentiel_placement_reconciled_v1';

/// Réconcilie le placement Essentiel/Flâner. À appeler une fois par cold boot,
/// depuis le bootstrap de la Tournée. Best-effort : toute erreur est avalée
/// (log debug) — la réconciliation ne doit jamais casser le chargement du feed.
Future<void> reconcileEssentielPlacement(Ref ref) async {
  try {
    // 1. État backend (source de vérité). On force la résolution des deux
    //    providers (lazy pendant le bootstrap) en parallèle : ils sont
    //    indépendants, on chevauche donc leurs fetchs plutôt que de les enchaîner.
    final (sourcesState, interestsState) = await (
      ref.read(userSourcesStateProvider.future),
      ref.read(userInterestsProvider.future),
    ).wait;

    final favSources = sourcesState.sources
        .where((s) => s.state == InterestState.favorite)
        .toList();
    final favThemes = interestsState.themes
        .where((t) => t.state == InterestState.favorite)
        .toList();
    if (favSources.isEmpty && favThemes.isEmpty) return;

    // 2. État local du device (prefs déjà chargées au bootstrap).
    final tourneeState = ref.read(tourneeOrderPrefsProvider);
    final tournee = List<String>.of(tourneeState.order);
    final tab = List<String>.of(ref.read(tabOrderPrefsProvider));

    final prefs = await SharedPreferences.getInstance();
    final alreadyReconciled = prefs.getBool(_kReconciledKey) ?? false;

    // ── Backfill local → DB (one-shot) ──────────────────────────────────────
    var backfillFullySucceeded = true;
    if (!alreadyReconciled) {
      for (final s in favSources) {
        if (s.essentielMode != null) continue; // placement déjà connu en DB.
        // Règle d'appartenance canonique (partagée par le provider Tournée, les
        // onglets Flâner et la sheet de gestion) — évite une 4ᵉ définition locale.
        final localEssentiel = tourneeState.sourceIsEssentiel(s.sourceId);
        try {
          await ref.read(userSourcesStateProvider.notifier).setSourceState(
                s.sourceId,
                InterestState.favorite,
                essentielMode: localEssentiel,
              );
        } catch (e) {
          backfillFullySucceeded = false;
          debugPrint('[essentiel-sync] backfill source ${s.sourceId} failed: $e');
        }
      }
      for (final t in favThemes) {
        if (t.essentielMode != null) continue;
        // Thème : Flâner ⟺ présent dans pinned_tabs ; sinon Essentiel (défaut).
        final localEssentiel = !tab.contains(tabOrderThemeKey(t.interestSlug));
        try {
          await ref.read(userInterestsProvider.notifier).setInterestState(
                ThemeFavoriteRef(slug: t.interestSlug),
                InterestState.favorite,
                essentielMode: localEssentiel,
              );
        } catch (e) {
          backfillFullySucceeded = false;
          debugPrint(
              '[essentiel-sync] backfill theme ${t.interestSlug} failed: $e');
        }
      }
      // On ne pose le flag que si le backfill a intégralement réussi : sinon on
      // retentera au prochain cold boot (les favoris déjà poussés seront alors
      // non-null → sautés, donc l'opération reste idempotente).
      if (backfillFullySucceeded) {
        try {
          await prefs.setBool(_kReconciledKey, true);
        } catch (_) {
          // best-effort.
        }
      }
    }

    // ── Hydratation DB → local (idempotente, chaque cold boot) ───────────────
    // On repart des listes backend fraîches : un favori tout juste backfillé a
    // désormais un essentielMode local == backend, donc l'alignement est un
    // no-op pour lui. Pour les favoris déjà connus en DB (essentielMode != null,
    // ex. resync après réinstallation) c'est ici qu'on restaure le placement.
    // Copies mutables : les originaux `tournee`/`tab` restent la référence pour
    // le check de drift plus bas. Les clés sont uniques (modèle exclusif + ajouts
    // gardés par `contains`), donc `remove` (1er match) suffit.
    final nextTournee = List<String>.of(tournee);
    final nextTab = List<String>.of(tab);

    for (final s in favSources) {
      final mode = s.essentielMode;
      if (mode == null) continue;
      final tKey = tourneeSourceKey(s.sourceId);
      final bKey = tabOrderSourceKey(s.sourceId);
      if (mode) {
        // Essentiel : présent dans tournee, absent de Flâner (modèle exclusif).
        if (!nextTournee.contains(tKey)) nextTournee.add(tKey);
        nextTab.remove(bKey);
      } else {
        // Flâner : retiré de l'Essentiel, présent dans les onglets.
        nextTournee.remove(tKey);
        if (!nextTab.contains(bKey)) nextTab.add(bKey);
      }
    }

    for (final t in favThemes) {
      final mode = t.essentielMode;
      if (mode == null) continue;
      final tKey = tourneeThemeKey(t.interestSlug);
      final bKey = tabOrderThemeKey(t.interestSlug);
      if (mode) {
        // Essentiel = défaut du thème : il suffit de le retirer de Flâner.
        nextTab.remove(bKey);
      } else {
        // Flâner : présent dans les onglets, retiré de l'Essentiel explicite.
        nextTournee.remove(tKey);
        if (!nextTab.contains(bKey)) nextTab.add(bKey);
      }
    }

    // Écritures groupées (une seule notif par provider) uniquement si drift réel.
    if (!listEquals(nextTournee, tournee)) {
      await ref
          .read(tourneeOrderPrefsProvider.notifier)
          .setOrder(nextTournee);
    }
    if (!listEquals(nextTab, tab)) {
      await ref.read(tabOrderPrefsProvider.notifier).setOrder(nextTab);
    }
  } catch (e, st) {
    debugPrint('[essentiel-sync] reconcile skipped on error: $e\n$st');
  }
}
