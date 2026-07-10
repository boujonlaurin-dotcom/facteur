import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/smart_search_result.dart';
import '../models/source_coverage.dart';
import '../models/source_model.dart';
import '../models/source_profile.dart';
import '../models/source_recent_items.dart';
import '../models/theme_source_model.dart';
import '../models/theme_suggestions_model.dart';

class SourcesRepository {
  final ApiClient _apiClient;

  SourcesRepository(this._apiClient);

  Future<List<Source>> getAllSources() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('sources');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) return [];

        if (data is List) {
          return data
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        } else if (data is Map<String, dynamic>) {
          // Possible object wrapper or error
          if (data.containsKey('curated')) {
            final result = <Source>[];
            if (data['curated'] != null) {
              result.addAll(
                (data['curated'] as List).map(
                  (json) => Source.fromJson(json as Map<String, dynamic>),
                ),
              );
            }
            if (data['custom'] != null) {
              result.addAll(
                (data['custom'] as List).map(
                  (json) => Source.fromJson(json as Map<String, dynamic>),
                ),
              );
            }
            return result;
          }
          // Log unexpected map
          print(
            'SourcesRepository: [WARNING] Received Map but expected List or Catalog: $data',
          );
        }
        return [];
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getAllSources: $e');
      rethrow;
    }
  }

  Future<List<Source>> getTrendingSources({int limit = 10}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'sources/trending',
        queryParameters: {'limit': limit},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getTrendingSources: $e');
      return [];
    }
  }

  Future<void> trustSource(String sourceId) async {
    try {
      await _apiClient.dio.post<dynamic>('sources/$sourceId/trust');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] trustSource: $e');
      rethrow;
    }
  }

  Future<void> untrustSource(String sourceId) async {
    try {
      await _apiClient.dio.delete<dynamic>('sources/$sourceId/trust');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] untrustSource: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> detectSource(String url) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'sources/detect',
        data: {'url': url},
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data!;
      }
      throw Exception('Failed to detect source');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] detectSource: $e');
      rethrow;
    }
  }

  Future<void> updateSourceSubscription(
    String sourceId,
    bool hasSubscription,
  ) async {
    try {
      await _apiClient.dio.put<dynamic>(
        'sources/$sourceId/subscription',
        data: {'has_subscription': hasSubscription},
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] updateSourceSubscription: $e');
      rethrow;
    }
  }

  Future<void> addCustomSource(String url, {String? name}) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'sources/custom',
        data: {'url': url, if (name != null) 'name': name},
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] addCustomSource: $e');
      rethrow;
    }
  }

  Future<SmartSearchResponse> smartSearch(
    String query, {
    String? contentType,
    bool expand = false,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'sources/smart-search',
        data: {
          'query': query,
          if (contentType != null) 'content_type': contentType,
          if (expand) 'expand': true,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        return SmartSearchResponse.fromJson(response.data!);
      }
      throw Exception('Smart search failed');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] smartSearch: $e');
      rethrow;
    }
  }

  Future<List<FollowedTheme>> getThemesFollowed() async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'sources/themes-followed',
      );
      if (response.statusCode == 200 && response.data is Map) {
        final themes = (response.data as Map<String, dynamic>)['themes'];
        if (themes is List) {
          return themes
              .map(
                (json) => FollowedTheme.fromJson(json as Map<String, dynamic>),
              )
              .toList();
        }
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getThemesFollowed: $e');
      return [];
    }
  }

  Future<void> logSearchAbandoned(String query) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'sources/search-abandoned',
        data: {'query': query},
      );
    } catch (_) {
      // fire-and-forget
    }
  }

  Future<List<Source>> getPepites({
    int limit = 10,
    bool forceShow = false,
  }) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'sources/pepites',
        queryParameters: {'limit': limit, if (forceShow) 'force_show': true},
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getPepites: $e');
      return [];
    }
  }

  /// Derniers contenus par source (animation de conclusion onboarding).
  /// Toujours best-effort : une erreur renvoie une liste vide, l'animation
  /// ne doit jamais bloquer la fin de l'onboarding.
  Future<List<SourceRecentItems>> fetchRecentItems(
    List<String> sourceIds, {
    int perSource = 3,
  }) async {
    if (sourceIds.isEmpty) return [];
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'sources/recent-items',
        data: {'source_ids': sourceIds, 'per_source': perSource},
      );
      final data = response.data?['sources'];
      if (response.statusCode == 200 && data is List) {
        return data
            .map(
              (json) =>
                  SourceRecentItems.fromJson(json as Map<String, dynamic>),
            )
            .toList();
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] fetchRecentItems: $e');
      return [];
    }
  }

  /// Couverture par thèmes d'une source sur les [days] derniers jours.
  /// Best-effort : une erreur renvoie une couverture vide (la section se masque).
  Future<SourceCoverage> fetchCoverage(
    String sourceId, {
    int days = 30,
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'sources/$sourceId/coverage',
        queryParameters: {'days': days},
      );
      if (response.statusCode == 200 && response.data != null) {
        return SourceCoverage.fromJson(response.data!);
      }
      return const SourceCoverage(periodLabel: '', totalCount: 0);
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] fetchCoverage: $e');
      return const SourceCoverage(periodLabel: '', totalCount: 0);
    }
  }

  /// Profil unifié d'une source — fiche source v3
  /// (`GET /sources/{id}/profile`).
  ///
  /// Contrairement à [fetchCoverage] (best-effort → vide), on **propage**
  /// l'erreur : la fiche s'appuie dessus pour basculer en fallback gracieux
  /// (couverture via `/coverage` + bouton « Réessayer ») plutôt que d'afficher
  /// un état vide trompeur.
  ///
  /// Un échec **transitoire** (timeout, coupure réseau, 5xx) est retenté
  /// jusqu'à 2 fois avec un court backoff : pendant l'onboarding la fiche est
  /// pré-chargée dès l'ouverture de l'écran, et un premier appel peut échouer
  /// le temps que la session/réseau se stabilise. On ne retente jamais une
  /// erreur définitive (4xx : 404 source absente, 422 id invalide).
  Future<SourceProfile> getSourceProfile(String sourceId) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _apiClient.dio.get<Map<String, dynamic>>(
          'sources/$sourceId/profile',
        );
        if (response.statusCode == 200 && response.data != null) {
          return SourceProfile.fromJson(response.data!);
        }
        throw Exception('Failed to load source profile');
      } catch (e) {
        if (attempt < maxAttempts && _isTransient(e)) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
          continue;
        }
        // ignore: avoid_print
        print('SourcesRepository: [ERROR] getSourceProfile: $e');
        rethrow;
      }
    }
  }

  /// Vrai si l'erreur est probablement transitoire (réseau/timeout/5xx) et
  /// donc justifie un retry. Les réponses 4xx sont définitives.
  bool _isTransient(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    if (status != null) return status >= 500;
    // Pas de réponse : timeout, connexion coupée, annulation réseau.
    return error.type != DioExceptionType.cancel;
  }

  Future<void> dismissPepiteCarousel() async {
    try {
      await _apiClient.dio.post<dynamic>('sources/pepites/dismiss');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] dismissPepiteCarousel: $e');
      rethrow;
    }
  }

  Future<ThemeSourcesResponse> getSourcesByTheme(String slug) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'sources/by-theme/$slug',
      );
      if (response.statusCode == 200 && response.data is Map) {
        return ThemeSourcesResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      return const ThemeSourcesResponse(
        curated: [],
        candidates: [],
        community: [],
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getSourcesByTheme: $e');
      rethrow;
    }
  }

  /// Footer « Étoffer [thème] » : sources poussées (Tiers 1 & 2) couvrant le
  /// thème, hors sources déjà suivies. Best-effort : un échec renvoie une
  /// réponse vide (l'UI bascule sur la seule entrée de recherche), le footer
  /// ne doit jamais casser le rendu de la Tournée.
  Future<ThemeSuggestions> suggestSourcesForTheme(String slug) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'sources/suggest-for-theme/$slug',
      );
      if (response.statusCode == 200 && response.data is Map) {
        return ThemeSuggestions.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
      return ThemeSuggestions(theme: slug, label: '', suggestions: const []);
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] suggestSourcesForTheme: $e');
      return ThemeSuggestions(theme: slug, label: '', suggestions: const []);
    }
  }
}
