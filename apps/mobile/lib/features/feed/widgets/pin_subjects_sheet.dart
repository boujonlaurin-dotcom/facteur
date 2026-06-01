import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../custom_topics/widgets/entity_add_sheet.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';

/// Nombre de sujets épinglés en-dessous duquel on incite l'utilisateur à en
/// épingler davantage (carte CTA + sous-titre). Aligné sur la promesse
/// « épingle 3-4 sujets pour une veille de qualité ».
const int kPinSubjectsTarget = 3;

int _pinnedCount(UserInterestsState? interests) {
  final favorites = interests?.favorites ?? const <FavoriteRef>[];
  return favorites.whereType<CustomTopicFavoriteRef>().length;
}

/// Ouvre la modale d'épinglage de sujets précis (custom topics) — distincte des
/// thèmes (qui pilotent la Tournée). Épingler un sujet le transforme en onglet
/// dédié dans Flâner.
Future<void> showPinSubjectsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const _PinSubjectsContent(),
      ),
    ),
  );
}

/// Carte proéminente (sliver) affichée en haut du feed Flâner tant que
/// l'utilisateur a épinglé moins de [kPinSubjectsTarget] sujets. Sinon masquée.
class PinSubjectsBanner extends ConsumerWidget {
  const PinSubjectsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ne rebuild la bannière que lorsque le nombre de sujets épinglés change —
    // pas sur chaque mutation d'intérêt (thèmes, veille, réordonnancement).
    final pinnedCount = ref.watch(
      userInterestsProvider.select((value) {
        final interests = value.valueOrNull;
        return interests == null ? null : _pinnedCount(interests);
      }),
    );
    if (pinnedCount == null || pinnedCount >= kPinSubjectsTarget) {
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Épingle tes sujets de veille',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Épingle 3-4 sujets pour une veille de qualité — '
                        'ils deviennent tes onglets ici.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.35,
                            ),
                      ),
                    ],
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

class _PinSubjectsContent extends ConsumerWidget {
  const _PinSubjectsContent();

  Future<void> _setState(
    WidgetRef ref,
    String topicId,
    InterestState state,
  ) async {
    try {
      await ref.read(userInterestsProvider.notifier).setInterestState(
            CustomTopicFavoriteRef(id: topicId),
            state,
          );
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final topics = interests?.customTopics ?? const <CustomTopicInterest>[];

    final pinned =
        topics.where((t) => t.state == InterestState.favorite).toList();
    final pinnable = topics
        .where((t) => t.state != InterestState.favorite)
        .toList()
      ..sort((a, b) =>
          a.topicName.toLowerCase().compareTo(b.topicName.toLowerCase()));

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),
                Text(
                  'Épingler des sujets',
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tes sujets précis deviennent des onglets dans Flâner. '
                  'Les thèmes, eux, pilotent ta Tournée du jour.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // Sujets déjà épinglés → tap pour dé-épingler.
                if (pinned.isNotEmpty) ...[
                  _SectionLabel(label: 'SUJETS ÉPINGLÉS', colors: colors),
                  const SizedBox(height: 8),
                  for (final t in pinned)
                    _SubjectRow(
                      key: ValueKey('pinned_${t.id}'),
                      label: t.topicName,
                      pinned: true,
                      colors: colors,
                      onTap: () =>
                          _setState(ref, t.id, InterestState.unfollowed),
                    ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Sujets suivis non épinglés → 1 tap pour épingler.
                if (pinnable.isNotEmpty) ...[
                  _SectionLabel(
                    label: 'ÉPINGLER UN SUJET SUIVI',
                    colors: colors,
                  ),
                  const SizedBox(height: 8),
                  for (final t in pinnable)
                    _SubjectRow(
                      key: ValueKey('pinnable_${t.id}'),
                      label: t.topicName,
                      pinned: false,
                      colors: colors,
                      onTap: () => _setState(ref, t.id, InterestState.favorite),
                    ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                if (pinned.isEmpty && pinnable.isEmpty) ...[
                  Text(
                    'Aucun sujet pour le moment. Crée ton premier sujet '
                    'à suivre ci-dessous.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => EntityAddSheet.show(
                      context,
                      pinOnFollow: true,
                    ),
                    icon: Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      size: 16,
                      color: colors.primary,
                    ),
                    label: Text(
                      'Créer un sujet',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: colors.primary.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final FacteurColors colors;

  const _SectionLabel({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final String label;
  final bool pinned;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _SubjectRow({
    super.key,
    required this.label,
    required this.pinned,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: pinned
                  ? colors.primary.withValues(alpha: 0.06)
                  : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: pinned
                    ? colors.primary.withValues(alpha: 0.3)
                    : colors.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  pinned
                      ? PhosphorIcons.pushPin(PhosphorIconsStyle.fill)
                      : PhosphorIcons.plus(PhosphorIconsStyle.bold),
                  size: 16,
                  color: pinned ? colors.primary : colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
