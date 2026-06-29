import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../digest/models/digest_models.dart';
import '../../digest/models/dual_digest_response.dart';
import '../../digest/providers/digest_provider.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/repositories/digest_repository.dart';
import '../models/flux_continu_models.dart';
import '../repositories/essentiel_repository.dart';
import '../utils/morning_ritual_format.dart';
import 'flux_continu_provider.dart';
import 'selected_edition_date_provider.dart';

/// EPIC « Lettre du jour » — contenu Essentiel **lecture seule** pour une
/// sélection de date donnée.
///
/// Volontairement séparé de `digestProvider` (widget home, complétion, streak,
/// gate `isEditionReady`) et de `fluxContinuProvider` (qui recomposerait toute
/// la tournée) : repurposer l'un ou l'autre pour des dates arbitraires
/// polluerait leurs invariants. Ce provider ne sert QUE le bloc Essentiel
/// (héros + Actus du jour + citation), jamais les sections tournée live.
class EditionEssentielState {
  final EditionSelection selection;
  final List<EssentielArticle> heroArticles;
  final List<DigestTopic> topics;
  final QuoteResponse? quote;

  /// Aucune lettre propre à servir pour ce jour : soit le backend n'a servi
  /// qu'un fallback cloné (`is_stale_fallback`), soit rien du tout. Le screen
  /// rend alors une carte « Pas d'édition pour … » plutôt que de présenter du
  /// contenu d'un autre jour comme la lettre demandée.
  final bool isStaleOrEmpty;

  /// Vue agrégée « Cette semaine » (vs un jour unique).
  final bool isWeek;

  const EditionEssentielState({
    required this.selection,
    this.heroArticles = const [],
    this.topics = const [],
    this.quote,
    this.isStaleOrEmpty = false,
    this.isWeek = false,
  });
}

/// Fenêtre de la rétro « Cette semaine » = 7 jours (J-0 inclus). J-0 vient du
/// flux (0 réseau) ; J-1…J-6 sont chargés par fan-out borné.
const int kEditionWeekPastDays = 6;

/// Concurrence du fan-out « Cette semaine » (≤ N jours en vol à la fois).
const int kEditionWeekConcurrency = 3;

/// Plafonds de l'agrégation hebdo.
const int kEditionWeekMaxHero = 5;
const int kEditionWeekMaxTopics = 6;

final editionEssentielProvider =
    AsyncNotifierProvider<EditionEssentielNotifier, EditionEssentielState>(
  EditionEssentielNotifier.new,
);

class EditionEssentielNotifier extends AsyncNotifier<EditionEssentielState> {
  late EssentielRepository _essentielRepo;
  late DigestRepository _digestRepo;

  /// Cache mémoire par jour (clé = `YYYY-MM-DD`), vidé quand l'utilisateur ou
  /// le mode serein change. Permet à « Cette semaine » de réutiliser les jours
  /// déjà chargés et rend la re-sélection d'un jour instantanée.
  final Map<String, _DayData> _dayCache = {};
  String? _cacheUser;
  bool? _cacheSerein;

  @override
  Future<EditionEssentielState> build() async {
    _essentielRepo = ref.read(essentielRepositoryProvider);
    _digestRepo = ref.read(digestRepositoryProvider);

    final selection = ref.watch(selectedEditionDateProvider);
    final serein = ref.watch(sereinToggleProvider.select((s) => s.enabled));
    final userId = ref.watch(authStateProvider.select((s) => s.user?.id));

    // Invalide le cache quand le contexte (user/mode) change : on ne mélange
    // jamais des jours chargés en normal avec une vue sereine, ni le cache d'un
    // user avec un autre.
    if (_cacheUser != userId || _cacheSerein != serein) {
      _dayCache.clear();
      _cacheUser = userId;
      _cacheSerein = serein;
    }

    // Switch statement (pas expression) : l'arm `EditionToday` est synchrone
    // (auto-wrappée en Future par `async`), les autres sont des Future.
    switch (selection) {
      case EditionToday():
        return _buildToday();
      case EditionPastDay(:final date):
        return _buildPastDay(date, serein: serein);
      case EditionWeek():
        return _buildWeek(serein: serein);
    }
  }

