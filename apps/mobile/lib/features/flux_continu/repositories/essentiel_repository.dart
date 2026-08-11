import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';
import '../../feed/models/content_model.dart';
import '../models/flux_continu_models.dart';

/// Résultat de `GET /api/essentiel` : les articles transversaux + le delta
/// « N nouveaux articles » (`new_since_this_morning`, borné côté backend) +
/// le carrousel semi-éditorialisé du jour (Story 32.1, `carousel`, `null` hors
/// édition du jour ou si aucun type éligible). `newSinceMorning == 0` ⇒ pas de
/// pastille sur le héros.
typedef EssentielFetchResult = ({
  List<EssentielArticle> articles,
  int newSinceMorning,
  FeedCarouselData? carousel,
});

/// `GET /api/essentiel` — Story 9.1/9.2.
///
/// Renvoie jusqu'à 5 articles transversaux cross-topic pour alimenter la
/// carte hi-fi "L'Essentiel du jour" en haut du feed. L'endpoint backend est
/// strictement read-only (réutilise la chaîne de fallback de `/api/digest`),
/// et peut renvoyer 202 `{"status":"preparing"}` quand aucun digest n'est
/// encore prêt — le provider traite ce cas comme une liste vide et conserve
/// son fallback construit depuis le digest classique.
class EssentielRepository {
  final ApiClient _apiClient;

  EssentielRepository(this._apiClient);

  /// Renvoie la liste des articles de l'Essentiel, ou `null` si l'endpoint
  /// n'a rien servi (202 ou erreur réseau). Le provider décide alors s'il
  /// veut fallback ou afficher une section vide.
  ///
  /// [serein] force le mode côté backend (`?serein=`) au lieu de dépendre de la
  /// persistance DB de la préférence : évite la race au toggle (refetch avant
  /// que la préférence soit écrite). Absent ⇒ le backend lit la préférence DB.
  ///
  /// [date] cible une **édition passée** (`?target_date=YYYY-MM-DD`) pour le
  /// sélecteur de date de l'Essentiel (EPIC « Lettre du jour »). Absent ⇒
  /// aujourd'hui (l'appel historique du flux reste valide). Même format que
  /// `DigestRepository.getDigest`/`fetchBothDigests`.
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'essentiel',
        queryParameters: {
          if (serein != null) 'serein': serein,
          if (date != null) 'target_date': date.toIso8601String().split('T')[0],
        },
      );
      if (response.statusCode == 202) {
        return null;
      }
      if (response.statusCode != 200 || response.data is! Map) {
        return null;
      }
      final data = response.data as Map<String, dynamic>;
      final raw = (data['articles'] as List?) ?? const [];
      final articles = raw
          .whereType<Map<String, dynamic>>()
          .map(EssentielArticle.fromJson)
          .toList(growable: false);
      // Story 32.1 — carrousel du jour (additif, peut être absent/null).
      final rawCarousel = data['carousel'];
      final carousel = rawCarousel is Map<String, dynamic>
          ? FeedCarouselData.fromJson(rawCarousel)
          : null;
      return (
        articles: articles,
        newSinceMorning: (data['new_since_this_morning'] as int?) ?? 0,
        carousel: carousel,
      );
    } on DioException catch (e) {
      // ignore: avoid_print
      print('EssentielRepository: fetch failed: ${e.message}');
      return null;
    }
  }

  /// `GET /api/essentiel/more` — Story 33.3.
  ///
  /// Deux recommandations Essentiel **inédites**, pour honorer « Plus
  /// d'articles ? » quand la réserve locale (carrousel du jour) est épuisée.
  /// [excludeIds] doit porter tout ce que le client a déjà : slate ∪ articles
  /// décidés ∪ pool local — c'est la seule garde contre un doublon.
  ///
  /// Renvoie le **JSON brut** des articles, pas des `EssentielArticle` : le
  /// payload est persisté tel quel par `essentielExtraArticlesProvider` pour
  /// survivre au cold-boot, et se re-parse à l'identique. `null` ⇒ échec
  /// réseau (à distinguer d'une liste vide, qui veut dire « rien d'inédit »).
  Future<List<Map<String, dynamic>>?> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
  }) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'essentiel/more',
        queryParameters: {
          'limit': limit,
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
        },
      );
      if (response.statusCode != 200 || response.data is! Map) return null;
      final data = response.data as Map<String, dynamic>;
      return ((data['articles'] as List?) ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    } on DioException catch (e) {
      // ignore: avoid_print
      print('EssentielRepository: fetchMore failed: ${e.message}');
      return null;
    }
  }

  /// `POST /api/essentiel/triage` — Story 33.1.
  ///
  /// Envoie un batch de décisions de tri. **Collecte seule** côté backend :
  /// aucun poids de reco ne bouge (seul `later` déclenche le save existant,
  /// exactement comme le bouton signet de la carte).
  ///
  /// Renvoie `true` si le batch a été accepté. Un échec n'est pas une erreur
  /// pour l'utilisateur — le tri ne doit jamais attendre le réseau — mais le
  /// provider garde les décisions en attente pour les renvoyer plus tard.
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async {
    if (decisions.isEmpty) return true;
    try {
      final response = await _apiClient.dio.post<dynamic>(
        'essentiel/triage',
        data: {
          'digest_date': digestDate,
          'slate_size': slateSize,
          'decisions': decisions,
        },
      );
      return response.statusCode == 200;
    } on DioException catch (e) {
      // 4xx = payload que le backend refusera toujours (rang hors slate,
      // décision inconnue) : le renvoyer en boucle ne servirait à rien.
      final status = e.response?.statusCode ?? 0;
      if (status >= 400 && status < 500) {
        // ignore: avoid_print
        print('EssentielRepository: triage rejected ($status) — dropped');
        return true;
      }
      // ignore: avoid_print
      print('EssentielRepository: postTriage failed: ${e.message}');
      return false;
    }
  }
}

final essentielRepositoryProvider = Provider<EssentielRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EssentielRepository(apiClient);
});
