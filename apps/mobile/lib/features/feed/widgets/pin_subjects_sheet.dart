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
import '../../veille/providers/veille_themes_provider.dart';

/// Nombre de sujets épinglés en-dessous duquel on incite l'utilisateur à en
/// épingler davantage (carte CTA + sous-titre). Aligné sur la promesse
/// « 3-4 sujets suffisent ».
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
                        'Épingle tes sujets',
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
                        '3-4 sujets suffisent — ils deviennent tes onglets '
                        'dans Flâner.',
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

/// Emoji du thème parent d'un sujet (sert d'icône de thématique). Fallback
/// 📰 pour un slug hors des 9 thèmes Facteur (cf. [kVeilleFacteurThemes]).
String _themeEmoji(String slugParent) {
  for (final t in kVeilleFacteurThemes) {
    if (t.slug == slugParent) return t.emoji;
  }
  return '📰';
}

/// Normalise une chaîne pour la recherche : minuscules + accents retirés.
String _normalize(String input) {
  final lower = input.toLowerCase();
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final idx = from.indexOf(char);
    buffer.write(idx == -1 ? char : to[idx]);
  }
  return buffer.toString();
}

class _PinSubjectsContent extends ConsumerStatefulWidget {
  const _PinSubjectsContent();

  @override
  ConsumerState<_PinSubjectsContent> createState() =>
      _PinSubjectsContentState();
}

class _PinSubjectsContentState extends ConsumerState<_PinSubjectsContent> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setState(String topicId, InterestState state) async {
    try {
      await ref.read(userInterestsProvider.notifier).setInterestState(
            CustomTopicFavoriteRef(id: topicId),
            state,
          );
    } catch (e) {
      NotificationService.showError('Erreur : $e');
    }
  }

  bool _matches(CustomTopicInterest t, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return _normalize(t.topicName).contains(normalizedQuery);
  }

  /// Groupe les sujets par thème parent, dans l'ordre canonique des thèmes
  /// Facteur (les thèmes inconnus en dernier), sujets triés alpha dans chaque
  /// groupe.
  List<MapEntry<String, List<CustomTopicInterest>>> _groupByTheme(
    List<CustomTopicInterest> subjects,
  ) {
    final groups = <String, List<CustomTopicInterest>>{};
    for (final t in subjects) {
      groups.putIfAbsent(t.slugParent, () => []).add(t);
    }
    for (final list in groups.values) {
      list.sort((a, b) =>
          a.topicName.toLowerCase().compareTo(b.topicName.toLowerCase()));
    }
    final order = {
      for (var i = 0; i < kVeilleFacteurThemes.length; i++)
        kVeilleFacteurThemes[i].slug: i,
    };
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final ia = order[a.key] ?? kVeilleFacteurThemes.length;
        final ib = order[b.key] ?? kVeilleFacteurThemes.length;
        if (ia != ib) return ia.compareTo(ib);
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final topics = interests?.customTopics ?? const <CustomTopicInterest>[];

    final normalizedQuery = _normalize(_query.trim());
    final hasQuery = normalizedQuery.isNotEmpty;

    final pinned = topics
        .where((t) =>
            t.state == InterestState.favorite && _matches(t, normalizedQuery))
        .toList()
      ..sort((a, b) =>
          a.topicName.toLowerCase().compareTo(b.topicName.toLowerCase()));
    final pinnable = topics
        .where((t) =>
            t.state != InterestState.favorite && _matches(t, normalizedQuery))
        .toList();
    final pinnableGroups = _groupByTheme(pinnable);

    final hasAnyTopic = topics.isNotEmpty;
    final noMatch = pinned.isEmpty && pinnable.isEmpty;

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

                // Barre de recherche — filtre les sujets ; fallback « créer »
                // quand aucun ne matche.
                if (hasAnyTopic)
                  _SearchField(
                    controller: _searchController,
                    colors: colors,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () => setState(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
                if (hasAnyTopic)
                  const SizedBox(height: FacteurSpacing.space4),

                // Sujets déjà épinglés → tap pour dé-épingler.
                if (pinned.isNotEmpty) ...[
                  _SectionLabel(label: 'SUJETS ÉPINGLÉS', colors: colors),
                  const SizedBox(height: 8),
                  for (final t in pinned)
                    _SubjectRow(
                      key: ValueKey('pinned_${t.id}'),
                      label: t.topicName,
                      emoji: _themeEmoji(t.slugParent),
                      pinned: true,
                      colors: colors,
                      onTap: () => _setState(t.id, InterestState.unfollowed),
                    ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Sujets suivis non épinglés → groupés par thématique,
                // 1 tap pour épingler.
                if (pinnable.isNotEmpty) ...[
                  _SectionLabel(
                    label: 'ÉPINGLER UN SUJET SUIVI',
                    colors: colors,
                  ),
                  const SizedBox(height: 8),
                  for (final group in pinnableGroups) ...[
                    _ThemeGroupHeader(
                      emoji: _themeEmoji(group.key),
                      label: veilleThemeLabelForSlug(group.key),
                      colors: colors,
                    ),
                    const SizedBox(height: 6),
                    for (final t in group.value)
                      _SubjectRow(
                        key: ValueKey('pinnable_${t.id}'),
                        label: t.topicName,
                        emoji: _themeEmoji(t.slugParent),
                        pinned: false,
                        colors: colors,
                        onTap: () => _setState(t.id, InterestState.favorite),
                      ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: FacteurSpacing.space2),
                ],

                // Aucun sujet ne matche la recherche → proposer de le créer.
                if (hasQuery && noMatch) ...[
                  _CreateSubjectTile(
                    query: _query.trim(),
                    colors: colors,
                    onTap: () => EntityAddSheet.show(
                      context,
                      pinOnFollow: true,
                      initialQuery: _query.trim(),
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                ],

                // Aucun sujet du tout (et pas de recherche en cours).
                if (!hasQuery && !hasAnyTopic) ...[
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FacteurColors colors;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Rechercher un sujet…',
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
        prefixIcon: Icon(
          PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
          size: 18,
          color: colors.textTertiary,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  PhosphorIcons.x(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.textTertiary,
                ),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          borderSide: BorderSide(color: colors.primary),
        ),
      ),
    );
  }
}

class _ThemeGroupHeader extends StatelessWidget {
  final String emoji;
  final String label;
  final FacteurColors colors;

  const _ThemeGroupHeader({
    required this.emoji,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 2),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _CreateSubjectTile extends StatelessWidget {
  final String query;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _CreateSubjectTile({
    required this.query,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Créer le sujet ',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                    ),
                    children: [
                      TextSpan(
                        text: '« $query »',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
  final String emoji;
  final bool pinned;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _SubjectRow({
    super.key,
    required this.label,
    required this.emoji,
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
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 10),
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