  // ── Aujourd'hui : 0 réseau, lu depuis le flux déjà construit ──────────────

  EditionEssentielState _buildToday() {
    final flux = ref.read(fluxContinuProvider).valueOrNull;
    final hero = _heroFromFlux(flux);
    final topics = _topicsFromFlux(flux);
    return EditionEssentielState(
      selection: const EditionToday(),
      heroArticles: hero,
      topics: topics,
      quote: flux?.quote,
      isStaleOrEmpty: hero.isEmpty && topics.isEmpty,
      isWeek: false,
    );
  }

  List<EssentielArticle> _heroFromFlux(FluxContinuState? flux) {
    if (flux == null) return const [];
    for (final s in flux.sections) {
      if (s is EssentielSection) return s.articles;
    }
    return const [];
  }

  List<DigestTopic> _topicsFromFlux(FluxContinuState? flux) {
    if (flux == null) return const [];
    for (final s in flux.sections) {
      // "Actus du jour" = DigestTopicSection legacy (kind=essentiel).
      if (s is DigestTopicSection && s.kind == SectionKind.essentiel) {
        return s.topics;
      }
    }
    return const [];
  }

  // ── Jour passé ────────────────────────────────────────────────────────────

  Future<EditionEssentielState> _buildPastDay(
    DateTime date, {
    required bool serein,
  }) async {
    final day = await _loadDay(date, serein: serein);
    return EditionEssentielState(
      selection: EditionPastDay(date),
      heroArticles: day.heroArticles,
      topics: day.topics,
      quote: day.quote,
      isStaleOrEmpty: day.isStaleOrEmpty,
      isWeek: false,
    );
  }

  /// Charge (héros + Actus + citation) d'un jour unique, avec mitigation stale.
  /// Mémoïsé dans [_dayCache].
  Future<_DayData> _loadDay(DateTime date, {required bool serein}) async {
    final cacheKey = editionDayKey(date);
    final cached = _dayCache[cacheKey];
    if (cached != null) return cached;

    final results = await Future.wait<Object?>([
      _fetchHeroSafe(date, serein),
      _fetchDualSafe(date),
    ]);
    final hero = results[0] as List<EssentielArticle>?;
    final dual = results[1] as DualDigestResponse?;

    final digest = serein
        ? (dual?.serein ?? dual?.normal)
        : (dual?.normal ?? dual?.serein);

    // Mitigation client : ne jamais présenter un fallback cloné (qui peut être
    // le contenu d'un AUTRE jour) comme la lettre du jour demandé.
    if (digest == null ||
        digest.isStaleFallback ||
        hero == null ||
        hero.isEmpty) {
      const data = _DayData(
        heroArticles: [],
        topics: [],
        quote: null,
        isStaleOrEmpty: true,
      );
      _dayCache[cacheKey] = data;
      return data;
    }

    // `digest` et `hero` sont promus non-null par le garde ci-dessus.
    final topics = digest.topics
        .where((t) => t.articles.isNotEmpty)
        .toList(growable: false);
    final data = _DayData(
      heroArticles: hero,
      topics: topics,
      quote: digest.quote,
      isStaleOrEmpty: false,
    );
    _dayCache[cacheKey] = data;
    return data;
  }

  Future<List<EssentielArticle>?> _fetchHeroSafe(
    DateTime date,
    bool serein,
  ) async {
    try {
      return await _essentielRepo.fetch(serein: serein, date: date);
    } catch (_) {
      return null;
    }
  }

