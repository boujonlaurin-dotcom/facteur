import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/providers/analytics_provider.dart';

/// Fraction visible minimale d'une carte pour qu'elle compte comme vue.
/// Standard MRC de viewabilité display (50 % de pixels), transposé à une carte
/// d'article : au-delà, une carte à moitié coupée par le bas de l'écran ne
/// serait jamais comptée alors qu'elle est lisible.
const double kImpressionMinVisibleFraction = 0.5;

/// Durée pendant laquelle la carte doit rester au-dessus du seuil. Standard MRC
/// (1 s pour du display). Filtre le scroll rapide : traverser la Tournée d'un
/// coup de pouce ne doit pas gonfler le dénominateur du CTR de cartes que
/// personne n'a lues.
const Duration kImpressionMinVisibleDuration = Duration(milliseconds: 1000);

/// Métadonnées d'une carte au moment de son impression — tout ce dont la jauge
/// CTR a besoin pour découper le taux (par famille de section, par rang, par
/// bande de score). Assemblées au rendu, jamais reconstruites a posteriori :
/// l'ordre des sections change d'un jour à l'autre.
@immutable
class ArticleImpressionInfo {
  final String contentId;
  final String sectionKey;

  /// `theme | source | veille | editorial`. `editorial` couvre les blocs non
  /// personnalisés (Essentiel, Actus du jour, Bonnes Nouvelles) : ils sont
  /// épinglés et ne concourent pas au classement des blocs.
  final String sectionFamily;

  /// `tournee | essentiel`. Flâner est **hors périmètre** (flux chronologique
  /// assumé — mesurer un CTR par rang n'y voudrait rien dire).
  final String surface;

  /// Rang de la section dans la Tournée du jour (0 = héros Essentiel).
  final int sectionIndex;

  /// Rang de la carte dans sa section.
  final int positionInSection;

  /// Rang de la carte dans la page entière — c'est lui qui porte l'effet de
  /// position, `positionInSection` seul ne distingue pas la 1ʳᵉ carte du haut
  /// de page de la 1ʳᵉ carte du 9ᵉ bloc.
  final int globalPosition;

  /// Score de recommandation de l'article. `null` sur les blocs éditoriaux, qui
  /// ne passent pas par le moteur de scoring personnalisé.
  final double? scoreTotal;

  /// Score du bloc qui a décidé de son rang. `null` tant que l'ordonnancement
  /// par score n'est pas branché — c'est ce champ qui reliera « ordre des
  /// blocs » et « CTR mesuré ».
  final double? blockScore;

  final String? theme;
  final String? sourceId;
  final bool isSerene;

  /// La section est **maigre** (≤1 survivant après dédup). Découpe utile : un
  /// CTR bas sur un bloc maigre ne se lit pas comme un CTR bas sur un bloc plein.
  final bool underfilled;

  const ArticleImpressionInfo({
    required this.contentId,
    required this.sectionKey,
    required this.sectionFamily,
    required this.surface,
    required this.sectionIndex,
    required this.positionInSection,
    required this.globalPosition,
    this.scoreTotal,
    this.blockScore,
    this.theme,
    this.sourceId,
    this.isSerene = false,
    this.underfilled = false,
  });
}

/// Enveloppe une carte de la Tournée ou de l'Essentiel pour compter son
/// **impression** : ≥ [kImpressionMinVisibleFraction] visible pendant
/// ≥ [kImpressionMinVisibleDuration], une fois par
/// `(contentId, sectionKey, jour)`.
///
/// Frère de `AutoGrowCandidate`, délibérément **pas** une extension de
/// celui-ci : son seuil est 0,9, il exclut les articles lus (or un article lu
/// *a été* impressionné, c'est même le numérateur du CTR) et son contrat de
/// `dispose` en microtask sert un tout autre besoin. Les deux
/// `VisibilityDetector` s'imbriquent sans conflit — chacun a sa propre clé.
class ArticleImpressionTracker extends ConsumerStatefulWidget {
  const ArticleImpressionTracker({
    super.key,
    required this.info,
    required this.dayKey,
    required this.child,
  });

  final ArticleImpressionInfo info;

  /// Jour Tournée (frontière 4 h Paris, cf. `TourneeProgressService.dayKey`) —
  /// passé plutôt que calculé ici pour que le widget reste pur et testable.
  final String dayKey;

  final Widget child;

  @override
  ConsumerState<ArticleImpressionTracker> createState() =>
      _ArticleImpressionTrackerState();
}

class _ArticleImpressionTrackerState
    extends ConsumerState<ArticleImpressionTracker> {
  Timer? _dwell;
  bool _fired = false;

  void _onVisibility(VisibilityInfo visibility) {
    if (!mounted || _fired) return;
    if (visibility.visibleFraction >= kImpressionMinVisibleFraction) {
      // `??=` : une carte qui reste visible émet plusieurs notifications
      // (scroll continu) ; réarmer le timer à chaque fois le repousserait
      // indéfiniment et aucune impression ne partirait jamais.
      _dwell ??= Timer(kImpressionMinVisibleDuration, _fire);
    } else {
      _dwell?.cancel();
      _dwell = null;
    }
  }

  void _fire() {
    _dwell = null;
    if (!mounted || _fired) return;
    _fired = true;
    final info = widget.info;
    unawaited(
      ref.read(analyticsServiceProvider).trackArticleImpression(
            contentId: info.contentId,
            sectionKey: info.sectionKey,
            sectionFamily: info.sectionFamily,
            surface: info.surface,
            dayKey: widget.dayKey,
            sectionIndex: info.sectionIndex,
            positionInSection: info.positionInSection,
            globalPosition: info.globalPosition,
            scoreTotal: info.scoreTotal,
            blockScore: info.blockScore,
            theme: info.theme,
            sourceId: info.sourceId,
            isSerene: info.isSerene,
            underfilled: info.underfilled,
          ),
    );
  }

  @override
  void dispose() {
    // Le seul état à nettoyer est le timer : rien n'est muté hors de ce widget
    // avant qu'il ne se déclenche, donc pas de contrat `dispose` fragile ici.
    _dwell?.cancel();
    _dwell = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(
        'impression_${widget.info.surface}_'
        '${widget.info.sectionKey}_${widget.info.contentId}',
      ),
      onVisibilityChanged: _onVisibility,
      child: widget.child,
    );
  }
}
