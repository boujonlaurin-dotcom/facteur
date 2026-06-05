import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../flux_continu/widgets/manage_favorites_sheet.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';

/// Nombre d'éléments épinglés (sujets + sources) en-dessous duquel on incite
/// l'utilisateur à en épingler davantage (carte CTA). Aligné sur la promesse
/// « 3-4 suffisent ».
const int kPinSubjectsTarget = 3;

int _pinnedTopicCount(UserInterestsState? interests) {
  final favorites = interests?.favorites ?? const <FavoriteRef>[];
  return favorites.whereType<CustomTopicFavoriteRef>().length;
}

int _pinnedSourceCount(UserSourcesState? sources) {
  return sources?.favorites.length ?? 0;
}

/// Shim historique (Story 10.2) — l'épinglage ouvre désormais la sheet unifiée
/// [showManageFavoritesSheet] côté Flâner. Conservé pour ne pas toucher les
/// appels existants (banner, feed_filter_bar).
Future<void> showPinSubjectsSheet(BuildContext context) {
  return showManageFavoritesSheet(context, entry: ManageFavoritesEntry.flaner);
}

/// Carte proéminente (sliver) affichée en haut du feed Flâner tant que
/// l'utilisateur a épinglé moins de [kPinSubjectsTarget] éléments. Sinon masquée.
class PinSubjectsBanner extends ConsumerWidget {
  const PinSubjectsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ne rebuild la bannière que lorsque le nombre d'éléments épinglés change.
    final pinnedTopics = ref.watch(
      userInterestsProvider.select((value) {
        final interests = value.valueOrNull;
        return interests == null ? null : _pinnedTopicCount(interests);
      }),
    );
    final pinnedSources = ref.watch(
      userSourcesStateProvider.select(
        (value) => _pinnedSourceCount(value.valueOrNull),
      ),
    );
    if (pinnedTopics == null) {
      return const SizedBox.shrink();
    }
    final pinnedCount = pinnedTopics + pinnedSources;
    if (pinnedCount >= kPinSubjectsTarget) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          onTap: () {
            HapticFeedback.mediumImpact();
            showPinSubjectsSheet(context);
          },
          child: Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border:
                  Border.all(color: colors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
                  size: 22,
                  color: colors.primary,
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Text(
                    'Épinglez des sources ou sujets précis',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                Icon(
                  PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                  size: 18,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
