import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../sources/widgets/source_logo_avatar.dart';

/// Banner that opens a Flux Continu V1.8 section.
///
/// Visual treatment mirrors the FeedScreen hero carrousel cards
/// (`DigestEntryCard._CarouselCard`) — same radial veil and asset
/// incrustation — so the two surfaces feel like one family.
class SectionBanner extends StatelessWidget {
  final String title;
  final String? blurb;
  final Color accent;
  final String? illustrationAsset;

  /// Optional callback for the inline favorite star, posed at the end of the
  /// title's last line. When null, no star is rendered — the banner layout is
  /// strictly identical to the legacy V1.8 banner. Only the two user-favorite
  /// sections (theme1 / theme2) wire this up.
  final VoidCallback? onTapFavorite;

  /// Story 23.4 — optional settings affordance (top-right tune button). Only
  /// wired for the veille section → opens the veille config in edit mode. As
  /// an independent hit target it sits **outside** the `IgnorePointer`s so it
  /// captures taps before the banner's fold InkWell.
  final VoidCallback? onTapSettings;

  /// When true, the banner renders in a larger "page hero" variant (bigger
  /// title / blurb / illustration and a taller floor). Used by the dedicated
  /// Flâner page to distinguish it from the inline thematic banners. Default
  /// [false] keeps the thematic banners pixel-identical.
  final bool large;

  /// PR « Sources dans la Tournée » — quand non null, le hero rend le **logo
  /// de la source** (net, sans le fadeout d'illustration) à la place de
  /// [illustrationAsset]. Le nom de la source ([title]) sert de fallback en
  /// initiales si le logo réseau échoue.
  final String? logoUrl;

  /// Story 10.1 — banner cliquable : remplace le CTA « Tout lire » de bas de
  /// section. Quand non null, le banner entier devient tappable et le titre
  /// gagne un chevron « > » fin couleur accent. Ignoré en variante [large]
  /// (page Flâner : pas de navigation de section).
  final VoidCallback? onTap;

  /// Nombre d'articles non affichés (`totalCount - coreVisibleCount`).
  /// Rendu en « +X » gris discret après le chevron quand > 0 et [onTap]
  /// est câblé.
  final int hiddenCount;

  /// Story 22.3 — quand true, le banner pose un badge « Choisie pour vous »
  /// au-dessus du titre, tappable via [onTapInfo] (ouvre la sheet « Pourquoi
  /// cette section ? »). Signale une section suggérée par le facteur.
  final bool suggested;

  /// Tap sur le badge « Choisie pour vous » → sheet explicative + actions
  /// (garder / retirer). Null hors sections suggérées.
  final VoidCallback? onTapInfo;

  const SectionBanner({
    super.key,
    required this.title,
    required this.accent,
    this.blurb,
    this.illustrationAsset,
    this.onTapFavorite,
    this.onTapSettings,
    this.large = false,
    this.logoUrl,
    this.onTap,
    this.hiddenCount = 0,
    this.suggested = false,
    this.onTapInfo,
  });

  double _trailingControlReserve() {
    if (onTapSettings != null) return 58;
    return 0;
  }

