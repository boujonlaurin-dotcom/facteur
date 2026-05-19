import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../repositories/feed_repository.dart' show HighlightSpan, TokenSpan;

/// Reconstruit un titre original avec diff lexical façon mockup hi-fi.
///
/// * **Mode 3 fidèle** (`sharedTokens` non-null/non-vide) : tokens partagés
///   avec la référence rendus en `text_tertiary` (atténué), tokens divergents
///   (`highlightSpans`) rendus avec un wash de la couleur du bias, le reste
///   en `text_primary`.
/// * **Mode 2 fallback** (`sharedTokens` vide → back pas encore déployé) :
///   tokens hors `highlightSpans` rendus en `text_tertiary` pour faire
///   ressortir les key spans malgré l'absence de shared explicites.
///
/// Animation : à `animateIn=true` (typiquement déclenché à l'ouverture de la
/// carte dépliée), les spans (shared + key) apparaissent en cascade
/// séquentielle ordonnée par `start` — 220 ms par span (`Curves.easeOutCubic`),
/// 25 ms d'écart. Feeling : « Facteur scanne le titre et marque ce qui
/// diverge ». À `animateIn=false`, l'état final est rendu directement (utile
/// pour tests et reconstructions post-animation).
class DiffTitle extends StatefulWidget {
  final String title;
  final List<HighlightSpan> highlightSpans;
  final List<TokenSpan> sharedTokens;
  final Color biasColor;
  final TextStyle baseStyle;
  final bool animateIn;
  final int maxLines;

  /// Délai avant que la cascade commence (laisse le panel se positionner
  /// avant l'animation pour éviter le jank d'expand).
  static const Duration kStartDelay = Duration(milliseconds: 80);
  static const Duration kPerSpan = Duration(milliseconds: 220);
  static const Duration kSpanGap = Duration(milliseconds: 25);

  const DiffTitle({
    super.key,
    required this.title,
    required this.highlightSpans,
    required this.sharedTokens,
    required this.biasColor,
    required this.baseStyle,
    this.animateIn = true,
    this.maxLines = 4,
  });

  @override
  State<DiffTitle> createState() => _DiffTitleState();
}

