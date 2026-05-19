import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../utils/theme_color_mapping.dart';

/// Bottom sheet listing the user's declared favorite interests (Thèmes +
/// Sujets, up to 3). Reorder is decorative only — the real management UI
/// lives in [RoutePaths.myInterests], which the primary CTA opens.
///
/// Reads directly from [userInterestsProvider] so the list reflects the
/// user's canonical favorites instead of being inferred from whatever theme
/// sections the Flux Continu happened to fetch.
Future<void> showMyInterestsBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    isScrollControlled: true,
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: const _MyInterestsContent(),
      ),
    ),
  );
}

class _MyInterestsContent extends ConsumerWidget {
  const _MyInterestsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final interests = ref.watch(userInterestsProvider).valueOrNull;
    final favorites = interests?.favorites ?? const <FavoriteRef>[];
    final rows = <_FavoriteRow>[
      for (final fav in favorites)
        _FavoriteRow.fromRef(ref: fav, interests: interests),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        'Mes intérêts',
                        style: GoogleFonts.fraunces(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${rows.length} FAVORIS',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: colors.textStamp,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Les intérêts qui pilotent ta tournée du jour.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < rows.length; i++) ...[
                  _ThemeRow(
                    order: i + 1,
                    row: rows[i],
                    colors: colors,
                  ),
                  if (i < rows.length - 1) const SizedBox(height: 8),
                ],
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Aucun favori pour le moment.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                Container(
                  height: 1,
                  color: colors.border.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 18),
                _PrimaryManageCta(
                  colors: colors,
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RoutePaths.myInterests);
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'En suivre d\'autres, en masquer, ajuster les sources…',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: colors.textTertiary,
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    textStyle: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// View-model bridging a [FavoriteRef] to the visuals expected by the row
/// renderer. Resolves theme labels from the canonical visual map; for custom
/// topics, falls back to the topic name from the interests state and the
/// parent macro-theme accent.
class _FavoriteRow {
  final String label;
  final Color accent;

  const _FavoriteRow({required this.label, required this.accent});

  factory _FavoriteRow.fromRef({
    required FavoriteRef ref,
    required UserInterestsState? interests,
  }) {
    return switch (ref) {
      ThemeFavoriteRef(:final slug) => _FavoriteRow(
          label: visualFor(slug).label,
          accent: visualFor(slug).accent,
        ),
      CustomTopicFavoriteRef(:final id) => () {
          final topic = interests?.customTopics
              .where((t) => t.id == id)
              .firstOrNull;
          return _FavoriteRow(
            label: topic?.topicName ?? 'Sujet personnalisé',
            accent: topic == null
                ? visualFor('').accent
                : visualFor(topic.slugParent).accent,
          );
        }(),
      // Veille : accent dédié sectionVeille1 + label "Ma veille" (Story 23.2 PR-4).
      // Le label précis (theme_label de la VeilleConfig) sera résolu en
      // commit 5 via veilleActiveConfigProvider.
      VeilleFavoriteRef() => const _FavoriteRow(
          label: 'Ma veille',
          accent: Color(0xFF2C3E50),
        ),
    };
  }
}

class _ThemeRow extends StatelessWidget {
  final int order;
  final _FavoriteRow row;
  final FacteurColors colors;

  const _ThemeRow({
    required this.order,
    required this.row,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final orderLabel = order.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              orderLabel,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colors.textTertiary,
              ),
            ),
          ),
          // Decorative drag handle — the actual reorder UI lives in
          // [MyInterestsScreen], reachable via the primary CTA below.
          Icon(
            PhosphorIcons.dotsSixVertical(),
            size: 16,
            color: colors.textTertiary,
          ),
          const SizedBox(width: 10),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: row.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              PhosphorIcons.star(PhosphorIconsStyle.fill),
              size: 13,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryManageCta extends StatelessWidget {
  final FacteurColors colors;
  final VoidCallback onTap;

  const _PrimaryManageCta({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.slidersHorizontal(),
                size: 16,
                color: colors.surface,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Gérer mes intérêts',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.surface,
                  ),
                ),
              ),
              Icon(
                PhosphorIcons.arrowRight(),
                size: 14,
                color: colors.surface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