  String? _displayBlurbFor(String title, String? rawBlurb) {
    // Keep the visible copy current even when a route was opened with a stale
    // section snapshot built before the provider constants changed.
    if (title.trim() == 'Actus du jour') {
      return 'Les sujets les + couverts en France.';
    }
    return rawBlurb;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // La variante `large` (page Flâner) reste non navigable : pas de chevron,
    // pas de +X, pas d'InkWell.
    final tappable = onTap != null && !large;
    final effectiveBlurb = _displayBlurbFor(title, blurb);
    final hasBlurb = effectiveBlurb != null && effectiveBlurb.trim().isNotEmpty;
    // `width: double.infinity` is required because the parent SectionBlock
    // Column uses `CrossAxisAlignment.start`, which would otherwise size
    // this Container to its intrinsic width and leave parchment showing
    // past the gradient on the right.
    // Inline sections keep a top-only radius because the cards below the
    // banner butt up against its bottom edge. The large Flâner hero stands
    // alone, so it gets the same radius on every corner.
    const inlineRadius = BorderRadius.vertical(
      top: Radius.circular(FacteurRadius.large),
    );
    const largeRadius = BorderRadius.all(Radius.circular(FacteurRadius.large));
    final borderRadius = large ? largeRadius : inlineRadius;
    final container = Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 3, 0, 5),
      // Thematic sections have no blurb — a single title line doesn't need
      // the taller editorial floor, so we drop it to keep the scroll tight.
      // The `large` page-hero variant gets a taller floor to breathe, while
      // content can still grow naturally when title/blurb wrap.
      constraints: BoxConstraints(
        minHeight: hasBlurb ? (large ? 140 : 92) : 60,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.09),
            accent.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Mirrors `DigestEntryCard._CarouselCard` so the two surfaces
          // share the same hero-card identity.
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 112,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.0,
                    colors: [
                      accent.withValues(alpha: 0.07),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bouton réglages (veille) — hit target indépendant, hors
          // IgnorePointer pour rester tappable.
          if (onTapSettings != null)
            Positioned(
              top: 8,
              right: 10,
              child: _SettingsButton(
                color: colors.textSecondary,
                border: colors.border,
                onTap: onTapSettings!,
              ),
            ),
          Padding(
            // With a blurb the content fills `minHeight` exactly, so the
            // centered column has no slack and the accent dash sticks to the
            // fixed top inset — making the section feel cramped vs the
            // thematic (blurb-less) banners, whose slack lets the dash drift
            // down. Add a few px of top inset on the blurb variant to match
            // the thematic dash's apparent inset.
            padding: large
                ? const EdgeInsets.fromLTRB(22, 24, 16, 20)
                : EdgeInsets.fromLTRB(
                    20,
                    hasBlurb ? 20 : 8,
                    14,
                    hasBlurb ? 14 : 9,
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: illustrationAsset == null
                          ? _trailingControlReserve()
                          : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (suggested) ...[
                          _SuggestedBadge(accent: accent, onTap: onTapInfo),
                          const SizedBox(height: 8),
                        ],
                        _AccentDash(accent: accent, large: large),
                        Padding(
                          padding: EdgeInsets.only(
                            top: 2,
                            bottom: hasBlurb ? (large ? 10 : 8) : 0,
                          ),
                          child: Text.rich(
                            TextSpan(
                              text: title,
                              children: <InlineSpan>[
                                if (tappable) ...[
                                  const TextSpan(text: ' '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: IgnorePointer(
                                      child: Icon(
                                        PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                                        size: 18,
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                                if (onTapFavorite != null) ...[
                                  const TextSpan(text: '  '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: _FavoriteStar(
                                      color: colors.textTertiary,
                                      onTap: onTapFavorite!,
                                    ),
                                  ),
                                ],
                              ],
                              style: GoogleFonts.fraunces(
                                fontSize: large ? 28 : 20,
                                fontWeight: FontWeight.w700,
                                height: large ? 1.12 : 1.08,
                                letterSpacing: -0.4,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        if (hasBlurb)
                          Text(
                            effectiveBlurb,
                            style: GoogleFonts.dmSans(
                              fontSize: large ? 14 : 12,
                              height: large ? 1.42 : 1.36,
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (logoUrl != null) ...[
                  const SizedBox(width: 12),
                  // Logo source rendu **net** (pas de ShaderMask ni d'Opacity
                  // 0.72 comme l'illustration thème) — un logo doit rester
                  // lisible. Fallback initiales géré par SourceLogoAvatar.
                  IgnorePointer(
                    child: SourceLogoAvatar.fromUrl(
                      logoUrl: logoUrl,
                      name: title,
                      size: large ? 96 : 62,
                      radius: 16,
                    ),
                  ),
                ] else if (illustrationAsset != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: large ? 96 : 62,
                    height: large ? 96 : 62,
                    child: IgnorePointer(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [Colors.black, Colors.transparent],
                          stops: [0.50, 1.0],
                        ).createShader(rect),
                        child: Opacity(
                          opacity: 0.72,
                          child: Image.asset(
                            illustrationAsset!,
                            height: large ? 96 : 62,
                            // Source PNGs are 1024² — decode at 2× display
                            // height to keep texture memory bounded.
                            cacheHeight: large ? 192 : 124,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (!tappable) return container;
    // Material transparent + InkWell sur tout le banner : l'étoile favorite
    // (GestureDetector opaque) et le bouton réglages (InkWell enfant) restent
    // des hit targets indépendants — le descendant gagne sur l'ancêtre.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: container,
      ),
    );
  }
}

/// Story 23.4 — bouton réglages 26×26 (tune), calqué sur le `_PersonalizeButton`
/// de l'Essentiel. Ouvre la config veille en édition.
class _SettingsButton extends StatelessWidget {
  final Color color;
  final Color border;
  final VoidCallback onTap;
  const _SettingsButton({
    required this.color,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.full),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 0.8),
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 13,
            color: color,
            semanticLabel: 'Réglages de ma veille',
          ),
        ),
      ),
    );
  }
}

/// Story 22.3 — pastille « Choisie pour vous » posée au-dessus du titre d'une
/// section suggérée. Tappable : ouvre la sheet « Pourquoi cette section ? ». Le
/// « i » signale l'affordance d'explication (transparence totale, PO).
class _SuggestedBadge extends StatelessWidget {
  final Color accent;
  final VoidCallback? onTap;

  const _SuggestedBadge({required this.accent, this.onTap});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 7, 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.34), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
            size: 11,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            'Choisie pour vous',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              color: accent,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(
              PhosphorIcons.info(PhosphorIconsStyle.bold),
              size: 12,
              color: accent.withValues(alpha: 0.85),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return badge;
    return Semantics(
      button: true,
      label: 'Pourquoi cette section est proposée',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: badge,
      ),
    );
  }
}

class _AccentDash extends StatelessWidget {
  final Color accent;
  final bool large;

  const _AccentDash({required this.accent, required this.large});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: large ? 34 : 28,
        height: 3,
        margin: const EdgeInsets.only(bottom: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

/// Inline "favorite" affordance posed at the end of a banner's title (last
/// line), used to signal that a section is one of the user's two configurable
/// favorites. Kept deliberately small — the rule is that this should not
/// disturb the title/blurb/illustration layout.
class _FavoriteStar extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _FavoriteStar({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Gérer mes thèmes favoris',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(
            PhosphorIcons.star(PhosphorIconsStyle.fill),
            size: 16,
            color: color.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
