import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/alert_item.dart';
import '../models/alert_suggestion.dart';
import '../providers/alerts_provider.dart';
import 'alert_activation_sheet.dart';

/// Le bloc de suggestions de « Mes alertes » (story 30.6).
///
/// Il répond au reproche PO « on n'a aucune proposition d'ajout de sources ni
/// de thème (alors qu'on a bien des stats sur ce qui est le + utilisé) ».
///
/// **Discret par construction.** Le PO a déjà reproché la surcharge de cette
/// zone : le bloc ne porte donc pas de carte par ligne (l'inventaire en a
/// une), pas de logo hors gabarit, pas de second titre d'écran. Une ligne de
/// suggestion fait ~64 px contre ~140 px pour une carte de l'inventaire, et
/// tout tient dans un seul conteneur avec des filets de séparation.
///
/// Il n'affiche rien du tout quand il n'a rien à dire : plafond atteint (c'est
/// l'en-tête du lot C qui porte la phrase, on ne la duplique pas), liste vide,
/// chargement, ou erreur. Un bloc vide dans un écran de réglages est du bruit.
class AlertSuggestionsList extends ConsumerStatefulWidget {
  const AlertSuggestionsList({super.key});

  @override
  ConsumerState<AlertSuggestionsList> createState() =>
      _AlertSuggestionsListState();
}

class _AlertSuggestionsListState extends ConsumerState<AlertSuggestionsList> {
  /// L'événement d'affichage part une seule fois par montage : sinon chaque
  /// rebuild (acceptation, refus, refresh) le rejouerait et le taux de
  /// conversion serait faux par construction.
  bool _shownTracked = false;

  /// Cible en cours de pose : une seule à la fois.
  String? _busyId;

  void _trackShown(List<AlertSuggestion> suggestions) {
    if (_shownTracked || suggestions.isEmpty) return;
    _shownTracked = true;
    unawaited(
      ref.read(analyticsServiceProvider).trackAlertSuggestionsShown(
            count: suggestions.length,
            signals: suggestions.map((s) => s.signal).toList(),
          ),
    );
  }

  /// Pose la cloche de [suggestion].
  ///
  /// `_busyId` est relâché dans un `finally` **unique** : sur le chemin
  /// nominal aussi. Le relâcher seulement dans les branches d'erreur laissait
  /// le verrou posé après une acceptation réussie, et comme il gouverne les
  /// deux gestes de **toutes** les lignes, le bloc entier devenait inerte
  /// jusqu'à ce qu'on quitte l'écran.
  Future<void> _accept(AlertSuggestion suggestion, int position) async {
    setState(() => _busyId = suggestion.targetId);
    try {
      // Helper extrait par le lot C : pas de seconde modale de permission ici.
      if (!await ensureAlertPushPermission(context, ref)) return;
      if (!mounted) return;

      final notifier = ref.read(alertsProvider.notifier);
      // Règle 30.3 : le mode filtré est déjà coché sur une cible bruyante,
      // exactement comme sur la fiche source et dans le sélecteur du lot C.
      final filtered = suggestion.prefillFiltered;
      if (suggestion.isTopic) {
        await notifier.setTopicAlert(
          suggestion.targetId,
          true,
          filtered: filtered,
        );
      } else {
        await notifier.setAlert(suggestion.targetId, true, filtered: filtered);
      }
      unawaited(
        ref.read(analyticsServiceProvider).trackAlertSuggestionAccepted(
              kind: suggestion.isTopic ? 'topic' : 'source',
              targetId: suggestion.targetId,
              signal: suggestion.signal,
              position: position,
              filtered: filtered,
            ),
      );
      ref.read(alertSuggestionsProvider.notifier).forget(suggestion.targetId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            filtered
                ? 'Alerte posée sur ${suggestion.targetName}. '
                    'Seulement les plus marquantes, 1 max par jour.'
                : 'Alerte posée sur ${suggestion.targetName}. '
                    '${suggestion.cadencePhrase}.',
          ),
        ),
      );
    } on AlertCapReachedException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tu as déjà ${e.cap} alertes. Désactives-en une pour en poser '
            'une autre.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de poser cette alerte.')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _dismiss(AlertSuggestion suggestion, int position) async {
    unawaited(
      ref.read(analyticsServiceProvider).trackAlertSuggestionDismissed(
            kind: suggestion.isTopic ? 'topic' : 'source',
            targetId: suggestion.targetId,
            signal: suggestion.signal,
            position: position,
          ),
    );
    try {
      await ref.read(alertSuggestionsProvider.notifier).dismiss(suggestion);
    } catch (_) {
      // Le retrait local a déjà eu lieu : un échec réseau ne doit pas faire
      // réapparaître la ligne dans la seconde. Elle reviendra au prochain
      // chargement, ce qui est le comportement le moins surprenant.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(alertSuggestionsProvider).valueOrNull;
    final suggestions = state?.suggestions ?? const <AlertSuggestion>[];
    if (suggestions.isEmpty) return const SizedBox.shrink();

    _trackShown(suggestions);

    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: FacteurSpacing.space1,
              bottom: FacteurSpacing.space2,
            ),
            child: Text(
              'Peut-être aussi',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.surfaceElevated),
            ),
            child: Column(
              children: [
                for (final (i, suggestion) in suggestions.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.surfaceElevated,
                    ),
                  _SuggestionRow(
                    suggestion: suggestion,
                    busy: _busyId == suggestion.targetId,
                    onAccept: _busyId != null
                        ? null
                        : () => _accept(suggestion, i),
                    onDismiss: _busyId != null
                        ? null
                        : () => _dismiss(suggestion, i),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une ligne : qui, pourquoi, à quel rythme, et deux gestes.
///
/// La raison est la seule chose qui distingue une suggestion utile d'une
/// suggestion plausible, donc elle est rendue en toutes lettres et non
/// résumée en icône.
class _SuggestionRow extends StatelessWidget {
  final AlertSuggestion suggestion;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  const _SuggestionRow({
    required this.suggestion,
    required this.busy,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Un sujet n'a pas de logo : la trame reste alignée grâce au même
          // gabarit de 28 px, un cran sous celui de l'inventaire (32 px).
          if (suggestion.isTopic)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                PhosphorIcons.hash(PhosphorIconsStyle.regular),
                size: 16,
                color: colors.primary,
              ),
            )
          else
            SourceLogoAvatar.fromUrl(
              logoUrl: suggestion.targetLogoUrl,
              name: suggestion.targetName,
              size: 28,
              radius: 8,
            ),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.targetName,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  suggestion.reason,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (suggestion.cadencePhrase.isNotEmpty)
                  Text(
                    suggestion.prefillFiltered
                        ? '${suggestion.cadencePhrase}. '
                            'Le mode filtré sera activé.'
                        : suggestion.cadencePhrase,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(FacteurSpacing.space2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Ne plus proposer',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              icon: Icon(
                PhosphorIcons.x(PhosphorIconsStyle.regular),
                size: 16,
                color: colors.textTertiary,
              ),
            ),
            IconButton(
              onPressed: onAccept,
              tooltip: 'Poser l\'alerte',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              icon: Icon(
                PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                size: 18,
                color: colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
