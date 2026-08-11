import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../config/theme.dart';
import '../utils/section_fit.dart';

/// Silhouette de la pile de tri (« Ton Essentiel » swipable, Story 33.1) :
/// pile de deux cartes + barre d'actions + progression — **dans cet ordre**, le
/// même que la vraie pile depuis la reprise PO du 08/08.
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
/// La vraie carte, elle, **épouse son contenu** : la silhouette ne peut donc pas
/// lui être pixel-identique. Elle réserve [kTriageCardHeight], la hauteur d'une
/// carte pleine (bandeau image + titre long) — à ce stade ni l'URL d'image ni la
/// longueur du titre ne sont connues, et sur-réserver fait *descendre* le
/// contenu à l'hydratation, jamais sauter la barre d'actions sous le doigt.
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: kTriageCardPaddingH,
                        vertical: kTriageCardPaddingV,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          bar(width: 96, height: 11),
                          const SizedBox(height: FacteurSpacing.space3),
                          bar(width: double.infinity, height: 14),
                          const SizedBox(height: FacteurSpacing.space2),
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
          height: kTriageCardHeight,
          child: Stack(
            children: [
              // Carte du dessous **à fleur du cadre**, comme la vraie pile
              // (reprise PO 10/08) : plus de mise à l'échelle, la profondeur est
              // portée par l'opacité seule. La silhouette annonce la géométrie
              // réelle — deux géométries divergentes feraient sauter la mise en
              // page à l'hydratation.
              Positioned.fill(
                child: Opacity(
                  opacity: kTriageBackCardOpacity,
                  child: triageCard(detailed: false),
                ),
              ),
              Positioned.fill(child: triageCard(detailed: true)),
            ],
          ),
        ),
        // La **vraie** silhouette de la barre d'actions (`_ActionBar`) : deux
        // ronds puis la pilule « Je garde » qui prend le reste, aux mêmes
        // constantes partagées que la barre elle-même. La précédente (3
        // pastilles de 52 centrées) annonçait une barre qui n'existe pas, donc
        // l'attente ne ressemblait pas au contenu.
        SizedBox(
          height: kTriageActionBarHeight,
          child: Center(
            child: Row(
              children: [
                bar(
                  width: kTriageActionButtonSize,
                  height: kTriageActionButtonSize,
                  radius: FacteurRadius.pill,
                ),
                const SizedBox(width: kTriageActionGap),
                bar(
                  width: kTriageActionButtonSize,
                  height: kTriageActionButtonSize,
                  radius: FacteurRadius.pill,
                ),
                const SizedBox(width: kTriageActionGap),
                Expanded(
                  child: bar(
                    height: kTriageActionButtonSize,
                    radius: FacteurRadius.pill,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Barre de progression **sous** les boutons, exactement comme la vraie
        // pile (reprise PO 10/08) : deux ordres différents feraient sauter la
        // mise en page à l'hydratation, ce que cette silhouette existe pour
        // empêcher. Depuis la 33.4 elle compte les **gardés** : le nombre de
        // segments est l'objectif du jour, inconnu à ce stade (SharedPrefs pas
        // encore relu) → 5, la valeur par défaut. La largeur totale ne dépend
        // de toute façon pas du compte.
        SizedBox(
          height: kTriageProgressBarHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 5; i++) ...[
                if (i > 0) const SizedBox(width: kTriageProgressSegmentGap),
                Expanded(
                  child: bar(
                    height: kTriageProgressSegmentHeight,
                    radius: FacteurRadius.pill,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Contrôle d'objectif : « Je veux lire », deux ronds de
        // [kTriageTargetRoundSize] centrés dans leur cible tactile de
        // [kTriageTargetControlHeight] encadrant le chiffre, puis la fin de la
        // phrase. Mêmes constantes que le vrai contrôle.
        SizedBox(
          height: kTriageTargetControlHeight,
          child: Row(
            children: [
              bar(width: 74, height: 11),
              SizedBox(
                width: kTriageTargetControlHeight,
                child: Center(
                  child: bar(
                    width: kTriageTargetRoundSize,
                    height: kTriageTargetRoundSize,
                    radius: FacteurRadius.pill,
                  ),
                ),
              ),
              bar(width: 10, height: 12),
              SizedBox(
                width: kTriageTargetControlHeight,
                child: Center(
                  child: bar(
                    width: kTriageTargetRoundSize,
                    height: kTriageTargetRoundSize,
                    radius: FacteurRadius.pill,
                  ),
                ),
              ),
              bar(width: 112, height: 11),
            ],
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
