import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../widgets/design/facteur_button.dart';
import '../../feed/models/content_model.dart';
import '../../flux_continu/utils/theme_color_mapping.dart';
import '../../flux_continu/widgets/flux_continu_article_card.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../my_interests/widgets/interest_state_pill.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../utils/publication_frequency.dart';
import 'premium_source_connection.dart';
import 'source_logo_avatar.dart';

/// Espace fine insécable (U+202F) — avant `? ! : ;`, milliers, unités.
const String _nnbsp = ' ';

/// Fiche source v2 — présentation du média d'abord, évaluation repliée.
///
/// Ordre des sections (haut → bas) :
/// 1. `_FsHeader` (logo/nom/domaine/signaux/description)
/// 2. `_FsEval` (repliée par défaut, discrète) + `_FsRecoPerso`
/// 3. `_FsCoverage` (couverture par thèmes, data-dépendante → skeleton)
/// 4. `_FsArticles` (derniers articles, data-dépendante → skeleton)
/// 5. `_FsSettings` (priorité, ssi suivie)
/// 6. `_FsManage` (premium si proposé + masquer)
/// 7. Actions (Suivre + favori) en fin de scroll.
class SourceDetailModal extends ConsumerWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final VoidCallback? onToggleMute;
  final VoidCallback? onCopyFeedUrl;

  /// Articles récents pré-chargés (ex. smart-search). Quand `null`, la fiche
  /// se charge elle-même via [sourceProfileProvider] (mode normal).
  final List<SmartSearchRecentItem>? recentItems;

  /// Contexte onboarding : quand non-null, le bouton principal reflète l'état
  /// de sélection du questionnaire (et non l'état « confiance » global).
  final bool? isSelectedOverride;

  /// Libellé du bouton principal quand la source n'est pas sélectionnée
  /// (contexte onboarding). Défaut : « Sélectionner cette source ».
  final String? selectLabel;

  const SourceDetailModal({
    super.key,
    required this.source,
    required this.onToggleTrust,
    this.onToggleMute,
    this.onCopyFeedUrl,
    this.recentItems,
    this.isSelectedOverride,
    this.selectLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    // Source live depuis le provider : trust/mute/abo restent synchro quand on
    // les bascule depuis la fiche elle-même.
    final liveSource = ref
            .watch(userSourcesProvider)
            .valueOrNull
            ?.where((s) => s.id == source.id)
            .firstOrNull ??
        source;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 28),
                child: _FsBody(
                  source: liveSource,
                  recentItems: recentItems,
                ),
              ),
            ),
            _FsActionBar(
              source: liveSource,
              onToggleTrust: onToggleTrust,
              isSelectedOverride: isSelectedOverride,
              selectLabel: selectLabel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenu défilant : header → éval → couverture → articles → réglages → gestion.
///
/// Deux modes :
/// - **normal** (`recentItems == null`) : un seul [sourceProfileProvider]
///   alimente couverture, articles (cartes cliquables) et chip fréquence. En
///   erreur réseau, la fiche tombe sur un **fallback statique** (header + éval
///   + réglages + gestion) sans jamais bloquer.
/// - **smart-search** (`recentItems != null`, depuis `source_add_panel`) :
///   inchangé — couverture via [sourceCoverageProvider], articles préchargés
///   en carte minimale (la source n'est pas forcément en base).
class _FsBody extends ConsumerWidget {
  final Source source;
  final List<SmartSearchRecentItem>? recentItems;

  const _FsBody({required this.source, this.recentItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preloaded = recentItems;
    if (preloaded != null) {
      return _assemble(
        frequencyLabel: null,
        middle: [
          _FsCoverageFromProvider(source: source),
          _FsSection(
            title: 'Derniers articles',
            child: _ArticlesContent(items: preloaded),
          ),
        ],
      );
    }

    final profileAsync = ref.watch(sourceProfileProvider(source.id));
    final (String? frequencyLabel, List<Widget> middle) = profileAsync.when(
      loading: () => (
        null,
        const [
          _FsSection(title: 'Couverture par thèmes', child: _CoverageSkeleton()),
          _FsSection(title: 'Derniers articles', child: _ArticlesSkeleton()),
        ],
      ),
      // Fallback statique : couverture / articles / fréquence masqués, le reste
      // reste exploitable depuis l'objet Source déjà en main.
      error: (_, __) => (null, const <Widget>[]),
      data: (profile) => (
        humanizeFrequency(profile.articles30d, profile.oldestContentAt),
        [
          if (profile.hasCoverage)
            _FsSection(
              title: 'Couverture par thèmes',
              action: '30 derniers jours',
              child: _CoverageBars(
                rows: [
                  for (final t in profile.themeDistribution)
                    (theme: t.theme, pct: (t.share * 100).round()),
                ],
                caption: _coverageCaption(profile.articles30d),
              ),
            ),
          _FsArticlesSection(articles: profile.recentArticles),
        ],
      ),
    );
    return _assemble(frequencyLabel: frequencyLabel, middle: middle);
  }

  /// Assemble la fiche autour d'une zone centrale variable. Header, éval,
  /// réglages et gestion sont communs aux trois états (data/loading/error).
  Widget _assemble({
    required String? frequencyLabel,
    required List<Widget> middle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FsHeader(source: source, frequencyLabel: frequencyLabel),
        _FsEval(source: source),
        ...middle,
        if (source.isTrusted) _FsSettings(source: source),
        _FsManage(source: source),
      ],
    );
  }
}

// ============================================================
// 1. Header identité
// ============================================================
class _FsHeader extends StatelessWidget {
  final Source source;

  /// Fréquence de publication humanisée (« ~100/jour »…). `null` hors mode
  /// normal data (smart-search, loading, fallback erreur).
  final String? frequencyLabel;

  const _FsHeader({required this.source, this.frequencyLabel});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final domain = _domainOf(source.url);
    final followerCount = source.followerCount;

    final signals = <Widget>[];
    if (followerCount > 0) {
      signals.add(_signal(
        context,
        PhosphorIcons.users(PhosphorIconsStyle.regular),
        'Suivi par ${_formatThousands(followerCount)} '
        '${followerCount > 1 ? 'lecteurs' : 'lecteur'}',
      ));
    }
    if (frequencyLabel != null && frequencyLabel!.isNotEmpty) {
      signals.add(_signal(
        context,
        PhosphorIcons.clock(PhosphorIconsStyle.regular),
        frequencyLabel!,
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SourceLogoAvatar(source: source, size: 64, radius: 16),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: FacteurTypography.serifTitle(colors.textPrimary)
                          .copyWith(fontSize: 22, letterSpacing: -0.4),
                    ),
                    if (domain != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        domain,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                    if (signals.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: signals,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (source.description != null &&
              source.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              source.description!.trim(),
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                height: 1.55,
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _signal(BuildContext context, IconData icon, String label) {
    final colors = context.facteurColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: colors.textTertiary),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
        ),
      ],
    );
  }
}

// ============================================================
// 2. Évaluation — repliée, discrète
// ============================================================
class _FsEval extends StatefulWidget {
  final Source source;
  const _FsEval({required this.source});

  @override
  State<_FsEval> createState() => _FsEvalState();
}

class _FsEvalState extends State<_FsEval> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final reliabilityLabel = _reliabilityLabel(widget.source.reliabilityScore);
    final reliabilityColor = _reliabilityColor(
      widget.source.reliabilityScore,
      colors,
    );
    final hasEval = widget.source.reliabilityScore != 'unknown' ||
        widget.source.scoreIndependence != null ||
        widget.source.scoreRigor != null ||
        widget.source.scoreUx != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête repliable
          InkWell(
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Évaluation Facteur',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '· à titre indicatif',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (hasEval)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: reliabilityColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          reliabilityLabel,
                          style: textTheme.labelMedium?.copyWith(
                            color: reliabilityColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Pas encore évaluée',
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : FacteurDurations.fast,
                    child: Icon(
                      PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                      size: 14,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              child: hasEval
                  ? _buildEvalBody(context, colors, textTheme, reliabilityLabel,
                      reliabilityColor)
                  : _buildNotEvaluated(context, colors, textTheme),
            ),
        ],
      ),
    );
  }

  Widget _buildEvalBody(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
    String reliabilityLabel,
    Color reliabilityColor,
  ) {
    final source = widget.source;
    final gauges = <Widget>[];
    void addGauge(String name, double? value) {
      if (value == null) return; // masquer si null
      gauges.add(_FsGauge(name: name, value: value));
    }

    addGauge('Indépendance', source.scoreIndependence);
    addGauge('Rigueur', source.scoreRigor);
    addGauge('Accessibilité', source.scoreUx);

    final reason = source.recommendationReason?.trim();
    final recoBy = source.recommendedBy?.trim();
    final hasRecoPerso = recoBy != null &&
        recoBy.isNotEmpty &&
        reason != null &&
        reason.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _evalRow(
          context,
          'Fiabilité',
          Text(
            reliabilityLabel,
            style: textTheme.labelMedium?.copyWith(
              color: reliabilityColor,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0,
            ),
          ),
        ),
        if (gauges.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < gauges.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: gauges[i]),
              ],
            ],
          ),
        ],
        const SizedBox(height: 12),
        _evalRow(
          context,
          'Bord politique',
          _BiasPill(source: source),
        ),
        // Ligne communauté : conditionnelle, masquée par défaut (pas de
        // métrique dédiée pour l'instant — cf. story 7.8 hors périmètre).
        if (hasRecoPerso) ...[
          const SizedBox(height: 12),
          _FsRecoPerso(name: recoBy, comment: reason),
        ],
        const SizedBox(height: 12),
        _buildFooter(context, colors, textTheme),
      ],
    );
  }

  Widget _buildNotEvaluated(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cette source ne publie pas encore assez pour que notre évaluation '
          'soit fiable. Nous préférons ne rien afficher plutôt qu’un '
          'chiffre fragile.',
          style: textTheme.labelMedium?.copyWith(
            color: colors.textSecondary,
            height: 1.55,
            fontSize: 12.5,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        _buildFooter(context, colors, textTheme),
      ],
    );
  }

  Widget _buildFooter(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Évaluation fournie au mieux de nos connaissances. Elle évolue '
            'avec notre méthodologie.',
            style: textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Voir la méthodologie',
            style: textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evalRow(BuildContext context, String label, Widget value) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 12.5,
                letterSpacing: 0,
              ),
        ),
        value,
      ],
    );
  }
}

