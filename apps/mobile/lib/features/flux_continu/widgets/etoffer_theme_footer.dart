import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/notification_service.dart';
import '../../my_interests/models/user_interests_state.dart' show InterestState;
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/models/theme_suggestions_model.dart';
import '../../sources/providers/sources_providers.dart' show etofferThemeProvider;
import '../../sources/widgets/source_logo_avatar.dart';

/// Footer « Étoffer [thème] » — vecteur contextuel de **sources de qualité** au
/// pied d'une section thématique de la Tournée.
///
/// Rend des sources **poussées** (Tiers 1 & 2, servies par
/// `GET /sources/suggest-for-theme/{slug}`) avec une UI **graduée** selon notre
/// niveau de contrôle éditorial :
/// - Tier 1 « Recommandé par Facteur » (pépite curée) : branding fort + raison.
/// - Tier 2 « Source de qualité » (catalogue évalué) : cadre neutre + badge
///   d'évaluation visible (biais + fiabilité).
/// Plus une entrée « Chercher une source [thème] » (Tier 3, découverte user)
/// dont Facteur ne se porte pas garant — déléguée à [onSearch].
///
/// Visuellement calqué sur `_FavoriteEmptyState` (carte beige `0xFFE6E1D6`).
class EtofferThemeFooter extends ConsumerStatefulWidget {
  /// Slug du macro-thème (jamais un sujet custom — le câblage le garantit).
  final String slug;

  /// Libellé lisible du thème (« Tech », « Politique »…), pour les CTA.
  final String label;

  /// Message d'accroche optionnel, rendu au-dessus des sources. Renseigné pour
  /// le cas **thème vide** (« Rien de neuf récemment sur Tech. »).
  final String? headline;

  /// `true` ⇒ footer **déplié** d'emblée (thème vide / maigre, où il porte la
  /// valeur). `false` ⇒ footer **replié** (thème riche) : un simple bouton
  /// « Étoffer [thème] » qui ne déclenche l'appel réseau qu'au tap.
  final bool initiallyExpanded;

  /// Ouvre la recherche de sources (Tier 3). Typiquement le même callback que
  /// `onAddSources` (route d'ajout de source).
  final VoidCallback? onSearch;

  const EtofferThemeFooter({
    super.key,
    required this.slug,
    required this.label,
    this.headline,
    this.initiallyExpanded = false,
    this.onSearch,
  });

  @override
  ConsumerState<EtofferThemeFooter> createState() => _EtofferThemeFooterState();
}

class _EtofferThemeFooterState extends ConsumerState<EtofferThemeFooter> {
  // On affiche au plus 2 sources (footer discret), mais le backend en renvoie
  // jusqu'à 3 (SUGGEST_FOR_THEME_CAP) : ce différentiel sert de tampon — quand
  // l'utilisateur en suit une, la 3ᵉ prend sa place sans refetch (cf. _followed).
  static const _maxPushed = 2;

  static const _borderColor = Color(0xFFE6E1D6);
  static const _textColor = Color(0xFF5D5B5A);
  static const _ctaColor = Color(0xFF2C3E50);
  static const _facteurAccent = Color(0xFFB0470A);

  /// Ids suivis pendant cette session → masqués localement (la prochaine
  /// requête les exclura nativement, sans flicker de refetch).
  final Set<String> _followed = {};

  /// Ids dont le suivi est en cours (spinner + tap ignoré).
  final Set<String> _following = {};

