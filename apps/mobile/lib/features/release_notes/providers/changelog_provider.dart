import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/changelog_entry.dart';
import '../services/changelog_service.dart';

final changelogServiceProvider = Provider<ChangelogService>((ref) {
  return ChangelogService();
});

/// Version applicative résolue via `PackageInfo`. Cached pour la durée de la
/// session.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Liste des releases non vues. Vide si :
/// - chargement en cours / en erreur,
/// - premier lancement (on stamp silencieusement),
/// - tout vu.
final unseenReleasesProvider = FutureProvider<List<ChangelogRelease>>((ref) async {
  final service = ref.watch(changelogServiceProvider);
  final currentVersion = await ref.watch(appVersionProvider.future);

  final stamped = await service.bootstrapIfFirstLaunch(currentVersion);
  if (stamped) return const [];

  final released = await service.loadReleased();
  final lastSeen = await service.readLastSeen();
  return service.unseenReleases(
    all: released,
    currentVersion: currentVersion,
    lastSeen: lastSeen,
  );
});

/// Appelé par le bouton "Compris" du modal ET par le `×` du bandeau.
/// Marque la version courante comme vue et invalide le provider pour faire
/// disparaître l'UI.
Future<void> markChangelogSeen(WidgetRef ref) async {
  final service = ref.read(changelogServiceProvider);
  final currentVersion = await ref.read(appVersionProvider.future);
  await service.markSeen(currentVersion);
  ref.invalidate(unseenReleasesProvider);
}
