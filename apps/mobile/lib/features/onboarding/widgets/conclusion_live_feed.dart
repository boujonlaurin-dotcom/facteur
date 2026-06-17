import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../sources/models/source_recent_items.dart';
import '../onboarding_strings.dart';

/// Animation de conclusion « vivante » : les logos des sources choisies
/// apparaissent, puis leurs vrais derniers titres « arrivent » un à un avec
/// un compteur. La preuve que les sources sont réellement connectées.
///
/// Tolère l'arrivée tardive de données ([didUpdateWidget] ajoute en fin de
/// file sans réordonner ce qui est déjà révélé — compteur monotone).
class ConclusionLiveFeed extends StatefulWidget {
  final List<SourceRecentItems> entries;

  /// Cadence de révélation des titres (exposée pour les tests).
  final Duration revealInterval;

  /// Phase de completion : l'API a répondu, on finit calmement de monter le
  /// compteur jusqu'à son total avant la navigation.
  final bool isCompleting;

  const ConclusionLiveFeed({
    super.key,
    required this.entries,
    this.revealInterval = const Duration(milliseconds: 1000),
    this.isCompleting = false,
  });

  @override
  State<ConclusionLiveFeed> createState() => _ConclusionLiveFeedState();
}

class _FeedItem {
  final String sourceId;
  final String sourceName;
  final String? logoUrl;
  final String title;

  const _FeedItem({
    required this.sourceId,
    required this.sourceName,
    required this.logoUrl,
    required this.title,
  });
}

class _ConclusionLiveFeedState extends State<ConclusionLiveFeed> {
  /// Fenêtre de titres visibles simultanément.
  static const int _windowSize = 5;

  /// Nombre maximum d'articles révélés : on ne montre que les tops articles
  /// de « Ton Essentiel » (3 à 5), pas tout le flux des sources — un compteur
  /// calme et lisible plutôt qu'un défilement épileptique.
  static const int _maxReveal = 5;

  /// Logos affichés dans la strip avant le badge « +N ».
  static const int _maxLogos = 8;

