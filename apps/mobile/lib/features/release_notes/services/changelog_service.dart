import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/changelog_entry.dart';

/// Clé SharedPreferences : dernière version vue par l'utilisateur. Tant que
/// `currentVersion > lastSeen`, les entrées entre les deux sont surfacées.
const String kLastSeenChangelogVersionKey = 'last_seen_changelog_version';

const String _kChangelogAssetPath = 'assets/changelog.json';

class ChangelogService {
  ChangelogService({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;

  Future<List<ChangelogRelease>> loadReleased() async {
    final raw = await (_bundle?.loadString(_kChangelogAssetPath) ??
        rootBundle.loadString(_kChangelogAssetPath));
    final decoded = json.decode(raw) as Map<String, dynamic>;
    final released = (decoded['released'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ChangelogRelease.fromJson)
        .toList(growable: false);
    return released;
  }

  /// Renvoie les releases avec `lastSeen < version <= currentVersion`. Si
  /// `lastSeen` est null (premier lancement), renvoie liste vide — le caller
  /// doit stamper `currentVersion` pour éviter d'inonder l'user au prochain
  /// démarrage.
  List<ChangelogRelease> unseenReleases({
    required List<ChangelogRelease> all,
    required String currentVersion,
    required String? lastSeen,
  }) {
    if (lastSeen == null) return const [];
    return all
        .where((r) =>
            compareSemver(r.version, lastSeen) > 0 &&
            compareSemver(r.version, currentVersion) <= 0)
        .toList(growable: false);
  }

  Future<String?> readLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kLastSeenChangelogVersionKey);
  }

  Future<void> markSeen(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLastSeenChangelogVersionKey, version);
  }

  /// Au tout premier lancement (clé absente), stamp silencieusement la version
  /// courante : l'user fraîchement installé ne doit pas voir l'historique
  /// complet de la 1ʳᵉ ouverture. Renvoie true si on a stampé.
  Future<bool> bootstrapIfFirstLaunch(String currentVersion) async {
    final existing = await readLastSeen();
    if (existing != null) return false;
    await markSeen(currentVersion);
    return true;
  }
}

/// Compare deux versions semver simples (3 segments, sans pre-release). Renvoie
/// -1, 0 ou 1. Tolère les versions avec moins de segments (`1.2` ≡ `1.2.0`).
int compareSemver(String a, String b) {
  final pa = _parseSegments(a);
  final pb = _parseSegments(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.length ? pa[i] : 0;
    final vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

List<int> _parseSegments(String version) {
  // Supporte le format `X.Y.Z+B` (pubspec) — on jette le suffixe build.
  final clean = version.split('+').first.split('-').first;
  return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
}
