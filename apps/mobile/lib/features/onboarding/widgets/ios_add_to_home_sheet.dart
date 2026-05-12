import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/ios_add_to_home_provider.dart';

/// Affiche la modal pédagogique iOS Safari "Ajouter à l'écran d'accueil".
///
/// iOS ne supporte pas `beforeinstallprompt` — pas d'install programmatique
/// possible. La modal explique en 3 étapes visuelles comment passer par le
/// Share Sheet de Safari.
///
/// Retourne `true` si l'utilisateur a confirmé "C'est fait", `false` s'il a
/// snoozé ("Plus tard") ou fermé via tap hors modal.
Future<bool?> showIosAddToHomeSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  unawaited(ref.read(analyticsServiceProvider).trackIosAddToHomeShown());
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    useRootNavigator: true,
    builder: (_) => const Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space6,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: IosAddToHomeSheet(),
    ),
  );
}

class IosAddToHomeSheet extends ConsumerStatefulWidget {
  const IosAddToHomeSheet({super.key});

  @override
  ConsumerState<IosAddToHomeSheet> createState() => _IosAddToHomeSheetState();
}

class _IosAddToHomeSheetState extends ConsumerState<IosAddToHomeSheet> {
  bool _busy = false;

  Future<void> _onConfirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(iosAddToHomeControllerProvider).markConfirmed();
    unawaited(
      ref.read(analyticsServiceProvider).trackIosAddToHomeConfirmed(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(iosAddToHomeControllerProvider).markDismissed();
    unawaited(
      ref.read(analyticsServiceProvider).trackIosAddToHomeDismissed(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Material(
      color: colors.backgroundPrimary,
      borderRadius: BorderRadius.circular(FacteurRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            FacteurSpacing.space4,
            FacteurSpacing.space6,
            FacteurSpacing.space4,
            FacteurSpacing.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.primaryMuted,
                    borderRadius: BorderRadius.circular(FacteurRadius.large),
                  ),
                  child: Icon(
                    PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                    color: colors.primary,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Gardez Facteur à portée de main',
                style: FacteurTypography.displayMedium(colors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                "Ajoutez Facteur à votre écran d'accueil pour le retrouver "
                "d'un geste, comme une vraie app — plus rapide, toujours là.",
                style: FacteurTypography.bodyMedium(colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space6),
              _StepRow(
                index: 1,
                icon: PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                text: 'Touchez l\'icône Partage en bas de Safari',
              ),
              const SizedBox(height: FacteurSpacing.space3),
              _StepRow(
                index: 2,
                icon: PhosphorIcons.plusSquare(PhosphorIconsStyle.regular),
                text: 'Choisissez "Sur l\'écran d\'accueil"',
              ),
              const SizedBox(height: FacteurSpacing.space3),
              _StepRow(
                index: 3,
                icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.regular),
                text: 'Confirmez avec "Ajouter"',
              ),
              const SizedBox(height: FacteurSpacing.space6),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.large),
                    ),
                  ),
                  child: const Text(
                    "C'est fait",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              TextButton(
                onPressed: _busy ? null : _onSkip,
                child: Text(
                  'Plus tard',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une étape numérotée du tutoriel : numéro dans un cercle, icône iOS, texte.
class _StepRow extends StatelessWidget {
  final int index;
  final IconData icon;
  final String text;

  const _StepRow({
    required this.index,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: FacteurTypography.labelMedium(colors.backgroundPrimary)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space3),
          Icon(icon, size: 24, color: colors.textSecondary),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Text(
              text,
              style: FacteurTypography.bodyMedium(colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
