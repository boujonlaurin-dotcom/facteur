import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../models/veille_config.dart';

/// Métadonnées des 9 thèmes Facteur officiels (alignés avec
/// `user_service.py:170` côté backend et `available_subtopics.dart` côté
/// front). L'ordre par défaut sert de fallback quand `/users/top-themes`
/// échoue ou quand on doit compléter les thèmes du user.
const List<({String slug, String label, String emoji})> kVeilleFacteurThemes = [
  (slug: 'tech', label: 'Technologie', emoji: '💻'),
  (slug: 'science', label: 'Science', emoji: '🔬'),
  (slug: 'society', label: 'Société', emoji: '👥'),
  (slug: 'politics', label: 'Politique', emoji: '🏛️'),
  (slug: 'environment', label: 'Environnement', emoji: '🌿'),
  (slug: 'international', label: 'Géopolitique', emoji: '🌍'),
  (slug: 'economy', label: 'Économie', emoji: '💰'),
  (slug: 'culture', label: 'Culture', emoji: '🎨'),
  (slug: 'sport', label: 'Sport', emoji: '⚽'),
];

/// Borne de l'affichage Step 1 : on ne montre jamais plus de 9 cartes
/// (les 9 thèmes Facteur), et les 2 premières (les plus pertinentes pour
/// le user) sont marquées `hot` pour le badge visuel.
const int _maxThemes = 9;
const int _hotThemesCount = 2;

({String label, String emoji}) _metaForSlug(String slug) {
  for (final t in kVeilleFacteurThemes) {
    if (t.slug == slug) return (label: t.label, emoji: t.emoji);
  }
  // Slug inconnu (ex: legacy 'sports' avec un 's') : on capitalise pour le
  // label et on tombe sur un emoji neutre.
  final label = slug.isEmpty
      ? slug
      : slug[0].toUpperCase() + slug.substring(1);
  return (label: label, emoji: '📰');
}

/// Helper synchrone — renvoie le label FR canonique d'un thème Facteur,
/// ou capitalise le slug si inconnu. Permet aux callers (submit, headers)
/// d'éviter une dépendance asynchrone sur `veilleThemesProvider`.
String veilleThemeLabelForSlug(String slug) => _metaForSlug(slug).label;

String _metaText(int? articleCount) {
  if (articleCount == null) return 'Disponible';
  if (articleCount == 0) return 'Peu d\'actualité · 14 j';
  if (articleCount == 1) return '1 article · 14 j';
  return '$articleCount articles · 14 j';
}

/// Charge les thèmes du user (`GET /api/users/top-themes`) et complète
/// avec les autres thèmes Facteur jusqu'à 9 cartes max. Les top-themes
/// arrivent en premier (sortis triés par poids côté backend).
///
/// Fallback : si l'API échoue, on renvoie les 9 thèmes Facteur sans
/// counts (meta='Disponible'). Aucune `throw` — l'UI Step 1 doit
/// toujours être utilisable.
final veilleThemesProvider = FutureProvider<List<VeilleTheme>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);

  // Set des slugs canoniques — sert de filtre pour ignorer les valeurs
  // legacy de `user_interests.interest_slug` (ex. `climat`, `sports`)
  // qui ne sont pas reconnues par la contrainte SQL backend
  // `ck_source_theme_valid`. Sans ce filtre, l'utilisateur peut
  // sélectionner un thème inconnu et faire échouer `/suggestions/sources`.
  final canonicalSlugs = {for (final t in kVeilleFacteurThemes) t.slug};

  List<({String slug, int articleCount})> userThemes = const [];
  try {
    final response = await apiClient.dio.get<dynamic>('users/top-themes');
    final raw = response.data as List<dynamic>;
    userThemes = raw.whereType<Map<String, dynamic>>().map((row) {
      return (
        slug: row['interest_slug'] as String,
        articleCount: (row['article_count'] as num?)?.toInt() ?? 0,
      );
    }).where((t) => canonicalSlugs.contains(t.slug)).toList();
  } on DioException {
    // Fallback silencieux — UI affichera les thèmes Facteur sans counts.
  }

  final seen = <String>{};
  final ordered = <({String slug, int? articleCount})>[];

  for (final t in userThemes) {
    if (seen.add(t.slug)) {
      ordered.add((slug: t.slug, articleCount: t.articleCount));
    }
  }
  for (final t in kVeilleFacteurThemes) {
    if (ordered.length >= _maxThemes) break;
    if (seen.add(t.slug)) {
      ordered.add((slug: t.slug, articleCount: null));
    }
  }

  final result = <VeilleTheme>[];
  for (var i = 0; i < ordered.length; i++) {
    final entry = ordered[i];
    final meta = _metaForSlug(entry.slug);
    result.add(
      VeilleTheme(
        id: entry.slug,
        label: meta.label,
        emoji: meta.emoji,
        iconKey: entry.slug,
        meta: _metaText(entry.articleCount),
        hot: i < _hotThemesCount && entry.articleCount != null,
      ),
    );
  }
  return result;
});
