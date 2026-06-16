import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/serein_colors.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../app_update/providers/app_update_provider.dart';
import '../../app_update/widgets/update_bottom_sheet.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../lettres/models/facteur_grade.dart';
import '../../lettres/providers/letters_provider.dart';
import '../../lettres/widgets/ring_avatar.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../veille/providers/veille_active_config_provider.dart';
import '../../veille/providers/veille_repository_provider.dart';
import '../providers/user_profile_provider.dart';
import 'feedback_modal.dart';

/// Bottom sheet hosting the new global "Réglages".
///
/// Replaces the previous full-screen settings tab. Layout from mock v23:
/// profile block → Mode Serein switch → content shortcuts → feedback CTA.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space6,
                  FacteurSpacing.space4,
                  FacteurSpacing.space6,
                  FacteurSpacing.space2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Réglages',
                    style: FacteurTypography.serifTitle(
                      colors.textPrimary,
                    ).copyWith(fontSize: 28, height: 1.15),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    FacteurSpacing.space4,
                    FacteurSpacing.space2,
                    FacteurSpacing.space4,
                    FacteurSpacing.space8,
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileBlock(),
                      SizedBox(height: FacteurSpacing.space4),
                      _UpdateAvailableTile(),
                      _SereinSwitchTile(),
                      SizedBox(height: FacteurSpacing.space4),
                      _ContentShortcuts(),
                      SizedBox(height: FacteurSpacing.space4),
                      _FeedbackTile(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileBlock extends ConsumerWidget {
  const _ProfileBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final displayName = ref.watch(userProfileProvider).displayName?.trim();
    final serein = ref.watch(sereinToggleProvider.select((s) => s.enabled));
    final lettersState = ref.watch(lettersProvider).valueOrNull;
    final grade = lettersState?.grade;
    final shown = (displayName == null || displayName.isEmpty)
        ? 'Mon profil'
        : displayName;
    return _SheetCard(
      onTap: () => context.pushNamed(RouteNames.profile),
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Row(
          children: [
            // Même identité visuelle que l'avatar du header (initiales,
            // serein, badge de niveau).
            RingAvatar.fromName(
              displayName,
              lettersState?.activeLetter?.progress,
              serein: serein,
              level: grade?.level,
            ),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shown,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    grade?.title ?? facteurLadder.first.title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateAvailableTile extends ConsumerWidget {
  const _UpdateAvailableTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || !Platform.isAndroid) return const SizedBox.shrink();
    final colors = context.facteurColors;
    final info = ref.watch(appUpdateProvider).valueOrNull;
    if (info == null || !info.updateAvailable) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space4),
      child: _SheetCard(
        onTap: () => UpdateBottomSheet.show(context, info: info),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space4,
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.arrowCircleDown(PhosphorIconsStyle.regular),
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mise à jour disponible',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.name.isNotEmpty ? info.name : info.latestTag,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Icon(
                PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
                color: colors.primary.withOpacity(0.6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SereinSwitchTile extends ConsumerWidget {
  const _SereinSwitchTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final enabled = ref.watch(sereinToggleProvider).enabled;

    return _SheetCard(
      onTap: () => ref.read(sereinToggleProvider.notifier).toggle(),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SereinColors.sereinColor.withOpacity(0.12),
              ),
              alignment: Alignment.center,
              child: Icon(
                SereinColors.sereinIcon,
                color: SereinColors.sereinColor,
                size: 18,
              ),
            ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mode Serein',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Une lecture plus calme, sans urgence',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              activeColor: SereinColors.sereinColor,
              onChanged: (_) =>
                  ref.read(sereinToggleProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentShortcuts extends ConsumerWidget {
  const _ContentShortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Point d'entrée veille dédié et découvrable (restauré après le retrait au
    // commit dbb6aa20). État adaptatif : veille active → « Ma veille » (édition) ;
    // sinon → libellé incitatif vers la création.
    final hasVeille = ref.watch(veilleActiveConfigProvider).valueOrNull != null;
    return _SheetCard(
      child: Column(
        children: [
          _ShortcutTile(
            icon: PhosphorIcons.bookOpen(PhosphorIconsStyle.regular),
            label: 'Mes sources',
            onTap: () => context.pushNamed(RouteNames.sources),
          ),
          const _Divider(),
          _ShortcutTile(
            icon: PhosphorIcons.heart(PhosphorIconsStyle.regular),
            label: 'Mes intérêts',
            onTap: () => context.pushNamed(RouteNames.myInterests),
          ),
          const _Divider(),
          _ShortcutTile(
            icon: PhosphorIcons.binoculars(PhosphorIconsStyle.regular),
            label: hasVeille ? 'Ma veille' : 'Crée ta veille',
            // Même destination que l'ancien « Gérer ma veille » de Mes intérêts :
            // veille active → menu modifier/archiver ; sinon → flow de création.
            onTap: () => hasVeille
                ? _showVeilleManageMenu(context, ref)
                : context.pushNamed(RouteNames.veilleConfig),
          ),
          const _Divider(),
          _ShortcutTile(
            icon: PhosphorIcons.palette(PhosphorIconsStyle.regular),
            label: 'Apparence',
            onTap: () => context.pushNamed(RouteNames.appearance),
          ),
          const _Divider(),
          _ShortcutTile(
            icon: PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.regular),
            label: 'Sauvegardés',
            onTap: () => context.pushNamed(RouteNames.saved),
          ),
        ],
      ),
    );
  }
}

/// Menu de gestion de la veille (modifier / archiver) — déplacé depuis Mes
/// intérêts vers le point d'entrée dédié des réglages (« Ma veille »).
Future<void> _showVeilleManageMenu(BuildContext context, WidgetRef ref) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(PhosphorIcons.pencilSimple()),
            title: const Text('Modifier la veille'),
            onTap: () => Navigator.of(sheetContext).pop('edit'),
          ),
          ListTile(
            leading: Icon(PhosphorIcons.archive(), color: Colors.red.shade700),
            title: Text(
              'Archiver',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () => Navigator.of(sheetContext).pop('archive'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'edit') {
    await context.pushNamed(
      RouteNames.veilleConfig,
      queryParameters: const {'mode': 'edit'},
    );
  } else if (choice == 'archive') {
    await _confirmAndArchiveVeille(context, ref);
  }
}

Future<void> _confirmAndArchiveVeille(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Archiver la veille ?'),
      content: const Text(
        'Ta veille sera retirée de Mes intérêts et de ta Tournée. '
        'Tu pourras en créer une nouvelle à tout moment.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Archiver'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(veilleRepositoryProvider).deleteConfig();
    // La config active devient null → le libellé de la tuile repasse à
    // « Crée ta veille » et le favori veille disparaît de Mes intérêts.
    ref.invalidate(veilleActiveConfigProvider);
    ref.invalidate(userInterestsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Veille archivée')));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Impossible d'archiver la veille.")),
    );
  }
}

class _FeedbackTile extends ConsumerWidget {
  const _FeedbackTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    return _SheetCard(
      onTap: () {
        // Trace serveur pour la lettre 4 (action give_app_feedback).
        unawaited(ref.read(analyticsServiceProvider).trackAppFeedbackOpened());
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => const FeedbackModal(),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space4,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.chatCircleDots(PhosphorIconsStyle.regular),
              color: colors.primary,
              size: 22,
            ),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Text(
                'Donner mon avis',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.primary.withOpacity(0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space4,
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 22),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.regular),
              color: colors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: Container(height: 1, color: colors.border.withOpacity(0.5)),
    );
  }
}

class _SheetCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _SheetCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final borderRadius = BorderRadius.circular(FacteurRadius.large);
    return Material(
      color: colors.surface,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: colors.surfaceElevated),
          ),
          child: child,
        ),
      ),
    );
  }
}
