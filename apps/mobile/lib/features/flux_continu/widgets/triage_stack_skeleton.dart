import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/theme.dart';
import '../utils/section_fit.dart';

/// Silhouette de la pile de tri (« Ton Essentiel » swipable, Story 33.1) :
/// progression + pile de deux cartes + barre d'actions.
///
/// **Un seul widget pour deux points de branchement**, sans quoi les deux
/// attentes divergent :
///
/// - `_HeroSkeleton` (flux_continu_screen.dart) — le squelette d'écran, quand le
///   feed entier est encore vide. Il fournit son propre `Shimmer` (l'en-tête
///   date/météo respire du même sweep), donc `standalone: false` ;
/// - [EssentielHiFiCard] — l'attente **dans** une carte déjà rendue : le feed a
///   un snapshot frais (`isSkeleton: false`, jamais de `_FluxContinuSkeleton`)
///   mais le tri n'est pas encore déterminé (hydratation SharedPreferences
///   asynchrone, `startIfNeeded` posté après la frame). Là il n'y a pas de
///   `Shimmer` ancêtre → `standalone: true`.
///
/// La silhouette réserve [kTriageCardHeight] (la borne haute des deux hauteurs
/// de carte) : à ce stade les URLs d'image ne sont pas encore connues, et
/// sur-réserver fait descendre le contenu, jamais sauter la barre d'actions sous
/// le doigt.
class TriageStackSkeleton extends StatelessWidget {
  /// `true` ⇒ le widget porte son propre [Shimmer.fromColors] (appelé hors d'un
  /// squelette d'écran). `false` ⇒ un ancêtre en fournit déjà un.
  final bool standalone;

  const TriageStackSkeleton({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Recette canonique de l'app (`SectionSkeletonCard`, `_HeroSkeleton`) : le
    // sweep est porté par le fond, jamais par un aplat plein.
    final base = colors.textTertiary.withValues(alpha: 0.10);
    final highlight = colors.textTertiary.withValues(alpha: 0.04);

    Widget bar({double? width, required double height, double radius = 6}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    // Silhouette d'une carte de tri. `detailed: false` = simple contour, pour la
    // carte du dessous (l'épaisseur de pile).
    Widget triageCard({required bool detailed}) => Container(
          height: kTriageCardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: base, width: 1.2),
          ),
          clipBehavior: Clip.antiAlias,
          child: detailed
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: kTriageCardImageHeight,
                      width: double.infinity,
                      color: base,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(width: 96, height: 11),
                          const SizedBox(height: 12),
                          bar(width: double.infinity, height: 14),
                          const SizedBox(height: 8),
                          bar(width: 210, height: 14),
                        ],
                      ),
                    ),
                  ],
                )
              : null,
        );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kTriageProgressHeight,
          child: Center(
            child: bar(width: double.infinity, height: 6, radius: 3),
          ),
        ),
        SizedBox(
          height: kTriageCardHeight,
          child: Stack(
            children: [
              // Mêmes `scale`/`alignment` que la vraie pile (carte du dessous
              // ancrée en haut) : la silhouette annonce la géométrie réelle.
              Positioned.fill(
                child: Transform.scale(
                  scale: 0.96,
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: 0.5,
                    child: triageCard(detailed: false),
                  ),
                ),
              ),
              Positioned.fill(child: triageCard(detailed: true)),
            ],
          ),
        ),
        // La **vraie** silhouette de la barre d'actions (`_ActionBar`) : deux
        // ronds de 44 puis la pilule « Je garde » qui prend le reste. La
        // précédente (3 pastilles de 52 centrées) annonçait une barre qui
        // n'existe pas, donc l'attente ne ressemblait pas au contenu.
        SizedBox(
          height: kTriageActionBarHeight,
          child: Center(
            child: Row(
              children: [
                bar(width: 44, height: 44, radius: FacteurRadius.pill),
                const SizedBox(width: 10),
                bar(width: 44, height: 44, radius: FacteurRadius.pill),
                const SizedBox(width: 10),
                Expanded(
                  child: bar(height: 44, radius: FacteurRadius.pill),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!standalone) return content;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: content,
    );
  }
}