  Future<DualDigestResponse?> _fetchDualSafe(DateTime date) async {
    try {
      return await _digestRepo.fetchBothDigests(date: date);
    } catch (_) {
      // 202 preparing / 5xx / réseau → traité comme « pas d'édition ».
      return null;
    }
  }

  // ── Cette semaine : agrégation client bornée ──────────────────────────────

  Future<EditionEssentielState> _buildWeek({required bool serein}) async {
    final pastDates = editionPastDays(kEditionWeekPastDays);
    final dayResults = await _boundedLoadDays(pastDates, serein: serein);

    // J-0 depuis le flux déjà construit (0 réseau).
    final flux = ref.read(fluxContinuProvider).valueOrNull;
    final allHero = <EssentielArticle>[..._heroFromFlux(flux)];
    final allTopics = <DigestTopic>[..._topicsFromFlux(flux)];

    for (final d in dayResults) {
      if (d.isStaleOrEmpty) continue; // jours manquants ignorés
      allHero.addAll(d.heroArticles);
      allTopics.addAll(d.topics);
    }

    final hero = _dedupAndRankHero(allHero);
    final topics = _dedupAndRankTopics(allTopics);

    return EditionEssentielState(
      selection: const EditionWeek(),
      heroArticles: hero,
      topics: topics,
      quote: null, // pas de citation unique pour une rétro hebdo
      isStaleOrEmpty: hero.isEmpty && topics.isEmpty,
      isWeek: true,
    );
  }

  /// Fan-out borné : ≤ [kEditionWeekConcurrency] jours en vol à la fois.
  Future<List<_DayData>> _boundedLoadDays(
    List<DateTime> dates, {
    required bool serein,
  }) async {
    final out = <_DayData>[];
    for (var i = 0; i < dates.length; i += kEditionWeekConcurrency) {
      final chunk = dates.sublist(
        i,
        math.min(i + kEditionWeekConcurrency, dates.length),
      );
      final loaded = await Future.wait(
        chunk.map((d) => _loadDay(d, serein: serein)),
      );
      out.addAll(loaded);
    }
    return out;
  }

  /// Dédup par `contentId` puis re-tri par `rank` (1 = lead), top N.
  List<EssentielArticle> _dedupAndRankHero(List<EssentielArticle> all) {
    final seen = <String>{};
    final deduped = <EssentielArticle>[];
    for (final a in all) {
      if (a.contentId.isEmpty) continue;
      if (seen.add(a.contentId)) deduped.add(a);
    }
    deduped.sort((a, b) {
      // rank absent/0 relégué en fin.
      final ra = a.rank <= 0 ? 1 << 30 : a.rank;
      final rb = b.rank <= 0 ? 1 << 30 : b.rank;
      return ra.compareTo(rb);
    });
    return deduped.take(kEditionWeekMaxHero).toList(growable: false);
  }

  /// Dédup par `topicId` (fallback `label`) puis re-tri par `topicScore` desc,
  /// `rank` asc en départage, top N.
  List<DigestTopic> _dedupAndRankTopics(List<DigestTopic> all) {
    final seen = <String>{};
    final deduped = <DigestTopic>[];
    for (final t in all) {
      final key = t.topicId.isNotEmpty ? t.topicId : t.label;
      if (key.isEmpty) continue;
      if (seen.add(key)) deduped.add(t);
    }
    deduped.sort((a, b) {
      final byScore = b.topicScore.compareTo(a.topicScore);
      if (byScore != 0) return byScore;
      return a.rank.compareTo(b.rank);
    });
    return deduped.take(kEditionWeekMaxTopics).toList(growable: false);
  }
}

/// Données brutes d'un jour (avant projection en [EditionEssentielState]).
class _DayData {
  final List<EssentielArticle> heroArticles;
  final List<DigestTopic> topics;
  final QuoteResponse? quote;
  final bool isStaleOrEmpty;

  const _DayData({
    required this.heroArticles,
    required this.topics,
    required this.quote,
    required this.isStaleOrEmpty,
  });
}
