import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../digest/providers/serein_toggle_provider.dart';
import '../../flux_continu/providers/geoloc_prompt_provider.dart';
import '../../flux_continu/providers/tournee_order_prefs_provider.dart';
import '../../notifications/providers/notification_renudge_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../../veille/providers/veille_active_config_provider.dart';
import '../../well_informed/providers/well_informed_prompt_provider.dart';
import '../models/notif_du_jour_message.dart';
import 'notif_du_jour_day_store.dart';
import 'notif_du_jour_dismissal_store.dart';

/// Amplitude du jitter quotidien (ε). Assez pour permuter des messages de
/// pertinence proche jour à jour, trop peu pour faire passer un 0.6 devant
/// un 1.0. Knob calibrable avec le PO.
const double kRotationJitter = 0.15;

/// Candidat éligible : id + pertinence profil [0,1].
class NotifCandidate {
  final String id;
  final double relevance;

  const NotifCandidate(this.id, this.relevance);
}

/// Jour epoch local — constant sur la journée vécue par l'utilisateur,
/// change à minuit local (même frontière que le day store : cap et rotation
/// basculent au même moment).
int notifEpochDay(DateTime now) =>
    DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(1970))
        .inDays;

/// Hash FNV-1a 31 bits d'un id : stable inter-plateformes (contrairement à
/// `String.hashCode`), pour un jitter 100 % déterministe et testable.
int notifIdHash(String id) {
  var h = 2166136261;
  for (final c in id.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0x7fffffff;
  }
  return h;
}

/// Rotation quotidienne déterministe : bruit ∈ [0, amplitude] stable pour un
/// couple (jour, id).
double notifJitter(
  String id,
  int epochDay, {
  double amplitude = kRotationJitter,
}) {
  // FNV sur `id#jour` : mixe id et jour non-linéairement. Un hash affine
  // (`jour * K + idHash`) donnerait des jitters corrélés entre ids (écart
  // constant d'un jour à l'autre) → quasi aucune permutation.
  final h = notifIdHash('$id#$epochDay');
  return (h % 1000) / 1000 * amplitude;
}

/// Trie les éligibles par `relevance + jitter(jour)` décroissant.
/// Tie-break par id pour un ordre totalement déterministe.
List<String> rankNotifQueue(
  List<NotifCandidate> candidates,
  int epochDay, {
  double jitterAmplitude = kRotationJitter,
}) {
  final keyed = [
    for (final c in candidates)
      (
        id: c.id,
        key: c.relevance +
            notifJitter(c.id, epochDay, amplitude: jitterAmplitude),
      ),
  ]..sort((a, b) {
      final cmp = b.key.compareTo(a.key);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
  return [for (final c in keyed) c.id];
}

/// File ordonnée des messages éligibles du jour (ids), consommée un à un par
/// la carte via le day store.
///
/// Éligibilité : toute donnée async non résolue ⇒ non éligible (pas de flash),
/// sauf `recommencer`, fallback toujours éligible → file jamais vide.
final notifDuJourQueueProvider = Provider<List<String>>((ref) {
  final candidates = <NotifCandidate>[];

  // Nudges absorbés — temps-sensibles, leurs `*ShouldShowProvider` encodent
  // déjà cap / espacement / refus passé.
  if (ref.watch(notificationRenudgeShouldShowProvider)) {
    candidates.add(const NotifCandidate(NotifDuJourIds.notifRenudge, 0.9));
  }
  if (ref.watch(wellInformedShouldShowProvider).valueOrNull ?? false) {
    // Relevance abaissée 0.85 → 0.6 : le sondage NPS gagne moins souvent le tri
    // de la file (rareté non biaisée, cf. WellInformedPromptController).
    candidates.add(const NotifCandidate(NotifDuJourIds.wellInformed, 0.6));
  }
  if (ref.watch(geolocPromptShouldShowProvider).valueOrNull ?? false) {
    candidates.add(const NotifCandidate(NotifDuJourIds.geoloc, 0.7));
  }

  // Messages profil. `.select` sur les comptes dérivés : la file ne se
  // re-trie pas quand la liste de sources change sans toucher ces comptes.
  final trusted = ref.watch(
    userSourcesProvider.select(
      (v) => v.valueOrNull?.where((s) => s.isTrusted).length,
    ),
  );
  if (trusted != null && trusted < 3) {
    candidates.add(
      NotifCandidate(NotifDuJourIds.source, sourceRelevance(trusted)),
    );
  }

  final eligibleSubsCount = ref.watch(
    eligibleSubscriptionSourcesProvider.select((l) => l.length),
  );
  if (eligibleSubsCount > 0) {
    candidates.add(
      NotifCandidate(
        NotifDuJourIds.premium,
        premiumRelevance(eligibleSubsCount),
      ),
    );
  }

  final veille = ref.watch(veilleActiveConfigProvider);
  if (veille.hasValue && veille.valueOrNull == null) {
    candidates.add(const NotifCandidate(NotifDuJourIds.veille, 0.6));
  }

  if (!ref.watch(tourneeOrderPrefsProvider).customized) {
    candidates.add(const NotifCandidate(NotifDuJourIds.tournee, 0.5));
  }

  final serein = ref.watch(sereinToggleProvider);
  if (!serein.enabled && !serein.isLoading) {
    // Relevance au-dessus de `tournee` (0.5), sous les prompts temps-sensibles :
    // combiné au cooldown de dismiss (30j), « Serein » finit par émerger une
    // fois les autres messages profil dismissés. Knob calibrable comme
    // `kRotationJitter`.
    candidates.add(const NotifCandidate(NotifDuJourIds.serein, 0.55));
  }

  // Messages communauté/feedback — toujours éligibles, pertinence basse-moyenne
  // pour ne jamais passer devant les nudges fonctionnels/profil ci-dessus.
  candidates.add(const NotifCandidate(NotifDuJourIds.feedbackMail, 0.35));
  candidates.add(const NotifCandidate(NotifDuJourIds.whatsappCommunity, 0.3));
  candidates.add(const NotifCandidate(NotifDuJourIds.shareApp, 0.3));
  candidates.add(const NotifCandidate(NotifDuJourIds.coffeeLaurin, 0.25));

  // Fallback : garantit une file jamais vide.
  candidates.add(const NotifCandidate(NotifDuJourIds.recommencer, 0.1));

  // Jour du day store (réactif) plutôt que `DateTime.now()` échantillonné :
  // un Provider ne re-build pas tout seul à minuit — en suivant la clé jour
  // persistée, file et cap basculent ensemble.
  final dayKey = ref.watch(
    notifDuJourDayStoreProvider.select((s) => s.day),
  );
  final day = dayKey.isEmpty
      ? DateTime.now()
      : DateTime.parse(dayKey); // 'YYYY-MM-DD' → minuit local du jour clé

  // Cooldown durable : retire les messages dismissés (croix) il y a moins de
  // 30j. Utilise la même clé jour que le day store pour le `now`, pour que le
  // cooldown bascule sur la même frontière que le cap/rotation.
  final cooldown = ref
      .watch(notifDuJourDismissalStoreProvider)
      .activeCooldownIds(day);
  final eligible = cooldown.isEmpty
      ? candidates
      : [for (final c in candidates) if (!cooldown.contains(c.id)) c];

  return rankNotifQueue(eligible, notifEpochDay(day));
});
