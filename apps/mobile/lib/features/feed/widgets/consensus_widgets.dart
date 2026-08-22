import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../flux_continu/widgets/coverage_chip.dart' show SourceDot;
import '../repositories/feed_repository.dart';

// ─── Copy 6C (Story 35.3) — constantes assertables, aucun em-dash ───────────
// `{N}` = toujours `coverageCount` servi (invariant #1104).

const String consensusSectionTitle = 'Analyse des angles';

String consensusCompareCtaLabel(int coverageCount) =>
    'Comparer les $coverageCount angles';

String consensusPendingCtaText(int coverageCount) =>
    'Analyse des angles en cours : les $coverageCount articles sont déjà '
    'consultables.';

String consensusSoloText(String sourceName) =>
    "$sourceName est pour l'instant la seule rédaction à avoir couvert ce "
    "sujet : il n'y a pas encore d'angles à comparer.";

String consensusConvergentFootnote(int coverageCount) =>
    'Aucun désaccord relevé : les $coverageCount médias racontent la même '
    'chose.';

String consensusPendingFootnote(int coverageCount) =>
    'Les accords et désaccords entre ces $coverageCount articles ne sont pas '
    "encore disponibles. Ils apparaîtront ici dès que l'analyse sera "
    'terminée.';

String consensusCarouselSubtitle(int coverageCount) =>
    '$coverageCount médias en parlent';

const String consensusAiCardTitle = 'Analyse complète IA';

String consensusAiCardBody(int coverageCount) =>
    'Aller plus loin : les $coverageCount angles décortiqués.';

const String consensusAiCardAction = 'Lancer';

/// Libellé français du `qualifier` backend. Jamais re-dérivé des listes.
String? consensusQualifierLabel(String? qualifier) {
  switch (qualifier) {
    case 'polarized':
      return 'polarisé';
    case 'varied':
      return 'avis variés';
    case 'convergent':
      return 'avis convergents';
    default:
      return null;
  }
}

// ─── Résolution domaine → identité de source ────────────────────────────────

/// Identité affichable d'un domaine porté par un constat.
class ConsensusSourceRef {
  final String domain;
  final String name;
  final String biasStance;
  final String? logoUrl;

  const ConsensusSourceRef({
    required this.domain,
    required this.name,
    this.biasStance = 'unknown',
    this.logoUrl,
  });
}

String _normalizeDomain(String raw) {
  var domain = raw.trim().toLowerCase();
  if (domain.startsWith('www.')) domain = domain.substring(4);
  return domain;
}

/// Résout chaque domaine de `display_domains` en (nom, biais, logo), dans
/// l'ordre servi. Match sur `perspectives[].sourceDomain` (normalisé
/// lowercase / sans www) d'abord, puis sur le domaine du média lu (biais =
/// `source_bias_stance`), sinon fallback nom = domaine nu, biais `unknown`.
/// Logo = favicon Google s2 (FacteurImage gère le fallback initiale).
List<ConsensusSourceRef> resolveConsensusRefs({
  required List<String> domains,
  required List<PerspectiveData> perspectives,
  String? readerDomain,
  String? readerSourceName,
  String readerBias = 'unknown',
}) {
  final byDomain = <String, PerspectiveData>{};
  for (final p in perspectives) {
    final key = _normalizeDomain(p.sourceDomain);
    if (key.isNotEmpty) byDomain.putIfAbsent(key, () => p);
  }
  final normalizedReader =
      readerDomain == null ? '' : _normalizeDomain(readerDomain);

  return domains.map((raw) {
    final domain = _normalizeDomain(raw);
    final logoUrl = domain.isEmpty
        ? null
        : 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
    final matched = byDomain[domain];
    if (matched != null) {
      return ConsensusSourceRef(
        domain: domain,
        name: matched.sourceName,
        biasStance: matched.biasStance,
        logoUrl: logoUrl,
      );
    }
    if (domain.isNotEmpty && domain == normalizedReader) {
      // Un domaine absent des alternatives servies est le média en cours de
      // lecture (exclu de la liste par construction côté backend).
      return ConsensusSourceRef(
        domain: domain,
        name: (readerSourceName?.isNotEmpty ?? false)
            ? readerSourceName!
            : domain,
        biasStance: readerBias,
        logoUrl: logoUrl,
      );
    }
    return ConsensusSourceRef(domain: domain, name: domain, logoUrl: logoUrl);
  }).toList();
}

// ─── Variante du CTA haut d'article ─────────────────────────────────────────

enum ConsensusCtaVariant { none, solo, statements, pending, bare }

/// Variante du CTA haut d'article, pilotée par les gates backend.
///
/// `null` ou gates `hidden()` (chemin d'erreur) → `none` : rien, pas de
/// skeleton. Une erreur réseau ne doit jamais afficher l'encart solo.
ConsensusCtaVariant resolveConsensusCtaVariant(PerspectivesResponse? response) {
  if (response == null) return ConsensusCtaVariant.none;
  final display = response.display;
  if (display.isSolo) return ConsensusCtaVariant.solo;
  if (!display.hasCta) return ConsensusCtaVariant.none;
  final consensus = response.consensus;
  if (consensus.isAvailable) return ConsensusCtaVariant.statements;
  if (consensus.isPending) return ConsensusCtaVariant.pending;
  return ConsensusCtaVariant.bare;
}

// ─── Widgets ────────────────────────────────────────────────────────────────

// Acier des désaccords (design 6C). Constante locale : promouvoir en token
// `FacteurColors` à la 3ᵉ utilisation.
const Color _kSteel = Color(0xFF5D6D7E);

