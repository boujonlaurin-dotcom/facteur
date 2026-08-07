import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/notification_preferences_api_service.dart';
import 'package:facteur/core/services/posthog_service.dart';
import 'package:facteur/features/notifications/widgets/notification_activation_modal.dart';

enum FeedLoadMilestone {
  firstPaint('first_paint'),
  digestVisible('digest_visible'),
  fullyLoaded('fully_loaded');

  const FeedLoadMilestone(this.eventValue);
  final String eventValue;
}

class AnalyticsService {
  final ApiClient? _apiClient;
  final PostHogService? _posthog;
  String? _deviceId;
  String? _sessionId;
  DateTime? _sessionStartTime;
  String? _appVersion;

  AnalyticsService(ApiClient this._apiClient, {PostHogService? posthog})
      : _posthog = posthog;

  /// No-op constructor used when upstream deps (Supabase) aren't available
  /// — e.g. widget tests that don't initialize the app harness. Every
  /// `trackXxx` becomes a silent no-op.
  AnalyticsService.disabled()
      : _apiClient = null,
        _posthog = null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('analytics_device_id');
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString('analytics_device_id', _deviceId!);
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Best-effort — version tracking degrades gracefully if unavailable
    }
  }

  Future<void> startSession({bool isOrganic = true}) async {
    _sessionId = const Uuid().v4();
    _sessionStartTime = DateTime.now();
    final localDate = _sessionStartTime!.toIso8601String().split('T').first;
    // Sonde de périmètre : « ce compte a-t-il personnalisé l'ordre de sa
    // Tournée ? ». C'est du SharedPreferences **local**, donc invisible en DB —
    // c'est la seule façon de savoir combien de comptes sont concernés par une
    // règle d'ordonnancement qui recouvre l'ordre manuel.
    final prefs = await SharedPreferences.getInstance();
    final tourneeCustomized = prefs.getBool(_kTourneeCustomizedPrefKey) ?? false;

    await _logEvent('session_start', {
      'session_id': _sessionId,
      'is_organic': isOrganic,
      'platform': defaultTargetPlatform.toString(),
      'local_date': localDate,
      'tournee_customized': tourneeCustomized,
      if (_appVersion != null) 'app_version': _appVersion,
    });
    // Story 14.1 — PostHog uses `app_open` as the conventional event name
    // for DAU/retention computation. We mirror session_start to it.
    await _capturePostHog('app_open', {
      'session_id': _sessionId,
      'is_organic': isOrganic,
      'platform': defaultTargetPlatform.toString(),
      'local_date': localDate,
      if (_appVersion != null) 'app_version': _appVersion,
    });
  }

  Future<void> endSession() async {
    if (_sessionStartTime == null) return;

    final sessionStartTime = _sessionStartTime!;
    final sessionId = _sessionId;
    final duration = DateTime.now().difference(sessionStartTime).inSeconds;

    // Clear the in-memory session before awaiting I/O so a quick
    // pause→resume cycle can start a fresh session immediately.
    _sessionId = null;
    _sessionStartTime = null;

    // Vide le buffer d'impressions AVANT `session_end` : `endSession` est
    // appelée sur `AppLifecycleState.paused` (cf. `app.dart`), c'est le dernier
    // moment garanti où le process tourne encore.
    await flushPendingEvents();

    await _logEvent('session_end', {
      'session_id': sessionId,
      'duration_seconds': duration,
    });
  }

  bool get hasActiveSession => _sessionStartTime != null;

  // ──────────────────────────────────────────────────────────────
  // Unified content interaction methods (GAFAM-aligned)
  // Use these for all new code. See 03-CONTEXT.md for rationale.
  // ──────────────────────────────────────────────────────────────

  /// Enregistre une interaction contenu unifiée (feed ou digest).
  /// Remplace les méthodes fragmentées (trackArticleRead, etc.)
  Future<void> trackContentInteraction({
    required String action, // read, save, dismiss, pass
    required String surface, // feed, digest
    required String contentId,
    required String sourceId,
    List<String> topics = const [],
    int? position,
    int timeSpentSeconds = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'action': action,
      'surface': surface,
      'content_id': contentId,
      'source_id': sourceId,
      'topics': topics,
      'atomic_themes': null, // Forward-compatible for Camembert
      'position': position,
      'time_spent_seconds': timeSpentSeconds,
    };
    await _logEvent('content_interaction', props);

    // Story 14.1 — dedicated PostHog events for clean funnel/retention.
    if (action == 'read') {
      await _capturePostHog('article_read', props);
    }
  }

  /// Une décision de tri sur la carte « Ton Essentiel » (Story 33.1).
  ///
  /// Première famille d'events `essentiel_*` du produit. Ce qui la rend utile
  /// et que `content_interaction` ne porte pas : [rank] **dans le slate figé**
  /// + [slateSize], soit le dénominateur qui manquait à la jauge de ranking, et
  /// [latencyMs], qui distingue le tri réfléchi du tri fait en scrollant.
  Future<void> trackEssentielTriage({
    required String decision,
    required String contentId,
    required int rank,
    required int slateSize,
    required String decidedVia,
    int? latencyMs,
  }) async {
    await _logEvent('essentiel_triage_decision', {
      'session_id': _sessionId,
      'decision': decision,
      'content_id': contentId,
      'rank': rank,
      'slate_size': slateSize,
      'decided_via': decidedVia,
      'latency_ms': latencyMs,
    });
  }

  /// Fin d'un tri complet — un event par session de tri, pas par article.
  Future<void> trackEssentielTriageSession({
    required int slateSize,
    required int kept,
    required int later,
    required int passed,
    int? durationMs,
  }) async {
    await _logEvent('essentiel_triage_session', {
      'session_id': _sessionId,
      'slate_size': slateSize,
      'kept': kept,
      'later': later,
      'passed': passed,
      'duration_ms': durationMs,
    });
  }

  /// « Lu jusqu'au bout » (Epic 30).
  ///
  /// Émis **au moment de l'événement**, jamais depuis `dispose()`. Distinct de
  /// [trackArticleRead], qui reste un événement de durée.
  ///
  /// Les propriétés sont là pour éviter de refaire l'erreur du seuil
  /// `reading_progress >= 90` : sans [isPartial] ni [renderMode], on
  /// recompterait le type d'article plutôt que la lecture. [scrollable]
  /// désambiguïse enfin le bucket « progression 0 » (rebond vs article court lu
  /// en entier).
  Future<void> trackArticleFinished({
    required String contentId,
    required String sourceId,
    required String completionSource,
    required bool isPartial,
    required String renderMode,
    required bool reachedFooterPermanent,
    required int progressRaw,
    required int timeSpentSeconds,
    required bool scrollable,
    required int articleCharCount,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'source_id': sourceId,
      'completion_source': completionSource,
      'is_partial': isPartial,
      'render_mode': renderMode,
      'reached_footer_permanent': reachedFooterPermanent,
      'progress_raw': progressRaw,
      'time_spent_seconds': timeSpentSeconds,
      'scrollable': scrollable,
      'article_char_count': articleCharCount,
    };
    await _logEvent('article_finished', props);
    await _capturePostHog('article_finished', props);
  }

  /// Enregistre une session digest complète.
  Future<void> trackDigestSession({
    required String digestDate,
    required int articlesRead,
    required int articlesSaved,
    required int articlesDismissed,
    required int articlesPassed,
    required int totalTimeSeconds,
    required bool closureAchieved,
    required int streak,
  }) async {
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'articles_read': articlesRead,
      'articles_saved': articlesSaved,
      'articles_dismissed': articlesDismissed,
      'articles_passed': articlesPassed,
      'total_time_seconds': totalTimeSeconds,
      'closure_achieved': closureAchieved,
      'streak': streak,
    };
    await _logEvent('digest_session', props);
    await _capturePostHog('digest_session', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Rituel matinal « Ton édition vient d'arriver » (Story 28.1)
  // ──────────────────────────────────────────────────────────────

  /// L'écran enveloppe `/edition` s'est affiché au premier open du jour.
  Future<void> trackMorningRitualShown({required String dayKey}) async {
    final props = {'session_id': _sessionId, 'day_key': dayKey};
    await _logEvent('morning_ritual_shown', props);
    await _capturePostHog('morning_ritual_shown', props);
  }

  /// L'utilisateur a tapé « Ouvrir l'édition ». [waitedMs] = temps écoulé entre
  /// l'affichage et le tap (utile pour calibrer le délai borné).
  Future<void> trackMorningRitualOpened({
    required String dayKey,
    int? waitedMs,
  }) async {
    final props = {
      'session_id': _sessionId,
      'day_key': dayKey,
      if (waitedMs != null) 'waited_ms': waitedMs,
    };
    await _logEvent('morning_ritual_opened', props);
    await _capturePostHog('morning_ritual_opened', props);
  }

  /// Enregistre une session feed complète.
  Future<void> trackFeedSession({
    required double scrollDepthPercent,
    required int itemsViewed,
    required int itemsInteracted,
    required int totalTimeSeconds,
  }) async {
    await _logEvent('feed_session', {
      'session_id': _sessionId,
      'scroll_depth_percent': scrollDepthPercent,
      'items_viewed': itemsViewed,
      'items_interacted': itemsInteracted,
      'total_time_seconds': totalTimeSeconds,
    });
  }

  /// Track the Ground News comparison screen open (H2 signal, Story 14.1).
  Future<void> trackComparisonViewed({
    required String clusterId,
    int sourcesCount = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'cluster_id': clusterId,
      'sources_count': sourcesCount,
    };
    await _logEvent('comparison_viewed', props);
    await _capturePostHog('comparison_viewed', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Legacy methods — deprecated, use unified methods above
  // ──────────────────────────────────────────────────────────────

  /// @deprecated Use [trackContentInteraction] with action='read' instead.
  ///
  /// Story 14.1 — even though this is deprecated, it's still the only call
  /// site for feed/detail reading flows (which carry real `timeSpentSeconds`).
  /// We MUST mirror to PostHog from here too, otherwise `article_read` would
  /// never fire from the surfaces where users actually spend reading time. The
  /// digest "save" flow that uses `trackContentInteraction` hardcodes
  /// `timeSpentSeconds: 0`.
  ///
  /// Epic 30 — l'ancien `article_completed` dérivé d'un seuil de 30 s a été
  /// retiré : la médiane de temps par article est de 20 s, il sous-comptait
  /// donc structurellement, et surtout il définissait « terminé » par une
  /// durée. La complétion est désormais un événement propre,
  /// [trackArticleFinished].
  Future<void> trackArticleRead(
    String contentId,
    String sourceId,
    int timeSpentSeconds,
  ) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'source_id': sourceId,
      'time_spent_seconds': timeSpentSeconds,
    };
    await _logEvent('article_read', props);

    await _capturePostHog('article_read', props);
  }

  /// @deprecated Use [trackFeedSession] instead.
  Future<void> trackFeedScroll(
    double scrollDepthPercent,
    int itemsViewed,
  ) async {
    await _logEvent('feed_scroll', {
      'session_id': _sessionId,
      'scroll_depth_percent': scrollDepthPercent,
      'items_viewed': itemsViewed,
    });
  }

  /// @deprecated Use [trackFeedSession] instead.
  Future<void> trackFeedComplete() async {
    await _logEvent('feed_complete', {'session_id': _sessionId});
  }

  /// Mesure la progression du chargement progressif du feed.
  /// [durationMs] : ms depuis le mount du `FeedScreen`.
  Future<void> trackFeedLoadTiming({
    required FeedLoadMilestone milestone,
    required int durationMs,
  }) async {
    final props = {
      'session_id': _sessionId,
      'milestone': milestone.eventValue,
      'duration_ms': durationMs,
    };
    await _logEvent('feed_load_timing', props);
    await _capturePostHog('feed_load_timing', props);
  }

  Future<void> trackSourceAdd(String sourceId) async {
    await _logEvent('source_add', {'source_id': sourceId});
    await _capturePostHog('source_added', {'source_id': sourceId});
  }

  Future<void> trackSourceRemove(String sourceId) async {
    await _logEvent('source_remove', {'source_id': sourceId});
  }

  /// Issue de l'enregistrement des sources en fin d'onboarding.
  ///
  /// Rend OBSERVABLE en production l'écart "sources demandées → enregistrées".
  /// Avant, un échec n'était qu'un `debugPrint` (invisible en release) → classe
  /// de bug "enregistrement silencieux". `failed` = l'appel onboarding lui-même
  /// n'a pas abouti (tous les retries KO).
  Future<void> trackOnboardingSourcesRegistered({
    required int requested,
    required int created,
    bool failed = false,
  }) async {
    final props = {
      'session_id': _sessionId,
      'requested': requested,
      'created': created,
      // signal clé pour l'alerting : des sources demandées mais 0 enregistrée
      'missing': failed ? requested : (requested - created).clamp(0, requested),
      'failed': failed,
    };
    await _logEvent('onboarding_sources_registered', props);
    await _capturePostHog('onboarding_sources_registered', props);
  }

  /// Étape d'onboarding vue ou franchie (story 31.1).
  ///
  /// Avant, une seule des treize étapes émettait un event : impossible de dire
  /// où le parcours se perd. `stepName` est une clé stable (snake case), pas une
  /// chaîne d'UI ; `stepIndex` est l'index global, monotone dans le parcours.
  /// PostHog uniquement : c'est un funnel, pas une donnée produit à stocker.
  Future<void> trackOnboardingStep({
    required String event,
    required String stepName,
    required int stepIndex,
    required int totalSteps,
  }) async {
    await _capturePostHog(event, {
      'session_id': _sessionId,
      'step_name': stepName,
      'step_index': stepIndex,
      'total_steps': totalSteps,
    });
  }

  /// Écran d'amorce notif (étape 3/4) affiché.
  Future<void> trackOnboardingNotifPrimingShown({required int step}) async {
    await _capturePostHog('onboarding_notif_priming_shown', {
      'session_id': _sessionId,
      'step': step,
    });
  }

  /// L'utilisateur a accepté l'amorce ; [registered] = device enregistré côté
  /// serveur (donc joignable par une relance J+0/J+1).
  Future<void> trackOnboardingNotifPrimingAccepted({
    required bool registered,
  }) async {
    await _capturePostHog('onboarding_notif_priming_accepted', {
      'session_id': _sessionId,
      'registered': registered,
    });
  }

  /// L'utilisateur a repoussé l'amorce (« Plus tard ») — aucune demande OS
  /// déclenchée, la modale d'activation quotidienne reste disponible.
  Future<void> trackOnboardingNotifPrimingRefused() async {
    await _capturePostHog('onboarding_notif_priming_refused', {
      'session_id': _sessionId,
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Sprint 2 — feature-by-feature events (PR1)
  // ──────────────────────────────────────────────────────────────

  Future<void> trackDigestOpened({
    required String digestDate,
    int? itemsCount,
  }) async {
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'items_count': itemsCount,
    };
    await _logEvent('digest_opened', props);
    await _capturePostHog('digest_opened', props);
  }

  Future<void> trackBonnesNouvellesOpened({DateTime? targetDate}) async {
    final props = {
      'session_id': _sessionId,
      'target_date': targetDate?.toIso8601String(),
    };
    await _logEvent('bonnes_nouvelles_opened', props);
    await _capturePostHog('bonnes_nouvelles_opened', props);
  }

  Future<void> trackDigestItemViewed({
    required String digestDate,
    required String contentId,
    required int position,
  }) async {
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'content_id': contentId,
      'position': position,
    };
    await _logEvent('digest_item_viewed', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Impressions d'article — dénominateur du CTR (Tournée + Essentiel)
  // ──────────────────────────────────────────────────────────────

  /// Clé SharedPreferences de dédup des impressions d'article : une entrée
  /// `'$dayKey|$sectionKey|$contentId'` par carte déjà comptée aujourd'hui,
  /// purgée des jours passés à chaque écriture (même pattern que
  /// [_kSuggestionImpressionsKey]).
  static const _kArticleImpressionsKey = 'article_impressions_v1';

  /// Miroir de `tournee_customized_v1` (cf. `tournee_order_prefs_provider`).
  /// Dupliqué ici plutôt qu'importé : `core/services` ne doit pas dépendre
  /// d'un feature.
  static const _kTourneeCustomizedPrefKey = 'tournee_customized_v1';

  /// Garde-fou mémoire : les clés déjà comptées **dans ce process**, pour ne
  /// pas relire SharedPreferences à chaque re-montage de carte au scroll (une
  /// carte recyclée par le viewport paresseux re-déclenche son tracker).
  final Set<String> _impressedArticleKeys = <String>{};

  /// Dédup persistante scindée par jour, partagée par les impressions d'article
  /// et de suggestion. Range [entry] dans la liste SharedPreferences [prefsKey]
  /// en purgeant les jours passés (on ne garde que les entrées préfixées par
  /// `'$dayKey|'`). Retourne `true` si l'entrée est neuve — l'événement doit
  /// alors partir —, `false` si elle a déjà été comptée aujourd'hui.
  Future<bool> _recordDailyOnce(
    String prefsKey,
    String entry,
    String dayKey,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = (prefs.getStringList(prefsKey) ?? const [])
        .where((e) => e.startsWith('$dayKey|'))
        .toList();
    if (kept.contains(entry)) return false;
    kept.add(entry);
    await prefs.setStringList(prefsKey, kept);
    return true;
  }

  /// Impression d'un article rendu dans la Tournée ou l'Essentiel — le
  /// **dénominateur** du CTR, dont le numérateur reste
  /// `user_content_status.status = 'consumed'` côté backend.
  ///
  /// Dédupliquée **1×/(contentId, sectionKey, jour)** : un article vu trois
  /// fois dans la même section le même jour compte une impression. Le même
  /// article vu dans deux sections différentes en compte deux — c'est voulu,
  /// la position dans une section est justement ce qu'on mesure.
  ///
  /// Backend-only, **pas de miroir PostHog** : le dénominateur doit se joindre
  /// à `user_content_status` × `contents` en Postgres, et le pipeline PostHog
  /// ne couvre qu'une fraction des clics réels (`article_read` ≈ 15 % des
  /// `consumed`). Un miroir donnerait deux chiffres divergents pour la même
  /// métrique.
  ///
  /// `algo_version` est estampillé **côté serveur** (cf.
  /// `routers/analytics.py`) : le client ne connaît pas la configuration de
  /// scoring.
  Future<void> trackArticleImpression({
    required String contentId,
    required String sectionKey,
    required String sectionFamily,
    required String surface,
    required String dayKey,
    required int sectionIndex,
    required int positionInSection,
    required int globalPosition,
    double? scoreTotal,
    double? blockScore,
    String? theme,
    String? sourceId,
    bool isSerene = false,
    bool underfilled = false,
  }) async {
    if (_apiClient == null) return;
    final entry = '$dayKey|$sectionKey|$contentId';
    if (!_impressedArticleKeys.add(entry)) return;

    if (!await _recordDailyOnce(_kArticleImpressionsKey, entry, dayKey)) {
      return; // déjà comptée aujourd'hui (relance)
    }

    await _logEventBuffered('article_impression', {
      'session_id': _sessionId,
      'content_id': contentId,
      'section_key': sectionKey,
      'section_family': sectionFamily,
      'surface': surface,
      'day_key': dayKey,
      'section_index': sectionIndex,
      'position_in_section': positionInSection,
      'global_position': globalPosition,
      'score_total': scoreTotal,
      'block_score': blockScore,
      'theme': theme,
      'source_id': sourceId,
      'is_serene': isSerene,
      'underfilled': underfilled,
    });
  }

  Future<void> trackPerspectiveComparisonOpened({
    required String contentId,
    String? clusterId,
    int sourcesCount = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'cluster_id': clusterId,
      'sources_count': sourcesCount,
    };
    await _logEvent('perspective_comparison_opened', props);
    await _capturePostHog('perspective_comparison_opened', props);
  }

  Future<void> trackPerspectiveArticleViewed({
    required String contentId,
    required String perspectiveArticleId,
    String? clusterId,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'perspective_article_id': perspectiveArticleId,
      'cluster_id': clusterId,
    };
    await _logEvent('perspective_article_viewed', props);
  }

  Future<void> trackPerspectiveComparisonClosed({
    required String contentId,
    String? clusterId,
    int viewedArticles = 0,
    int openedSeconds = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'cluster_id': clusterId,
      'viewed_articles': viewedArticles,
      'opened_seconds': openedSeconds,
    };
    await _logEvent('perspective_comparison_closed', props);
  }

  /// Ouverture de la modale « Donner mon avis » (réglages). Trace serveur
  /// utilisée par la lettre 4 (action give_app_feedback).
  Future<void> trackAppFeedbackOpened() async {
    final props = {'session_id': _sessionId};
    await _logEvent('app_feedback_opened', props);
    await _capturePostHog('app_feedback_opened', props);
  }

  // ─── Invitation « un café en visio » (Epic 13, story 13.3) ───
  // Funnel complet : shown (entrée inline vue) → opened (modale, auto ou tap)
  // → booked / snoozed / already_done. `segment` = classification backend
  // ("active" | "low_active" | "returning").

  /// Nom d'event de sortie du funnel, par action envoyée au backend.
  static const _feedbackInviteExitEvents = {
    'accepted': 'feedback_invite_booked',
    'declined': 'feedback_invite_snoozed',
    'already_done': 'feedback_invite_already_done',
  };

  Future<void> _trackFeedbackInvite(
    String event,
    String? segment, {
    Map<String, dynamic> extra = const {},
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      if (segment != null) 'segment': segment,
      ...extra,
    };
    await _logEvent(event, props);
    await _capturePostHog(event, props);
  }

  /// L'entrée inline est réellement entrée dans le viewport.
  Future<void> trackFeedbackInviteShown({String? segment}) =>
      _trackFeedbackInvite('feedback_invite_shown', segment);

  /// origin: 'auto' (auto-déploiement une fois) | 'tap' (entrée inline).
  Future<void> trackFeedbackInviteOpened({
    String? segment,
    required String origin,
  }) =>
      _trackFeedbackInvite(
        'feedback_invite_opened',
        segment,
        extra: {'origin': origin},
      );

  /// Sortie du funnel. `action` = celle envoyée au backend
  /// ("accepted" | "declined" | "already_done").
  Future<void> trackFeedbackInviteAction(String action, {String? segment}) =>
      _trackFeedbackInvite(
        _feedbackInviteExitEvents[action] ?? 'feedback_invite_$action',
        segment,
      );

  /// origin: 'digest' | 'feed' | 'settings'
  Future<void> trackArticleFeedbackSubmitted({
    required String contentId,
    required String feedbackType,
    required String origin,
    Map<String, dynamic> extra = const {},
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'content_id': contentId,
      'feedback_type': feedbackType,
      'origin': origin,
      ...extra,
    };
    await _logEvent('article_feedback_submitted', props);
    await _capturePostHog('article_feedback_submitted', props);
  }

  /// origin: 'onboarding' | 'custom_topics'
  Future<void> trackSubtopicSuggestionShown({
    required String subtopicSlug,
    required String origin,
  }) async {
    await _logEvent('subtopic_suggestion_shown', {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    });
  }

  Future<void> trackSubtopicAdded({
    required String subtopicSlug,
    required String origin,
  }) async {
    final props = {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    };
    await _logEvent('subtopic_added', props);
    await _capturePostHog('subtopic_added', props);
  }

  Future<void> trackSubtopicRemoved({
    required String subtopicSlug,
    required String origin,
  }) async {
    await _logEvent('subtopic_removed', {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    });
  }

  /// Un ajout de sujet/entité personnalisé a échoué (timeout réseau, 4xx/5xx…).
  /// origin: 'onboarding' | 'custom_topics'. Sert à mesurer la fréquence réelle
  /// des échecs autrefois avalés côté client (bug custom-topics-deferred-save).
  Future<void> trackCustomTopicSaveFailed({
    required String name,
    required String origin,
    String? theme,
    String? error,
  }) async {
    final props = {
      'session_id': _sessionId,
      'name': name,
      'origin': origin,
      'theme': theme,
      'error': error,
    };
    await _logEvent('custom_topic_save_failed', props);
    await _capturePostHog('custom_topic_save_failed', props);
  }

  /// Generic settings/preference toggle. `key` is a stable snake_case identifier
  /// (e.g. 'notifications_daily_digest'), oldValue/newValue are coerced to string
  /// to keep the event payload shape uniform across bool/int/string toggles.
  Future<void> trackPreferenceChanged({
    required String key,
    required Object? oldValue,
    required Object? newValue,
  }) async {
    final props = {
      'session_id': _sessionId,
      'key': key,
      'old_value': oldValue?.toString(),
      'new_value': newValue?.toString(),
    };
    await _logEvent('preference_changed', props);
    await _capturePostHog('preference_changed', props);
  }

  Future<void> trackAddSourceThemeTap(String themeSlug) async {
    await _logEvent('add_source_theme_tap', {'theme_slug': themeSlug});
  }

  Future<void> trackAddSourceExampleTap(String exampleText) async {
    await _logEvent('add_source_example_tap', {'example_text': exampleText});
  }

  Future<void> trackAddSourceGemTap(String sourceId) async {
    await _logEvent('add_source_gem_tap', {'source_id': sourceId});
  }

  Future<void> trackAddSourceContentTypeFilter(String contentType) async {
    await _logEvent('add_source_content_type_filter', {
      'content_type': contentType,
    });
  }

  Future<void> trackAddSourceExpand(String query) async {
    await _logEvent('add_source_expand', {'query': query});
  }

  /// Ajout réussi d'une source depuis le panneau de recherche (catalogue ou
  /// URL custom). Mesure l'effet des affordances « source vérifiée » / preuve
  /// inline en regard de `search_abandoned` (émis au dispose sans ajout).
  /// `sourceId` est vide pour un ajout custom (pas d'entrée catalogue).
  Future<void> trackSourceAdded({
    String? sourceId,
    required String sourceType,
    required bool inCatalog,
    required bool isCurated,
    required String sourceLayer,
  }) async {
    await _logEvent('source_added', {
      'source_id': sourceId ?? '',
      'source_type': sourceType,
      'in_catalog': inCatalog,
      'is_curated': isCurated,
      'source_layer': sourceLayer,
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Story 30.1 — Recherche universelle.
  // Funnel visé : search_opened → search_result_selected (succès) vs
  // search_submitted_empty (impasse) → search_broadened /
  // search_add_source_bridged (rattrapages).
  // ──────────────────────────────────────────────────────────────

  /// [origin] : `header` (loupe du header partagé) ou `filter_bar` (pill de
  /// recherche active). [tab] : `essentiel` ou `flaner`.
  Future<void> trackSearchOpened({
    required String origin,
    required String tab,
  }) async {
    final props = {'origin': origin, 'tab': tab};
    await _logEvent('search_opened', props);
    await _capturePostHog('search_opened', props);
  }

  /// [resultType] : `article` · `source` · `catalog_source` · `topic` ·
  /// `entity` · `theme` · `add_source`. [rank] est l'index du résultat dans sa
  /// section (0-based) — mesure si les bons résultats remontent assez haut.
  Future<void> trackSearchResultSelected({
    required String resultType,
    required int rank,
    required int queryLength,
  }) async {
    final props = {
      'result_type': resultType,
      'rank': rank,
      'query_length': queryLength,
    };
    await _logEvent('search_result_selected', props);
    await _capturePostHog('search_result_selected', props);
  }

  /// Recherche mot-clé n'ayant ramené aucun article — l'impasse qu'on cherche
  /// à faire disparaître. [broadened] indique si la recherche portait déjà sur
  /// toutes les sources (vs les seules sources suivies).
  Future<void> trackSearchSubmittedEmpty({
    required int queryLength,
    required bool broadened,
  }) async {
    final props = {'query_length': queryLength, 'broadened': broadened};
    await _logEvent('search_submitted_empty', props);
    await _capturePostHog('search_submitted_empty', props);
  }

  /// Passage de la recherche au flow d'ajout de source. [bridgeCase] :
  /// `catalog_follow` (ajout en 1 tap depuis le catalogue) ou `smart_search`
  /// (bascule vers `AddSourceScreen` pré-rempli).
  Future<void> trackSearchAddSourceBridged({required String bridgeCase}) async {
    final props = {'case': bridgeCase};
    await _logEvent('search_add_source_bridged', props);
    await _capturePostHog('search_add_source_bridged', props);
  }

  /// Tap sur « élargir à toutes les sources » (`includeUnfollowed`).
  Future<void> trackSearchBroadened({required int resultCount}) async {
    final props = {'result_count': resultCount};
    await _logEvent('search_broadened', props);
    await _capturePostHog('search_broadened', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Story 14.3 — Self-reported "well-informed" score (1-10 NPS).
  // Trois events pour construire le funnel shown → skipped / submitted.
  // ──────────────────────────────────────────────────────────────

  Future<void> trackWellInformedPromptShown({
    String context = 'digest_inline',
  }) async {
    final props = {'session_id': _sessionId, 'context': context};
    await _logEvent('well_informed_prompt_shown', props);
  }

  Future<void> trackWellInformedPromptSkipped({
    String context = 'digest_inline',
  }) async {
    final props = {'session_id': _sessionId, 'context': context};
    await _logEvent('well_informed_prompt_skipped', props);
    await _capturePostHog('well_informed_prompt_skipped', props);
  }

  Future<void> trackWellInformedScoreSubmitted({
    required int score,
    String context = 'digest_inline',
  }) async {
    final props = {
      'session_id': _sessionId,
      'score': score,
      'context': context,
    };
    await _logEvent('well_informed_score_submitted', props);
    await _capturePostHog('well_informed_score_submitted', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Home-screen widget — refonte instrumentation
  // ──────────────────────────────────────────────────────────────

  Future<void> trackWidgetPinNudgeShown() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_nudge_shown', props);
    await _capturePostHog('widget_pin_nudge_shown', props);
  }

  Future<void> trackWidgetPinRequested() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_requested', props);
    await _capturePostHog('widget_pin_requested', props);
  }

  Future<void> trackWidgetPinDismissed() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_dismissed', props);
    await _capturePostHog('widget_pin_dismissed', props);
  }

  Future<void> trackDiscoverDisableStepShown() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_step_shown', props);
    await _capturePostHog('discover_disable_step_shown', props);
  }

  Future<void> trackDiscoverDisableConfirmed() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_confirmed', props);
    await _capturePostHog('discover_disable_confirmed', props);
  }

  Future<void> trackDiscoverDisableSkipped() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_skipped', props);
    await _capturePostHog('discover_disable_skipped', props);
  }

  Future<void> trackGeolocPromptShown({required int displayCount}) async {
    final props = {
      'session_id': _sessionId,
      'display_count': displayCount,
    };
    await _logEvent('geoloc_prompt_shown', props);
    await _capturePostHog('geoloc_prompt_shown', props);
  }

  Future<void> trackGeolocPromptActivated({required bool granted}) async {
    final props = {
      'session_id': _sessionId,
      'granted': granted,
    };
    await _logEvent('geoloc_prompt_activated', props);
    await _capturePostHog('geoloc_prompt_activated', props);
  }

  Future<void> trackGeolocPromptDismissed() async {
    final props = {'session_id': _sessionId};
    await _logEvent('geoloc_prompt_dismissed', props);
    await _capturePostHog('geoloc_prompt_dismissed', props);
  }

  /// target: 'digest' | 'article' | 'feed'.
  /// Fired whenever a `io.supabase.facteur://` widget URI lands in the app.
  Future<void> trackWidgetAppOpened({
    required String target,
    String? articleId,
    int? position,
    String? topicId,
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'target': target,
      'article_id': articleId,
      'position': position,
      'topic_id': topicId,
    };
    await _logEvent('widget_app_opened', props);
    await _capturePostHog('widget_app_opened', props);
  }

  /// Fired when the widget URI specifically asked for an article reader,
  /// to power the widget→reader CTR funnel without mixing with `digest`/`feed`
  /// taps.
  Future<void> trackWidgetArticleOpened({
    required String articleId,
    int? position,
    String? topicId,
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'article_id': articleId,
      'position': position,
      'topic_id': topicId,
    };
    await _logEvent('widget_article_opened', props);
    await _capturePostHog('widget_article_opened', props);
  }

  /// Fired once per Flux view session, on app foreground, after reading the
  /// max scroll position the native RemoteViewsFactory persisted to
  /// SharedPreferences. [maxPosition] is 0-indexed; [scrollPct] is computed
  /// against [totalCount].
  Future<void> trackWidgetFluxScrollSession({
    required int maxPosition,
    required int totalCount,
    DateTime? at,
  }) async {
    final scrollPct =
        totalCount > 0 ? ((maxPosition + 1) / totalCount).clamp(0.0, 1.0) : 0.0;
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'max_position': maxPosition,
      'total_count': totalCount,
      'scroll_pct': scrollPct,
      'at_iso': at?.toUtc().toIso8601String(),
    };
    await _logEvent('widget_flux_scroll', props);
    await _capturePostHog('widget_flux_scroll', props);
  }

  // ── Notifications activation events (brief §7) ──────────────────────

  Future<void> trackModalNotifShown({
    required ActivationTrigger trigger,
  }) async {
    final props = <String, dynamic>{'trigger': trigger.name};
    await _logEvent('modal_notif_shown', props);
    await _capturePostHog('modal_notif_shown', props);
  }

  Future<void> trackModalNotifTimeChanged({
    required NotifTimeSlot timeSlot,
  }) async {
    final props = <String, dynamic>{'time': timeSlot.wire};
    await _logEvent('modal_notif_time_changed', props);
    await _capturePostHog('modal_notif_time_changed', props);
  }

  Future<void> trackModalNotifConfirmed({
    required NotifPreset preset,
    required NotifTimeSlot timeSlot,
    required bool osPermissionGranted,
  }) async {
    final props = <String, dynamic>{
      'preset': preset.wire,
      'time': timeSlot.wire,
      'os_permission_granted': osPermissionGranted,
    };
    await _logEvent('modal_notif_confirmed', props);
    await _capturePostHog('modal_notif_confirmed', props);
  }

  Future<void> trackModalNotifDismissed() async {
    await _logEvent('modal_notif_dismissed', {});
    await _capturePostHog('modal_notif_dismissed', {});
  }

  // ── iOS "Add to Home Screen" PWA modal (Story web.1) ────────────────

  Future<void> trackIosAddToHomeShown() async {
    await _logEvent('ios_add_to_home_shown', {});
    await _capturePostHog('ios_add_to_home_shown', {});
  }

  Future<void> trackIosAddToHomeConfirmed() async {
    await _logEvent('ios_add_to_home_confirmed', {});
    await _capturePostHog('ios_add_to_home_confirmed', {});
  }

  Future<void> trackIosAddToHomeDismissed() async {
    await _logEvent('ios_add_to_home_dismissed', {});
    await _capturePostHog('ios_add_to_home_dismissed', {});
  }

  Future<void> trackRenudgeShown({required int displayCount}) async {
    final props = <String, dynamic>{'display_count': displayCount};
    await _logEvent('renudge_shown', props);
    await _capturePostHog('renudge_shown', props);
  }

  Future<void> trackRenudgeConfirmed() async {
    await _logEvent('renudge_confirmed', {});
    await _capturePostHog('renudge_confirmed', {});
  }

  Future<void> trackRenudgeDismissed() async {
    await _logEvent('renudge_dismissed', {});
    await _capturePostHog('renudge_dismissed', {});
  }

  Future<void> trackNotifScheduled({
    required String type, // daily_a / daily_b / daily_empty / community
    required String time,
  }) async {
    final props = <String, dynamic>{'type': type, 'time': time};
    await _logEvent('notif_scheduled', props);
    await _capturePostHog('notif_scheduled', props);
  }

  Future<void> trackNotifOpened({
    required String type,
    int? timeToOpenSeconds,
  }) async {
    final props = <String, dynamic>{
      'type': type,
      'time_to_open': timeToOpenSeconds,
    };
    await _logEvent('notif_opened', props);
    await _capturePostHog('notif_opened', props);
  }

  Future<void> trackNotifDisabled({required String source}) async {
    // source: 'in_app' or 'os_settings'
    final props = <String, dynamic>{'source': source};
    await _logEvent('notif_disabled', props);
    await _capturePostHog('notif_disabled', props);
  }

  Future<void> trackAppFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('has_launched_before') == true) return;

    await _logEvent('app_first_launch', {});
    await prefs.setBool('has_launched_before', true);
  }

  // ──────────────────────────────────────────────────────────────
  // Tournée — suggestions « Choisie pour vous » (Story 22.6)
  // ──────────────────────────────────────────────────────────────

  /// Clé SharedPreferences de dédup des impressions de suggestions. Une entrée
  /// `'$dayKey|$sectionKey'` par section suggérée déjà comptée aujourd'hui ;
  /// purgée des jours passés à chaque émission (1 impression/section/jour).
  static const _kSuggestionImpressionsKey = 'suggestion_impressions_v1';

  /// Impression d'une section suggérée, **dédupliquée 1×/section/jour** et
  /// persistée (survit aux rebuilds et relances). Émise au premier build de la
  /// section ; les appels suivants du même jour sont des no-op silencieux.
  Future<void> trackSuggestionImpression({
    required String sectionKey,
    required String kind,
    required String dayKey,
  }) async {
    final entry = '$dayKey|$sectionKey';
    if (!await _recordDailyOnce(_kSuggestionImpressionsKey, entry, dayKey)) {
      return; // déjà comptée aujourd'hui
    }
    final props = {
      'session_id': _sessionId,
      'section_key': sectionKey,
      'kind': kind,
      'day_key': dayKey,
    };
    await _logEvent('suggestion_impression', props);
    await _capturePostHog('suggestion_impression', props);
  }

  /// Promotion d'une suggestion en favori. [origin] = `card` (CTA de la carte)
  /// ou `sheet` (« Garder dans mes favoris »).
  Future<void> trackSuggestionPromoted({
    required String sectionKey,
    required String kind,
    required String origin,
  }) async {
    final props = {
      'session_id': _sessionId,
      'section_key': sectionKey,
      'kind': kind,
      'origin': origin,
    };
    await _logEvent('suggestion_promoted', props);
    await _capturePostHog('suggestion_promoted', props);
  }

  /// Dismiss d'une suggestion (retrait local réversible).
  Future<void> trackSuggestionDismissed({
    required String sectionKey,
    required String kind,
  }) async {
    final props = {
      'session_id': _sessionId,
      'section_key': sectionKey,
      'kind': kind,
    };
    await _logEvent('suggestion_dismissed', props);
    await _capturePostHog('suggestion_dismissed', props);
  }

  // ──────────────────────────────────────────────────────────────
  // La Grille du jour (Story 24.2)
  // ──────────────────────────────────────────────────────────────

  Future<void> trackGrilleOpened({String? numero, required String statut}) async {
    final props = {
      'session_id': _sessionId,
      'numero': numero,
      'statut': statut,
    };
    await _logEvent('grille_opened', props);
    await _capturePostHog('grille_opened', props);
  }

  Future<void> trackGrilleGuessSubmitted({
    String? numero,
    required int essai,
    required bool valide,
    String? raison,
  }) async {
    await _logEvent('grille_guess_submitted', {
      'session_id': _sessionId,
      'numero': numero,
      'essai': essai,
      'valide': valide,
      'raison': raison,
    });
  }

  Future<void> trackGrilleCompleted({
    String? numero,
    required String statut,
    required int nbEssais,
  }) async {
    final props = {
      'session_id': _sessionId,
      'numero': numero,
      'statut': statut,
      'nb_essais': nbEssais,
    };
    await _logEvent('grille_completed', props);
    await _capturePostHog('grille_completed', props);
  }

  /// `medium` ∈ `texte | lien`.
  Future<void> trackGrilleShared({String? numero, required String medium}) async {
    final props = {
      'session_id': _sessionId,
      'numero': numero,
      'medium': medium,
    };
    await _logEvent('grille_shared', props);
    await _capturePostHog('grille_shared', props);
  }

  Future<void> trackGrilleLeaderboardOpened({String? numero}) async {
    await _logEvent('grille_leaderboard_opened', {
      'session_id': _sessionId,
      'numero': numero,
    });
  }

  Future<void> trackGrilleCtaShown({required String state}) async {
    await _logEvent('grille_cta_shown', {
      'session_id': _sessionId,
      'state': state,
    });
  }

  Future<void> trackGrilleCtaTapped({required String state}) async {
    final props = {'session_id': _sessionId, 'state': state};
    await _logEvent('grille_cta_tapped', props);
    await _capturePostHog('grille_cta_tapped', props);
  }

  /// Tap sur un lien « lire les actus du jour » depuis La Grille (résultat ou
  /// mini-CTA en cours de jeu).
  Future<void> trackGrilleActusTapped({String? numero}) async {
    final props = {'session_id': _sessionId, 'numero': numero};
    await _logEvent('grille_actus_tapped', props);
    await _capturePostHog('grille_actus_tapped', props);
  }

  /// Le joueur a ouvert le vrai article accroché au mot du jour (reveal).
  Future<void> trackGrilleArticleTapped({String? numero}) async {
    final props = {'session_id': _sessionId, 'numero': numero};
    await _logEvent('grille_article_tapped', props);
    await _capturePostHog('grille_article_tapped', props);
  }

  /// Le joueur a « donné sa langue au chat » (mot révélé, exclu du classement).
  Future<void> trackGrilleRevealed({String? numero}) async {
    final props = {'session_id': _sessionId, 'numero': numero};
    await _logEvent('grille_revealed', props);
    await _capturePostHog('grille_revealed', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Buffer d'events — POST groupé
  // ──────────────────────────────────────────────────────────────

  /// Taille de lot déclenchant un flush immédiat. Aligné sur le plafond serveur
  /// (`MAX_BATCH_EVENTS = 100`) avec une marge large : un flush ne doit jamais
  /// se faire refuser pour cause de lot trop grand.
  static const int _kBatchFlushSize = 25;

  /// Inactivité au bout de laquelle un lot partiel part quand même — sinon les
  /// impressions d'une session courte n'arrivent qu'à la mise en arrière-plan.
  static const Duration _kBatchIdleFlush = Duration(seconds: 10);

  final List<Map<String, dynamic>> _pendingEvents = [];
  Timer? _flushTimer;

  /// Empile un event pour envoi **groupé**. Réservé à la télémétrie à haut
  /// volume (impressions) : `_logEvent` reste le chemin unitaire de tout event
  /// porteur d'un effet de bord serveur (`session_start` → streak, version).
  ///
  /// Motif : `_logEvent` fait un POST HTTP par event. ~30 impressions par
  /// session, c'est 30 POST fire-and-forget sur réseau mobile.
  Future<void> _logEventBuffered(
    String eventType,
    Map<String, dynamic> eventData,
  ) async {
    if (_apiClient == null) return;
    if (_deviceId == null) await init();
    _pendingEvents.add({
      'event_type': eventType,
      'event_data': eventData,
      'device_id': _deviceId,
    });
    if (_pendingEvents.length >= _kBatchFlushSize) {
      await flushPendingEvents();
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(_kBatchIdleFlush, () => unawaited(flushPendingEvents()));
  }

  /// Pousse le buffer vers `POST /analytics/events/batch`. Appelée sur seuil,
  /// sur inactivité et par [endSession] (donc sur `AppLifecycleState.paused`).
  ///
  /// Un lot qui échoue est **abandonné**, jamais ré-empilé : de l'analytics
  /// best-effort qui se remettrait en file grossirait sans borne hors ligne, et
  /// finirait par rejouer un lot au-delà du plafond serveur.
  Future<void> flushPendingEvents() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final client = _apiClient;
    if (client == null || _pendingEvents.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_pendingEvents);
    _pendingEvents.clear();
    try {
      await client.dio.post<dynamic>('analytics/events/batch', data: batch);
    } catch (e) {
      debugPrint('Analytics batch error (${batch.length} events): $e');
    }
  }

  /// Nombre d'events en attente de flush — sonde de test.
  @visibleForTesting
  int get pendingEventCount => _pendingEvents.length;

  Future<void> _logEvent(
    String eventType,
    Map<String, dynamic> eventData,
  ) async {
    final client = _apiClient;
    if (client == null) return;
    try {
      if (_deviceId == null) await init();

      await client.dio.post<dynamic>(
        'analytics/events',
        data: {
          'event_type': eventType,
          'event_data': eventData,
          'device_id': _deviceId,
        },
      );
    } catch (e) {
      // Fail silently for analytics but log to console
      debugPrint('Analytics Error ($eventType): $e');
    }
  }

  /// Push un event vers PostHog — fire-and-forget, silencieux si désactivé.
  /// PostHog requiert des propriétés `Object` (pas nullable) donc on filtre.
  Future<void> _capturePostHog(
    String event,
    Map<String, dynamic> rawProps,
  ) async {
    final ph = _posthog;
    if (ph == null || !ph.isEnabled) return;
    final cleanProps = <String, Object>{};
    rawProps.forEach((key, value) {
      if (value != null) cleanProps[key] = value as Object;
    });
    await ph.capture(event: event, properties: cleanProps);
  }
}
