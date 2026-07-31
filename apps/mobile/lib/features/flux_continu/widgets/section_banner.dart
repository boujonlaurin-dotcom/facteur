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

  /// Story 23.4 — optional settings affordance (tune button). Only wired for
  /// the veille section → opens the veille config in edit mode. Rendered inline
  /// in the title, right after the favorite star (order: titre ★ ⚙), so it is
  /// visible in the flow rather than floating. As a nested `InkWell` it stays an
  /// independent hit target, capturing taps before the banner's fold InkWell
  /// (descendant wins over ancestor).
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

  /// Story 22.3 — quand true, le banner pose un badge « Choisie pour vous »
  /// au-dessus du titre, tappable via [onTapInfo] (ouvre la sheet « Pourquoi
  /// cette section ? »). Signale une section suggérée par le facteur.
  final bool suggested;

  /// Tap sur le badge « Choisie pour vous » → sheet explicative + actions
  /// (garder / retirer). Null hors sections suggérées.
  final VoidCallback? onTapInfo;

  /// Story 22.6 (redesign) — quand non null, une puce d'action « Ajouter à
  /// l'Essentiel » est posée **sur la ligne de la balise** « Choisie pour
  /// vous » : promeut la section suggérée en favorite sans passer par la sheet.
  /// La puce gère localement son spinner + l'anti double-tap. Vit dans la ligne
  /// de la balise (hauteur banner inchangée) → aucun contenu tappable sous les
  /// cartes, donc pas de dérive du budget snap/fit.
  final Future<void> Function()? onPromote;

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
    this.suggested = false,
    this.onTapInfo,
    this.onPromote,
  });

  static final _titleStyleLarge = GoogleFonts.fraunces(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.12,
    letterSpacing: -0.4,
  );

  static final _titleStyleInline = GoogleFonts.fraunces(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.08,
    letterSpacing: -0.4,
  );

  static final _blurbStyleLarge = GoogleFonts.dmSans(
    fontSize: 13,
    height: 1.42,
  );

  static final _blurbStyleInline = GoogleFonts.dmSans(
    fontSize: 12,
    height: 1.36,
  );

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
      margin: const EdgeInsets.fromLTRB(0, 2, 0, 4),
      // Thematic sections have no blurb — a single title line doesn't need
      // the taller editorial floor, so we drop it to keep the scroll tight.
      // The `large` page-hero variant gets a taller floor to breathe, while
      // content can still grow naturally when title/blurb wrap.
      constraints: BoxConstraints(
        minHeight: hasBlurb ? (large ? 116 : 70) : (large ? 48 : 46),
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: large
              ? [accent.withValues(alpha: 0.09), accent.withValues(alpha: 0.02)]
              : [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.02)],
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
                // Le halo radial hérité du hero-card FeedScreen (180×112) est
                // bien plus haut que le bandeau inline compacté (~44px) : coupé
                // net au bord bas (clipBehavior antiAlias) avant d'avoir fondu
                // vers alpha 0, il laissait une couture de couleur visible en
                // bas à droite. En inline, on borne la boîte à la hauteur du
                // bandeau pour que le dégradé finisse de fondre avant le clip.
                // La variante `large` (Flâner, hero haut) garde le halo complet.
                width: large ? 180 : 150,
                height: large ? 112 : 48,
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
          Padding(
            // With a blurb the content fills `minHeight` exactly, so the
            // centered column has no slack and the accent dash sticks to the
            // fixed top inset — making the section feel cramped vs the
            // thematic (blurb-less) banners, whose slack lets the dash drift
            // down. Add a few px of top inset on the blurb variant to match
            // the thematic dash's apparent inset.
            padding: large
                ? const EdgeInsets.fromLTRB(18, 18, 14, 16)
                : EdgeInsets.fromLTRB(
                    16,
                    hasBlurb ? 12 : 12,
                    12,
                    hasBlurb ? 8 : 6,
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (suggested) ...[
                        // Balise + CTA texte sur une même ligne, qui ne doit
                        // JAMAIS sauter de ligne (demande PO) : `Row` avec la
                        // balise à taille fixe et le CTA `Flexible`, qui
                        // rétrécit (et tronque son texte en ellipsis) plutôt
                        // que de wrapper ou de lever un RenderFlex overflow.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _SuggestedBadge(accent: accent, onTap: onTapInfo),
                            if (onPromote != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: _PromoteChip(
                                  accent: accent,
                                  onPromote: onPromote!,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      _AccentDash(accent: accent, large: large),
                      Padding(
                        padding: EdgeInsets.only(
                          top: 2,
                          bottom: hasBlurb ? (large ? 10 : 8) : 0,
                        ),
                        child: Text.rich(
                          // Borne le titre : la page Flâner (`large`) tolère
                          // 2 lignes, mais les bannières inline (dont la
                          // veille, au label long `Ma veille — {config}`)
                          // restent sur 1 ligne pour ne jamais dépasser le
                          // budget de hauteur `kBannerHeightWithBlurb` que le
                          // snap/fit suppose.
                          maxLines: large ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          TextSpan(
                            text: title,
                            children: <InlineSpan>[
                              if (tappable) ...[
                                // Chevron de tappabilité : glyphe « > » dans le
                                // style exact du titre (Fraunces, même poids),
                                // agrandi (~1.3×) pour se lire comme la
                                // continuité actionnable du titre. WidgetSpan
                                // centré verticalement → alignement propre sans
                                // baseline décalée.
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: large ? 6 : 5,
                                    ),
                                    child: Text(
                                      '>',
                                      style:
                                          (large
                                                  ? _titleStyleLarge
                                                  : _titleStyleInline)
                                              .copyWith(
                                                color: colors.textPrimary,
                                                fontSize:
                                                    (large ? 24 : 16) * 1.3,
                                                height: 1.0,
                                              ),
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
                              // Réglages veille inline, juste après l'étoile
                              // favori (ordre : titre ★ ⚙). Hit target
                              // indépendant : l'InkWell du bouton gagne sur
                              // l'InkWell de pli du banner (descendant > ancêtre).
                              if (onTapSettings != null) ...[
                                const TextSpan(text: ' '),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: _SettingsButton(
                                    color: colors.textSecondary,
                                    border: colors.border,
                                    onTap: onTapSettings!,
                                  ),
                                ),
                              ],
                            ],
                            style:
                                (large ? _titleStyleLarge : _titleStyleInline)
                                    .copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ),
                      if (hasBlurb)
                        Text(
                          effectiveBlurb,
                          // Défensif : même budget 82px — borne le blurb pour
                          // garder une hauteur déterministe.
                          maxLines: large ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: (large ? _blurbStyleLarge : _blurbStyleInline)
                              .copyWith(color: colors.textSecondary),
                        ),
                    ],
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
                ] else if (large && illustrationAsset != null) ...[
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
            'Choisi pour toi',
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

/// Story 22.6 (redesign, puis allégé sur demande PO) — CTA texte « Ajouter à
/// l'Essentiel » posé sur la ligne de la balise « Choisie pour vous ».
/// Remplace l'ancien `_PromoteSuggestionButton` (FilledButton pleine largeur
/// sous les cartes, qui cassait le budget snap/fit) puis l'ex-puce teintée
/// (fond + bordure), jugée encore trop lourde : ici du simple texte inline,
/// registre "discret" repris du CTA « Tout lire › » de `section_block.dart`
/// (pas de fond/bordure). Reprend telle quelle la logique métier de l'ancien
/// bouton : flag `_pending` anti double-tap, capture du `ScaffoldMessenger`
/// avant l'await (le CTA peut être démonté quand la section devient favorite),
/// SnackBar de succès, `finally` + garde `mounted`.
class _PromoteChip extends StatefulWidget {
  const _PromoteChip({required this.accent, required this.onPromote});

  final Color accent;
  final Future<void> Function() onPromote;

  @override
  State<_PromoteChip> createState() => _PromoteChipState();
}

class _PromoteChipState extends State<_PromoteChip> {
  bool _pending = false;

  Future<void> _handlePromote() async {
    if (_pending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pending = true);
    try {
      await widget.onPromote();
      // Succès uniquement : un throw saute directement au `finally`.
      messenger.showSnackBar(
        const SnackBar(content: Text('Ajouté à ton Essentiel')),
      );
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Semantics(
      button: true,
      label: 'Ajouter à ton Essentiel',
      child: GestureDetector(
        // Hit target élargi au-delà du visuel (~44px, FES §7.2) : le
        // `HitTestBehavior.opaque` capte les taps sur tout le rectangle du
        // CTA, marges de la ligne comprises.
        behavior: HitTestBehavior.opaque,
        onTap: _pending ? null : _handlePromote,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pending
                  ? SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: accent,
                      ),
                    )
                  : Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      size: 11,
                      color: accent,
                    ),
              const SizedBox(width: 4),
              // `Flexible` + ellipsis sur une ligne : jamais de saut de ligne
              // ni de RenderFlex overflow, la fin du libellé se tronque en
              // priorité quand l'espace manque (demande PO).
              Flexible(
                child: Text(
                  'Ajouter à ton Essentiel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        width: large ? 28 : 22,
        height: 3,
        margin: const EdgeInsets.only(bottom: 5),
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
