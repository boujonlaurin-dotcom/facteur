import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/feed_provider.dart' show FeedFilterKind;

/// Empty state affiché quand un filtre (mot-clé, thème, topic, entity, source)
/// ne retourne aucun article. Propose des CTAs contextuels pour
/// réduire la frustration et guider l'utilisateur.
///
/// Story 30.1 — la variante mot-clé est la plus riche : une recherche
/// bredouille est le moment où l'utilisateur a le plus besoin d'une porte de
/// sortie (élargir · ajouter la source · suivre le sujet), plutôt que d'un
/// écran blanc comme c'était le cas jusqu'ici.
class EmptyFilterState extends StatelessWidget {
  /// Nature du filtre qui n'a rien ramené. Reprise telle quelle de
  /// [FeedFilterSelection.activeKind] — les dimensions étant exclusives, un
  /// seul champ vaut mieux que quatre booléens dont 11 combinaisons sur 16
  /// seraient invalides.
  final FeedFilterKind kind;

  final String? filterName;

  /// Recherche déjà élargie aux sources non suivies — masque le CTA « élargir ».
  final bool alreadyBroadened;

  final VoidCallback onClearFilter;

  /// Variante mot-clé — relancer la recherche sur toutes les sources.
  final VoidCallback? onBroaden;

  /// Variante mot-clé — chercher une source portant ce nom (recherche
  /// intelligente pré-remplie).
  final VoidCallback? onSearchSource;

  /// Variante mot-clé — suivre la requête comme sujet.
  final VoidCallback? onFollowTopic;

  const EmptyFilterState({
    super.key,
    required this.kind,
    required this.onClearFilter,
    this.filterName,
    this.alreadyBroadened = false,
    this.onBroaden,
    this.onSearchSource,
    this.onFollowTopic,
  }) : assert(
          kind != FeedFilterKind.keyword || filterName != null,
          'Une recherche mot-clé porte toujours son libellé.',
        );

  bool get _isKeyword => kind == FeedFilterKind.keyword;

  String get _emoji {
    switch (kind) {
      case FeedFilterKind.keyword:
      case FeedFilterKind.entity:
        return '🔍';
      case FeedFilterKind.source:
        return '📰';
      case FeedFilterKind.theme:
      case FeedFilterKind.topic:
        return '📭';
    }
  }

  String get _title =>
      filterName != null ? 'Rien sur « $filterName »' : 'Aucun article trouvé';

  String get _subtitle {
    switch (kind) {
      case FeedFilterKind.keyword:
        return alreadyBroadened
            ? 'Aucun article récent ne porte ce mot dans son titre,\nmême hors de tes sources.'
            : 'Aucun article récent de tes sources ne porte ce mot\ndans son titre.';
      case FeedFilterKind.entity:
        return 'Aucun article récent ne mentionne ce sujet.\nDe nouveaux contenus peuvent arriver bientôt.';
      case FeedFilterKind.source:
        return 'Aucun article récent de cette source.';
      case FeedFilterKind.theme:
      case FeedFilterKind.topic:
        return 'Aucun article récent ne correspond à ce filtre.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Ordre des rattrapages : du moins engageant (élargir la même recherche) au
    // plus engageant (ajouter une source), puis la sortie neutre.
    final secondary = <Widget>[
      if (_isKeyword && !alreadyBroadened && onBroaden != null)
        _SecondaryCta(
          colors: colors,
          icon: PhosphorIcons.globeHemisphereWest(PhosphorIconsStyle.regular),
          label: 'Élargir à toutes les sources',
          onPressed: onBroaden!,
        ),
      if (_isKeyword && onSearchSource != null)
        _SecondaryCta(
          colors: colors,
          icon: PhosphorIcons.plusCircle(PhosphorIconsStyle.regular),
          label: 'Ajouter « $filterName » comme source',
          onPressed: onSearchSource!,
        ),
      if (_isKeyword && onFollowTopic != null)
        _SecondaryCta(
          colors: colors,
          icon: PhosphorIcons.bellSimpleRinging(PhosphorIconsStyle.regular),
          label: 'Suivre « $filterName » comme sujet',
          onPressed: onFollowTopic!,
        ),
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_emoji, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              _title,
              style: textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              _subtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space6),

            // Les rattrapages passent devant la sortie neutre : sur une
            // recherche bredouille, « revenir au feed » n'est pas ce que
            // l'utilisateur veut en premier.
            for (final cta in secondary) ...[
              cta,
              const SizedBox(height: FacteurSpacing.space3),
            ],
            _ClearFilterCta(colors: colors, onPressed: onClearFilter),
          ],
        ),
      ),
    );
  }
}

class _ClearFilterCta extends StatelessWidget {
  final FacteurColors colors;
  final VoidCallback onPressed;

  const _ClearFilterCta({required this.colors, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold), size: 18),
        label: const Text('Revenir au feed'),
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
          ),
        ),
      ),
    );
  }
}

class _SecondaryCta extends StatelessWidget {
  final FacteurColors colors;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SecondaryCta({
    required this.colors,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, textAlign: TextAlign.center),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textSecondary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
          ),
        ),
      ),
    );
  }
}
