import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../shared/widgets/buttons/secondary_button.dart';
import 'package:facteur/core/ui/notification_service.dart';
import '../../../core/auth/auth_state.dart';

/// Écran de confirmation après création de compte
/// Affiché lorsque l'utilisateur doit valider son email
class EmailConfirmationScreen extends ConsumerStatefulWidget {
  final String email;

  const EmailConfirmationScreen({
    super.key,
    required this.email,
  });

  @override
  ConsumerState<EmailConfirmationScreen> createState() =>
      _EmailConfirmationScreenState();
}

class _EmailConfirmationScreenState
    extends ConsumerState<EmailConfirmationScreen> {
  bool _resending = false;
  bool _resent = false;

  Future<void> _resendEmail() async {
    setState(() {
      _resending = true;
      _resent = false;
    });

    try {
      debugPrint(
          'EmailConfirmationScreen: Requesting resend for ${widget.email}');
      await ref
          .read(authStateProvider.notifier)
          .resendConfirmationEmail(widget.email);

      if (mounted) {
        setState(() {
          _resending = false;
          _resent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resending = false);
        NotificationService.showError(
          'Impossible de renvoyer l\'email. Réessaie plus tard.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Bouton déconnexion
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(authStateProvider.notifier).signOut(),
                  icon: Icon(
                    PhosphorIcons.signOut(PhosphorIconsStyle.regular),
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  label: Text(
                    'Se déconnecter',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ),

              const Spacer(),

              // Icône email animée
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIcons.envelope(PhosphorIconsStyle.duotone),
                    size: 48,
                    color: colors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Titre
              Text(
                'Vérifie ta boîte mail !',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'Nous avons envoyé un lien de confirmation à :',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Email (mis en valeur)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.at(PhosphorIconsStyle.regular),
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.email,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Instruction
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIcons.info(PhosphorIconsStyle.fill),
                      size: 20,
                      color: colors.secondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Clique sur le lien dans l\'email pour activer ton compte et commencer à utiliser Facteur.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Bouton "J'ai confirmé"
              PrimaryButton(
                label: 'J\'ai confirmé mon email',
                icon: PhosphorIcons.check(PhosphorIconsStyle.bold),
                onPressed: () =>
                    ref.read(authStateProvider.notifier).refreshUser(),
              ),

              const SizedBox(height: 16),

              // Bouton renvoyer ou confirmation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _resent
                    ? Container(
                        key: const ValueKey('resent'),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: colors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIcons.checkCircle(
                                  PhosphorIconsStyle.fill),
                              color: colors.success,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Email renvoyé !',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colors.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : SecondaryButton(
                        key: const ValueKey('resend'),
                        label: 'Renvoyer l\'email',
                        icon: PhosphorIcons.arrowCounterClockwise(
                          PhosphorIconsStyle.regular,
                        ),
                        onPressed: _resendEmail,
                        isLoading: _resending,
                      ),
              ),

              const Spacer(),

              // Aide spam
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.warningCircle(PhosphorIconsStyle.regular),
                      size: 18,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tu ne trouves pas l\'email ? Vérifie ton dossier spam.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