/// Pile de logos superposés — composition de [SourceDot] (fallback initiale,
/// `FacteurImage` interne, jamais `Image.network`).
class ConsensusLogoStack extends StatelessWidget {
  final List<ConsensusSourceRef> refs;
  final double size;
  final double overlap;
  final int max;

  const ConsensusLogoStack({
    super.key,
    required this.refs,
    this.size = 21,
    this.overlap = 6,
    this.max = 4,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final visible = refs.length > max ? refs.sublist(0, max) : refs;
    if (visible.isEmpty) return const SizedBox.shrink();
    final stackWidth = size + (visible.length - 1) * (size - overlap);

    return SizedBox(
      width: stackWidth,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: SourceDot(
                name: visible[i].name,
                logoUrl: visible[i].logoUrl,
                accent: colors.primary,
                ringColor: colors.surface,
                size: size,
              ),
            ),
        ],
      ),
    );
  }
}

/// Rangée de constat : icône (accord vert / désaccord acier), texte, pile de
/// logos inline 17px et « +N » (masqué à 0).
class ConsensusStatementRow extends StatelessWidget {
  final ConsensusStatement statement;
  final bool isAgreement;
  final List<ConsensusSourceRef> refs;

  const ConsensusStatementRow({
    super.key,
    required this.statement,
    required this.isAgreement,
    required this.refs,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textStyle = GoogleFonts.dmSans(
      fontSize: 13.5,
      height: 1.5,
      color: colors.textPrimary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            isAgreement
                ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                : PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.bold),
            size: 14,
            color: isAgreement ? colors.success : _kSteel,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: textStyle,
              children: [
                TextSpan(text: statement.text),
                if (refs.isNotEmpty) ...[
                  const TextSpan(text: '  '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: ConsensusLogoStack(
                      refs: refs,
                      size: 17,
                      overlap: 5,
                    ),
                  ),
                ],
                if (statement.plusCount > 0)
                  TextSpan(
                    text: ' +${statement.plusCount}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// CTA « Comparer les angles » en haut d'article (design 6C).
///
/// Rien tant que la réponse n'est pas là (`none`) : pas de skeleton, hauteur
/// imprévisible et fetch lancé dès `initState`. Le wrapper
/// `AnimatedSize` + `AnimatedOpacity` assure un fade-in sans à-coup à
/// l'arrivée des données.
class ConsensusCompareCta extends StatelessWidget {
  final PerspectivesResponse? response;
  final String? readerDomain;
  final String? readerSourceName;
  final VoidCallback? onTap;

  const ConsensusCompareCta({
    super.key,
    required this.response,
    this.readerDomain,
    this.readerSourceName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final variant = resolveConsensusCtaVariant(response);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: variant == ConsensusCtaVariant.none ? 0 : 1,
        // Respiration au-dessus de la carte, DANS l'AnimatedSize : hauteur
        // strictement nulle tant qu'il n'y a rien à montrer.
        child: variant == ConsensusCtaVariant.none
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildVariant(context, variant),
              ),
      ),
    );
  }

  Widget _buildVariant(BuildContext context, ConsensusCtaVariant variant) {
    final colors = context.facteurColors;
    final resp = response!;

    if (variant == ConsensusCtaVariant.solo) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(232, 222, 203, 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          consensusSoloText(
            (readerSourceName?.isNotEmpty ?? false)
                ? readerSourceName!
                : 'Ce média',
          ),
          style: GoogleFonts.dmSans(
            fontSize: 12.5,
            height: 1.5,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    // Pile d'entrée : les 4 premiers domaines du corpus servi.
    final corpusRefs = resolveConsensusRefs(
      domains: resp.perspectives
          .map((p) => p.sourceDomain)
          .where((d) => d.isNotEmpty)
          .take(4)
          .toList(),
      perspectives: resp.perspectives,
      readerDomain: readerDomain,
      readerSourceName: readerSourceName,
      readerBias: resp.sourceBiasStance,
    );

    final entryRow = Row(
      children: [
        if (corpusRefs.isNotEmpty) ...[
          ConsensusLogoStack(refs: corpusRefs),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            consensusCompareCtaLabel(resp.coverageCount),
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        Icon(
          PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
          size: 15,
          color: colors.textSecondary,
        ),
      ],
    );

    final children = <Widget>[entryRow];

    if (variant == ConsensusCtaVariant.pending) {
      children.addAll([
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                PhosphorIcons.hourglass(PhosphorIconsStyle.regular),
                size: 14,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                consensusPendingCtaText(resp.coverageCount),
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  height: 1.5,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ]);
    } else if (variant == ConsensusCtaVariant.statements) {
      final cta = resp.consensus.cta;
      final statements = [
        if (cta.agreement != null) (statement: cta.agreement!, agree: true),
        if (cta.disagreement != null)
          (statement: cta.disagreement!, agree: false),
      ];
      if (statements.isNotEmpty) {
        children.addAll([
          const SizedBox(height: 10),
          Container(height: 1, color: colors.border.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
        ]);
        for (var i = 0; i < statements.length; i++) {
          if (i > 0) children.add(const SizedBox(height: 8));
          final entry = statements[i];
          children.add(
            ConsensusStatementRow(
              statement: entry.statement,
              isAgreement: entry.agree,
              refs: resolveConsensusRefs(
                domains: entry.statement.displayDomains,
                perspectives: resp.perspectives,
                readerDomain: readerDomain,
                readerSourceName: readerSourceName,
                readerBias: resp.sourceBiasStance,
              ),
            ),
          );
        }
      }
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(232, 222, 203, 0.80),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