class _DiffTitleState extends State<DiffTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_Chunk> _chunks;
  late int _animatedSpanCount;

  @override
  void initState() {
    super.initState();
    _rebuildChunks();
    _controller = AnimationController(
      vsync: this,
      duration: _totalDuration(),
    );
    if (widget.animateIn && _animatedSpanCount > 0) {
      Future.delayed(DiffTitle.kStartDelay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(DiffTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final needsRebuild = oldWidget.title != widget.title ||
        oldWidget.highlightSpans != widget.highlightSpans ||
        oldWidget.sharedTokens != widget.sharedTokens;
    if (needsRebuild) {
      _rebuildChunks();
      _controller.duration = _totalDuration();
      _controller.value = widget.animateIn ? 0 : 1;
      if (widget.animateIn && _animatedSpanCount > 0) {
        _controller.forward();
      }
    } else if (oldWidget.animateIn != widget.animateIn && !widget.animateIn) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _totalDuration() {
    if (_animatedSpanCount == 0) return Duration.zero;
    final ms = (_animatedSpanCount - 1) * DiffTitle.kSpanGap.inMilliseconds +
        DiffTitle.kPerSpan.inMilliseconds;
    return Duration(milliseconds: ms);
  }

  /// Tokenise le titre en chunks ordonnés [(start, end, type)] couvrant
  /// 100 % de la chaîne (les "plain" comblent les trous entre spans).
  void _rebuildChunks() {
    final title = widget.title;
    final titleLen = title.length;
    final useSharedAsTertiary = widget.sharedTokens.isNotEmpty;

    final spans = <_RawSpan>[];
    for (final s in widget.highlightSpans) {
      final start = s.start.clamp(0, titleLen);
      final end = s.end.clamp(start, titleLen);
      if (end > start) spans.add(_RawSpan(start, end, _ChunkType.key));
    }
    if (useSharedAsTertiary) {
      for (final s in widget.sharedTokens) {
        final start = s.start.clamp(0, titleLen);
        final end = s.end.clamp(start, titleLen);
        if (end > start) spans.add(_RawSpan(start, end, _ChunkType.shared));
      }
    }
    spans.sort((a, b) => a.start.compareTo(b.start));

    // Walk the title and emit chunks. The back guarantees shared/key are
    // disjoint per lemma — overlaps shouldn't happen, but if they do we
    // give precedence to the first emitted span and skip overlapping bytes.
    final chunks = <_Chunk>[];
    var cursor = 0;
    var animIndex = 0;
    for (final span in spans) {
      if (span.start < cursor) continue;
      if (span.start > cursor) {
        chunks.add(_Chunk(
          text: title.substring(cursor, span.start),
          type: _ChunkType.plain,
        ));
      }
      chunks.add(_Chunk(
        text: title.substring(span.start, span.end),
        type: span.type,
        animIndex: animIndex,
      ));
      animIndex++;
      cursor = span.end;
    }
    if (cursor < titleLen) {
      // Fallback Mode 2 : si aucun shared explicite, atténuer le hors-key
      // en tertiary pour faire ressortir les key.
      final tailType = (!useSharedAsTertiary && spans.isNotEmpty)
          ? _ChunkType.dimmedFallback
          : _ChunkType.plain;
      chunks.add(_Chunk(text: title.substring(cursor), type: tailType));
    }

    _chunks = chunks;
    _animatedSpanCount = animIndex;

    // Mode 2 : passe en revue tout le titre — les portions plain qui ne sont
    // pas key doivent être en tertiary. On corrige les chunks plain en
    // dimmedFallback si on est en Mode 2. Requiert au moins un key span :
    // sans aucun span (back retourne highlight_spans=[] et shared_tokens=[],
    // ex. cluster_id NULL), tout dimmer ferait apparaître le titre uniformément
    // en gris — le comportement attendu est un rendu plain textPrimary normal.
    if (!useSharedAsTertiary && _animatedSpanCount > 0) {
      for (var i = 0; i < _chunks.length; i++) {
        if (_chunks[i].type == _ChunkType.plain) {
          _chunks[i] = _Chunk(text: _chunks[i].text, type: _ChunkType.dimmedFallback);
        }
      }
    }
  }

  double _easedProgressFor(int spanIndex) {
    if (_animatedSpanCount == 0) return 1.0;
    final totalMs = _totalDuration().inMilliseconds;
    if (totalMs == 0) return 1.0;
    final currentMs = _controller.value * totalMs;
    final startMs = spanIndex * DiffTitle.kSpanGap.inMilliseconds;
    final localMs = (currentMs - startMs).clamp(
      0.0,
      DiffTitle.kPerSpan.inMilliseconds.toDouble(),
    );
    final localT = localMs / DiffTitle.kPerSpan.inMilliseconds;
    return Curves.easeOutCubic.transform(localT);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final spans = <InlineSpan>[];
        for (final chunk in _chunks) {
          spans.add(_buildInlineSpan(chunk, colors));
        }
        return RichText(
          text: TextSpan(style: widget.baseStyle, children: spans),
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  InlineSpan _buildInlineSpan(_Chunk chunk, FacteurColors colors) {
    switch (chunk.type) {
      case _ChunkType.plain:
        return TextSpan(
          text: chunk.text,
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w400),
        );
      case _ChunkType.dimmedFallback:
        return TextSpan(
          text: chunk.text,
          style: TextStyle(color: colors.textTertiary, fontWeight: FontWeight.w400),
        );
      case _ChunkType.shared:
        final t = _easedProgressFor(chunk.animIndex);
        final color = Color.lerp(colors.textPrimary, colors.textTertiary, t)!;
        return TextSpan(
          text: chunk.text,
          style: TextStyle(color: color, fontWeight: FontWeight.w400),
        );
      case _ChunkType.key:
        final t = _easedProgressFor(chunk.animIndex);
        return WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: widget.biasColor.withValues(alpha: 0.22 * t),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              chunk.text,
              style: widget.baseStyle.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
    }
  }
}

enum _ChunkType { plain, shared, key, dimmedFallback }

class _Chunk {
  final String text;
  final _ChunkType type;
  final int animIndex;
  const _Chunk({required this.text, required this.type, this.animIndex = -1});
}

class _RawSpan {
  final int start;
  final int end;
  final _ChunkType type;
  const _RawSpan(this.start, this.end, this.type);
}
