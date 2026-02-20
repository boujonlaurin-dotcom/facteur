import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/digest_provider.dart';

/// Format du digest : "topics" (sujets du jour) ou "flat" (liste classique).
///
/// Stocké comme user preference côté backend (clé: digest_format).
/// Le changement sera appliqué au prochain digest (régénération ou lendemain).
enum DigestFormat {
  topics(
    key: 'topics',
    label: 'Sujets du jour',
    description: 'Articles groupés par sujet, avec scroll horizontal',
  ),
  flat(
    key: 'flat',
    label: 'Liste classique',
    description: 'Articles classés par pertinence',
  );

  const DigestFormat({
    required this.key,
    required this.label,
    required this.description,
  });

  final String key;
  final String label;
  final String description;

  static DigestFormat fromFormatVersion(String? formatVersion) {
    if (formatVersion == 'flat_v1') return DigestFormat.flat;
    return DigestFormat.topics;
  }
}

/// Provider for the digest format preference.
final digestFormatProvider =
    StateNotifierProvider<DigestFormatNotifier, DigestFormat>((ref) {
  return DigestFormatNotifier(ref);
});

class DigestFormatNotifier extends StateNotifier<DigestFormat> {
  final Ref _ref;

  DigestFormatNotifier(this._ref) : super(DigestFormat.topics);

  /// Initialise depuis la réponse API du digest
  void initFromDigestResponse(String? formatVersion) {
    final format = DigestFormat.fromFormatVersion(formatVersion);
    if (format != state) {
      state = format;
    }
  }

  /// Change le format du digest.
  /// Sauvegarde la préférence pour le prochain digest.
  Future<void> setFormat(DigestFormat newFormat) async {
    if (newFormat == state) return;

    state = newFormat;

    try {
      final repository = _ref.read(digestRepositoryProvider);
      await repository.updatePreference(
        key: 'digest_format',
        value: newFormat.key,
      );
    } catch (e) {
      // Silently fail — preference will be retried next time
    }
  }
}