/// Jauge fine pour un pilier d'évaluation (barre + mot dérivé par seuils).
class _FsGauge extends StatelessWidget {
  final String name;
  final double value;
  const _FsGauge({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: colors.textPrimary.withValues(alpha: 0.09),
            valueColor: AlwaysStoppedAnimation<Color>(colors.secondary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _gaugeWord(value),
          style: textTheme.labelSmall?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// Pilule « Bord politique ».
class _BiasPill extends StatelessWidget {
  final Source source;
  const _BiasPill({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = source.getBiasColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Text(
        source.getBiasLabel(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

/// Reco perso repliable : « Recommandé par {prénom} » + citation.
class _FsRecoPerso extends StatefulWidget {
  final String name;
  final String comment;
  const _FsRecoPerso({required this.name, required this.comment});

  @override
  State<_FsRecoPerso> createState() => _FsRecoPersoState();
}

class _FsRecoPersoState extends State<_FsRecoPerso> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final initial = widget.name.trim().isEmpty
        ? '?'
        : widget.name.trim()[0].toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recommandé par ${widget.name}',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration:
                      reduceMotion ? Duration.zero : FacteurDurations.fast,
                  child: Icon(
                    PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                    size: 14,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(FacteurRadius.medium),
                bottomRight: Radius.circular(FacteurRadius.medium),
              ),
              border: Border(
                left: BorderSide(color: colors.primary, width: 3),
              ),
            ),
            child: Text(
              widget.comment,
              style: textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
                height: 1.55,
                fontSize: 12.5,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// 3. Couverture par thèmes
// ============================================================

/// Couverture par thèmes alimentée par [sourceCoverageProvider] (mode
/// smart-search : la source n'est pas forcément dans le profil unifié).
class _FsCoverageFromProvider extends ConsumerWidget {
  final Source source;
  const _FsCoverageFromProvider({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverageAsync = ref.watch(sourceCoverageProvider(source.id));

    return coverageAsync.when(
      loading: () => const _FsSection(
        title: 'Couverture par thèmes',
        child: _CoverageSkeleton(),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (coverage) {
        if (coverage.isEmpty) return const SizedBox.shrink();
        return _FsSection(
          title: 'Couverture par thèmes',
          action: coverage.periodLabel.isNotEmpty ? coverage.periodLabel : null,
          child: _CoverageBars(
            rows: [
              for (final r in coverage.rows) (theme: r.theme, pct: r.pct),
            ],
            caption: coverage.caption,
          ),
        );
      },
    );
  }
}

/// Barres de couverture par thème : un rang = `(theme brut, pct 0..100)`.
/// Partagé par les deux sources de données (profil unifié & coverage legacy).
class _CoverageBars extends StatelessWidget {
  final List<({String theme, int pct})> rows;
  final String? caption;
  const _CoverageBars({required this.rows, this.caption});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    _coverageLabel(row.theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(
                          height: 12,
                          color: colors.textPrimary.withValues(alpha: 0.06),
                        ),
                        FractionallySizedBox(
                          widthFactor: (row.pct / 100).clamp(0.0, 1.0),
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              color: _coverageColor(row.theme, colors),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${row.pct}$_nnbsp%',
                    textAlign: TextAlign.right,
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (caption != null) ...[
          const SizedBox(height: 1),
          Text(
            caption!,
            style: textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              fontSize: 11.5,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _CoverageSkeleton extends StatelessWidget {
  const _CoverageSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final widths = [0.72, 0.48, 0.30, 0.20];
    return Column(
      children: [
        for (final w in widths)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                _Skel(width: 70, height: 11, colors: colors),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: w,
                      child: _Skel(height: 12, colors: colors),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================
// 4. Derniers articles
// ============================================================

/// Mode normal : articles récents en carte standard [FluxContinuArticleCard]
/// (tap → reader, read-sync, preview en appui long — gérés par la carte). Les
/// `Content` viennent complets du profil unifié.
class _FsArticlesSection extends StatelessWidget {
  final List<Content> articles;
  const _FsArticlesSection({required this.articles});

  @override
  Widget build(BuildContext context) {
    final visible = articles.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 26, 16, 14),
          child: _FsSectionHeader(title: 'Derniers articles'),
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _ArticlesEmptyCard(message: 'Aucun article récent.'),
          )
        else
          // FluxContinuArticleCard porte 12px de padding horizontal interne ;
          // +4px ici aligne les cartes sur les 16px du reste de la fiche.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                for (final article in visible)
                  FluxContinuArticleCard(
                    article: article,
                    onTap: () => _openArticle(context, article),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _openArticle(BuildContext context, Content article) {
    // Reader unique (root navigator) : la sheet reste vivante dessous.
    context.pushNamed(
      RouteNames.contentDetail,
      pathParameters: {'id': article.id},
      extra: article,
    );
  }
}

/// Carte vide partagée (mode smart-search & mode normal sans article).
class _ArticlesEmptyCard extends StatelessWidget {
  final String message;
  const _ArticlesEmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(
          color: colors.textTertiary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.moonStars(PhosphorIconsStyle.regular),
            size: 22,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticlesContent extends StatelessWidget {
  final List<SmartSearchRecentItem> items;
  const _ArticlesContent({required this.items});

  @override
  Widget build(BuildContext context) {
    final visible = items.take(3).toList();

    if (visible.isEmpty) {
      return const _ArticlesEmptyCard(
        message: 'Rien publié ces 7 derniers jours.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _ArticleCard(item: visible[i]),
        ],
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final SmartSearchRecentItem item;
  const _ArticleCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final ago = _relativeTime(item.publishedAt);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _fsCardDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.3,
              letterSpacing: -0.15,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (item.theme != null) ...[
                _ThemeTag(theme: item.theme!),
                Text(
                  '  ·  ',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ],
              if (ago != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.clock(PhosphorIconsStyle.regular),
                      size: 13,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ago,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeTag extends StatelessWidget {
  final String theme;
  const _ThemeTag({required this.theme});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FacteurRadius.full),
      ),
      child: Text(
        _coverageLabel(theme),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

class _ArticlesSkeleton extends StatelessWidget {
  const _ArticlesSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _fsCardDecoration(colors),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Skel(height: 13, colors: colors),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.7,
                    child: _Skel(height: 13, colors: colors),
                  ),
                ),
                const SizedBox(height: 12),
                _Skel(width: 110, height: 10, colors: colors),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================
// 5. Réglages de suivi (ssi suivie)
// ============================================================
class _FsSettings extends StatelessWidget {
  final Source source;
  const _FsSettings({required this.source});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return _FsSection(
      title: 'Réglages de suivi',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _fsCardDecoration(colors),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Priorité dans ton flux',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Choisis la place de cette source dans ton flux.',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SourceStatePill(sourceId: source.id, title: source.name),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 6. Gestion de la source : premium (si proposé) + masquer
// ============================================================
class _FsManage extends ConsumerStatefulWidget {
  final Source source;
  const _FsManage({required this.source});

  @override
  ConsumerState<_FsManage> createState() => _FsManageState();
}

class _FsManageState extends ConsumerState<_FsManage> {
  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final hasPremium = source.premiumConnection != null;

    return _FsSection(
      title: 'Gestion de la source',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPremium) ...[
            _FsPremium(source: source),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: _ManageButton(
              isOn: source.isMuted,
              labelOn: 'Source masquée',
              labelOff: 'Masquer cette source',
              onTap: () => _toggleMute(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMute(BuildContext context) async {
    final source = widget.source;
    try {
      await ref
          .read(userSourcesProvider.notifier)
          .toggleMute(source.id, source.isMuted);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de masquer cette source.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

/// Bouton premium (associer l'abonnement). Visible dès que la source en
/// propose un, indépendamment du suivi.
class _FsPremium extends ConsumerWidget {
  final Source source;
  const _FsPremium({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final linked = source.hasSubscription;

    final title = linked
        ? 'Abonnement associé'
        : (source.premiumConnection!.isGeneric
            ? 'Associer mon abonnement'
            : 'Connecter mon abonnement');

    return InkWell(
      borderRadius: BorderRadius.circular(FacteurRadius.large),
      onTap: () => _openPremiumFlow(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _fsCardDecoration(colors),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.crown(PhosphorIconsStyle.fill),
                size: 17,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.labelMedium?.copyWith(
                      color: linked ? colors.success : colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Lis les articles réservés aux abonnés directement dans '
                    'Facteur.',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      height: 1.4,
                      fontSize: 11.5,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              linked
                  ? PhosphorIcons.check(PhosphorIconsStyle.regular)
                  : PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              size: linked ? 16 : 13,
              color: linked ? colors.success : colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPremiumFlow(BuildContext context, WidgetRef ref) async {
    if (source.hasSubscription) {
      // Déjà associé : permet de dissocier.
      try {
        await ref
            .read(userSourcesProvider.notifier)
            .disconnectSubscription(source.id);
        await ref.read(premiumSessionStoreProvider).clearForSource(source);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de dissocier cet abonnement.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          onConnected: () => ref
              .read(userSourcesProvider.notifier)
              .connectSubscription(source.id),
        ),
      ),
    );
  }
}

/// Bouton tertiaire de gestion (toggle local, ex. masquer).
class _ManageButton extends StatelessWidget {
  final bool isOn;
  final String labelOn;
  final String labelOff;
  final VoidCallback onTap;

  const _ManageButton({
    required this.isOn,
    required this.labelOn,
    required this.labelOff,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOn
              ? colors.textPrimary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color: isOn ? Colors.transparent : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOn
                  ? PhosphorIcons.eye(PhosphorIconsStyle.regular)
                  : PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              size: 16,
              color: isOn ? colors.textSecondary : colors.textTertiary,
            ),
            const SizedBox(width: 7),
            Text(
              isOn ? labelOn : labelOff,
              style: textTheme.labelMedium?.copyWith(
                color: isOn ? colors.textPrimary : colors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 7. Barre d'actions (Suivre + favori) — fin de scroll / sticky bas
// ============================================================
class _FsActionBar extends ConsumerWidget {
  final Source source;
  final VoidCallback onToggleTrust;
  final bool? isSelectedOverride;
  final String? selectLabel;

  const _FsActionBar({
    required this.source,
    required this.onToggleTrust,
    this.isSelectedOverride,
    this.selectLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final inOnboarding = isSelectedOverride != null;
    final isSelected = isSelectedOverride ?? source.isTrusted;

    final followLabel = inOnboarding
        ? (isSelected
            ? 'Retirer de ma sélection'
            : (selectLabel ?? 'Sélectionner cette source'))
        : (isSelected ? 'Suivie' : 'Suivre ${source.name}');

    final isFavorite = ref
            .watch(userSourcesStateProvider)
            .valueOrNull
            ?.favorites
            .any((f) => f.sourceId == source.id) ??
        false;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FacteurButton(
              onPressed: () {
                onToggleTrust();
                Navigator.pop(context);
              },
              label: followLabel,
              type: isSelected
                  ? FacteurButtonType.secondary
                  : FacteurButtonType.primary,
              icon: isSelected
                  ? PhosphorIcons.check(PhosphorIconsStyle.regular)
                  : PhosphorIcons.plus(PhosphorIconsStyle.regular),
            ),
          ),
          // Favori : disponible une fois la source suivie (pas en onboarding).
          if (!inOnboarding && source.isTrusted) ...[
            const SizedBox(width: 10),
            _StarButton(
              isFavorite: isFavorite,
              onTap: () => _toggleFavorite(context, ref, isFavorite),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    bool isFavorite,
  ) async {
    final next =
        isFavorite ? InterestState.followed : InterestState.favorite;
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(source.id, next);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de mettre à jour cette source.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class _StarButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  const _StarButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: colors.border),
        ),
        child: Icon(
          isFavorite
              ? PhosphorIcons.star(PhosphorIconsStyle.fill)
              : PhosphorIcons.star(PhosphorIconsStyle.regular),
          size: 19,
          color: isFavorite ? colors.primary : colors.textSecondary,
          semanticLabel:
              isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
        ),
      ),
    );
  }
}

// ============================================================
// Helpers UI partagés
// ============================================================

/// En-tête de section seul : titre + filet + action optionnelle. Extrait pour
/// que la section articles (cartes au padding propre) le réutilise.
class _FsSectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  const _FsSectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          title,
          style: textTheme.labelLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 10),
          Text(
            action!,
            style: textTheme.labelSmall?.copyWith(
              color: colors.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}

/// En-tête de section : titre + filet + action optionnelle, puis contenu.
class _FsSection extends StatelessWidget {
  final String title;
  final String? action;
  final Widget child;

  const _FsSection({required this.title, this.action, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FsSectionHeader(title: title, action: action),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Bloc de chargement (gris doux). Pas d'animation infinie pour rester sobre
/// et respecter `prefers-reduced-motion`.
class _Skel extends StatelessWidget {
  final double? width;
  final double height;
  final FacteurColors colors;
  const _Skel({this.width, required this.height, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

// ============================================================
// Helpers data / copy
// ============================================================

/// Mot dérivé par seuils client pour une jauge d'évaluation (0–1).
String _gaugeWord(double value) {
  if (value >= 0.85) return 'Élevée';
  if (value >= 0.65) return 'Bonne';
  if (value >= 0.5) return 'Correcte';
  if (value >= 0.35) return 'Limitée';
  return 'Faible';
}

/// Copie fiabilité alignée : Solide / Mitigée / Fragile / Pas encore évaluée.
String _reliabilityLabel(String reliabilityScore) {
  switch (reliabilityScore) {
    case 'high':
      return 'Solide';
    case 'medium':
    case 'mixed':
      return 'Mitigée';
    case 'low':
      return 'Fragile';
    default:
      return 'Pas encore évaluée';
  }
}

Color _reliabilityColor(String reliabilityScore, FacteurColors colors) {
  switch (reliabilityScore) {
    case 'high':
      return colors.success;
    case 'medium':
    case 'mixed':
      return colors.warning;
    case 'low':
      return colors.error;
    default:
      return colors.textTertiary;
  }
}

/// Label de thème pour la couverture / les tags article. Utilise le kit Flux
/// continu (`theme_color_mapping` / `topic_labels`), avec un cas spécial pour
/// la traîne `autres` regroupée côté backend.
String _coverageLabel(String theme) {
  final slug = theme.toLowerCase();
  if (slug == 'autres' || slug == 'other' || slug == 'others') return 'Autres';
  // visualFor couvre les 9 macro-thèmes ; getTopicLabel couvre les slugs fins.
  if (themeMap.containsKey(slug)) return visualFor(slug).label;
  return getTopicLabel(slug);
}

/// Couleur de thème via le kit Flux continu (jamais une table en dur).
Color _coverageColor(String theme, FacteurColors colors) {
  final slug = theme.toLowerCase();
  if (slug == 'autres' || slug == 'other' || slug == 'others') {
    return colors.textTertiary;
  }
  if (themeMap.containsKey(slug)) return visualFor(slug).accent;
  return getThemeColor(slug, colors);
}

/// Domaine lisible à partir d'une URL de source (sans `www.`).
String? _domainOf(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) {
    // Peut déjà être un domaine nu.
    final cleaned = url.trim().replaceFirst(RegExp(r'^https?://'), '');
    return cleaned.isEmpty ? null : cleaned.replaceFirst('www.', '');
  }
  return uri.host.replaceFirst('www.', '');
}

/// Temps relatif FR (« il y a 2 heures », « hier »). `null` si date absente.
String? _relativeTime(String publishedAt) {
  if (publishedAt.trim().isEmpty) return null;
  final date = DateTime.tryParse(publishedAt);
  if (date == null) return null;
  return timeago.format(date, locale: 'fr');
}

/// Caption couverture en mode normal, dérivée du volume 30 j du profil.
/// Aligne la copie sur celle calculée côté backend pour `/coverage`.
String _coverageCaption(int total) {
  final noun = total == 1 ? 'article publié' : 'articles publiés';
  return '${_formatThousands(total)} $noun sur la période';
}

/// Sépare les milliers par une espace fine insécable (« 3 012 »).
String _formatThousands(int value) {
  final s = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(_nnbsp);
    buffer.write(s[i]);
  }
  return buffer.toString();
}

/// Décoration commune des cartes `surface` de la fiche : pas de bordure, ombre
/// douce. Centralisée pour qu'un ajustement du rayon ou de l'ombre se fasse en
/// un seul endroit.
BoxDecoration _fsCardDecoration(FacteurColors colors) {
  return BoxDecoration(
    color: colors.surface,
    borderRadius: BorderRadius.circular(FacteurRadius.large),
    boxShadow: const [
      BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
  );
}