  @override
  Widget build(BuildContext context) {
    // Cas A (thème riche, replié) : un simple bouton qui mène droit au
    // catalogue filtré — plus de dépli in-place des suggestions.
    if (!widget.initiallyExpanded) return _collapsedButton();

    final async = ref.watch(etofferThemeProvider(widget.slug));
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.headline != null) ...[
            Text(widget.headline!, style: _headlineStyle),
            const SizedBox(height: 12),
          ],
          async.when(
            loading: () => _loadingRow(),
            error: (_, __) => const SizedBox.shrink(),
            data: _suggestionsColumn,
          ),
          _searchEntry(),
        ],
      ),
    );
  }

  // --- Sous-vues -------------------------------------------------------------

  Widget _collapsedButton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: widget.onSearch,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
        label: Text('Plus de sources (${widget.label})'),
        style: _discreetCtaStyle,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: EdgeInsets.fromLTRB(16, widget.headline == null ? 12 : 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: child,
    );
  }

  Widget _loadingRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Recherche de sources…',
            style: TextStyle(fontSize: 13, color: _textColor),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsColumn(ThemeSuggestions data) {
    final visible = data.suggestions
        .where((s) => !_followed.contains(s.source.id))
        .take(_maxPushed)
        .toList();
    if (visible.isEmpty) {
      // Cas C — aucune source curée/évaluée : pas de phrase descriptive, il ne
      // reste que le lien discret « Chercher une source X » (le `_searchEntry`
      // rendu juste après, qui mène désormais au catalogue filtré).
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final s in visible) _suggestionRow(s)],
    );
  }

  Widget _suggestionRow(ThemeSuggestion suggestion) {
    final source = suggestion.source;
    final isFacteurPick = suggestion.tier == ThemeSuggestionTier.facteurPick;
    final following = _following.contains(source.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SourceLogoAvatar(source: source, size: 34, radius: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B2A28),
                  ),
                ),
                const SizedBox(height: 4),
                if (isFacteurPick)
                  _facteurPickLine(source)
                else
                  _qualityLine(source),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _followButton(source, following),
        ],
      ),
    );
  }

  /// Tier 1 — branding assumé : pastille « Recommandé par Facteur » + raison
  /// (ou « Choisi par {recommendedBy} » à défaut de raison).
  Widget _facteurPickLine(Source source) {
    final reason = source.recommendationReason?.trim();
    final by = source.recommendedBy?.trim();
    final caption = (reason != null && reason.isNotEmpty)
        ? reason
        : (by != null && by.isNotEmpty)
            ? 'Choisi par $by'
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Pill(
          icon: Icons.verified_rounded,
          label: 'Recommandé par Facteur',
          color: _facteurAccent,
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              height: 1.3,
              fontStyle: FontStyle.italic,
              color: _textColor,
            ),
          ),
        ],
      ],
    );
  }

  /// Tier 2 — cadre neutre + badge d'évaluation visible (biais + fiabilité) :
  /// Facteur reste transparent, sans se porter garant par son branding.
  Widget _qualityLine(Source source) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Source de qualité sur ${widget.label}',
          style: const TextStyle(fontSize: 12, color: _textColor),
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _Dot(
              color: source.getBiasColor(),
              label: source.getBiasLabel(),
            ),
            _Dot(
              color: source.getReliabilityColor(),
              label: 'Fiabilité ${source.getReliabilityLabel().toLowerCase()}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _followButton(Source source, bool following) {
    return SizedBox(
      height: 32,
      child: FilledButton.tonalIcon(
        onPressed: following ? null : () => _follow(source),
        icon: following
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_rounded, size: 16),
        label: const Text('Suivre'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFEFEAE0),
          foregroundColor: _ctaColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _searchEntry() {
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: widget.onSearch,
        icon: const Icon(Icons.search_rounded, size: 15),
        label: Text('Chercher une source ${widget.label}'),
        style: _discreetCtaStyle,
      ),
    );
  }

  /// Style commun aux CTA texte de pied de section : discret (gris, petit,
  /// poids moyen) et centré, pour ne pas concurrencer les suggestions.
  static final _discreetCtaStyle = TextButton.styleFrom(
    foregroundColor: _textColor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 32),
    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
  );

  // --- Action ----------------------------------------------------------------

  Future<void> _follow(Source source) async {
    setState(() => _following.add(source.id));
    try {
      // « Suivre » (et non « favori ») : ajout léger, sans plafond de favoris.
      // L'état `followed` suffit à faire remonter la source dans le feed du
      // thème (le backend lit le même axe de suivi).
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(source.id, InterestState.followed);
      if (!mounted) return;
      setState(() {
        _following.remove(source.id);
        _followed.add(source.id);
      });
      NotificationService.showSuccess(
        '${source.name} ajoutée. Ses articles nourriront ${widget.label}.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _following.remove(source.id));
      NotificationService.showError('Impossible d\'ajouter cette source.');
    }
  }

  // --- Styles partagés -------------------------------------------------------

  static const _headlineStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
    color: _textColor,
  );
}

/// Pastille tier (Tier 1) — icône + label sur fond teinté.
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge d'évaluation (Tier 2) — pastille de couleur + label (biais/fiabilité).
class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF5D5B5A)),
        ),
      ],
    );
  }
}