  final List<_FeedItem> _queue = [];
  final Set<String> _seenKeys = {};
  int _revealed = 0;
  Timer? _timer;
  Timer? _completionTimer;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ingest(widget.entries);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion) {
      _timer?.cancel();
      _timer = null;
      _revealed = _queue.length;
    } else {
      _ensureTimer();
    }
  }

  @override
  void didUpdateWidget(ConclusionLiveFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ingest(widget.entries);
    if (_reduceMotion) {
      _revealed = _queue.length;
    } else if (widget.isCompleting && !oldWidget.isCompleting) {
      // Entrée en phase de completion : on accélère le timer pour flusher
      // rapidement le compteur jusqu'au total avant la navigation.
      _speedUpTimer();
    }
  }

  /// Termine calmement la révélation des derniers titres restants (≤ quelques
  /// articles vu le cap [_maxReveal]) avant que l'écran ne soit quitté. Cadence
  /// posée (280 ms) pour éviter tout défilement épileptique.
  void _speedUpTimer() {
    if (_reduceMotion) return;
    _timer?.cancel();
    _timer = null;
    _completionTimer?.cancel();
    _completionTimer = Timer.periodic(
      const Duration(milliseconds: 280),
      (timer) {
        if (_revealed >= _queue.length) {
          timer.cancel();
          return;
        }
        setState(() => _revealed++);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _completionTimer?.cancel();
    super.dispose();
  }

  /// Entrelace les titres en round-robin entre les sources (plus « vivant »
  /// que source par source) et n'ajoute que les paires jamais vues, en fin
  /// de file — jamais de réordonnancement de ce qui est déjà révélé.
  void _ingest(List<SourceRecentItems> entries) {
    final maxItems = entries.fold<int>(
      0,
      (max, e) => e.items.length > max ? e.items.length : max,
    );
    for (var i = 0; i < maxItems; i++) {
      for (final entry in entries) {
        // Cap : on ne révèle que les tops articles (≤ _maxReveal).
        if (_queue.length >= _maxReveal) return;
        if (i >= entry.items.length) continue;
        final title = entry.items[i].title;
        if (title.isEmpty) continue;
        if (!_seenKeys.add('${entry.sourceId}|$title')) continue;
        _queue.add(_FeedItem(
          sourceId: entry.sourceId,
          sourceName: entry.name,
          logoUrl: entry.logoUrl,
          title: title,
        ));
      }
    }
  }

  void _ensureTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(widget.revealInterval, (_) {
      if (_revealed >= _queue.length) return;
      setState(() => _revealed++);
      // Haptique parcimonieuse : un tic toutes les 5 révélations.
      if (_revealed % 5 == 1) {
        HapticFeedback.selectionClick();
      }
    });
  }

  List<_FeedItem> get _visibleItems {
    if (_revealed == 0) return const [];
    final start = _revealed > _windowSize ? _revealed - _windowSize : 0;
    return _queue.sublist(start, _revealed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sources = <String, SourceRecentItems>{
      for (final e in widget.entries) e.sourceId: e,
    }.values.toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoStrip(
          sources: sources,
          maxLogos: _maxLogos,
          reduceMotion: _reduceMotion,
        ),
        const SizedBox(height: FacteurSpacing.space6),
        SizedBox(
          height: 5 * 36.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final item in _visibleItems)
                _TitleRow(
                  key: ValueKey('${item.sourceId}|${item.title}'),
                  item: item,
                  reduceMotion: _reduceMotion,
                ),
            ],
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),
        Semantics(
          liveRegion: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              OnboardingStrings.conclusionLiveCounter(
                _revealed,
                sources.length,
              ),
              key: ValueKey(_revealed),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

/// Strip de logos des sources connectées, apparition décalée.
class _LogoStrip extends StatelessWidget {
  final List<SourceRecentItems> sources;
  final int maxLogos;
  final bool reduceMotion;

  const _LogoStrip({
    required this.sources,
    required this.maxLogos,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final visible = sources.take(maxLogos).toList();
    final overflow = sources.length - visible.length;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: FacteurSpacing.space2,
      runSpacing: FacteurSpacing.space2,
      children: [
        for (var i = 0; i < visible.length; i++)
          _StaggeredFadeIn(
            delay: reduceMotion
                ? Duration.zero
                : Duration(milliseconds: 120 * i),
            child: _SourceLogo(source: visible[i]),
          ),
        if (overflow > 0)
          _StaggeredFadeIn(
            delay: reduceMotion
                ? Duration.zero
                : Duration(milliseconds: 120 * visible.length),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+$overflow',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SourceLogo extends StatelessWidget {
  final SourceRecentItems source;

  const _SourceLogo({required this.source});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final fallback = Container(
      color: colors.backgroundSecondary,
      alignment: Alignment.center,
      child: Text(
        source.name.isNotEmpty ? source.name[0].toUpperCase() : '?',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: source.logoUrl != null && source.logoUrl!.isNotEmpty
          ? FacteurImage(
              imageUrl: source.logoUrl!,
              fit: BoxFit.cover,
              errorWidget: (context) => fallback,
            )
          : fallback,
    );
  }
}

/// Ligne de titre fraîchement « arrivée » (fade + légère montée).
class _TitleRow extends StatelessWidget {
  final _FeedItem item;
  final bool reduceMotion;

  const _TitleRow({super.key, required this.item, required this.reduceMotion});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final row = SizedBox(
      height: 36,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              item.title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (reduceMotion) return row;
    return _StaggeredFadeIn(delay: Duration.zero, child: row);
  }
}

/// Fade-in + slide-up de 8px, jouable avec un délai (stagger).
class _StaggeredFadeIn extends StatelessWidget {
  final Duration delay;
  final Widget child;

  const _StaggeredFadeIn({required this.delay, required this.child});

  @override
  Widget build(BuildContext context) {
    final total = delay + const Duration(milliseconds: 350);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        total.inMilliseconds == 0
            ? 0
            : delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
