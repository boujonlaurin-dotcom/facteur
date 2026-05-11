import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/services/widget_service.dart';
import '../providers/user_profile_provider.dart';
import 'package:facteur/core/ui/notification_service.dart';

/// Écran de gestion du compte utilisateur
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final authState = ref.watch(authStateProvider);
    final userEmail = authState.user?.email ?? 'Email non disponible';

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text(kIsWeb ? 'Compte' : 'Compte & Widget'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Info Compte
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                border: Border.all(color: colors.surfaceElevated),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INFORMATIONS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                          letterSpacing: 1.5,
                        ),
                  ),
                  const SizedBox(height: FacteurSpacing.space3),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Nom d\'affichage',
                    value: ref.watch(userProfileProvider).displayName ??
                        'Non renseigné',
                    onTap: () => _editDisplayName(context, ref),
                  ),
                  const SizedBox(height: FacteurSpacing.space2),
                  Row(
                    children: [
                      Icon(Icons.email_outlined,
                          color: colors.primary, size: 20),
                      const SizedBox(width: FacteurSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                            ),
                            Text(
                              userEmail,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Section Widget (Android uniquement, masquée sur Web)
            if (!kIsWeb && Platform.isAndroid) ...[
              const SizedBox(height: FacteurSpacing.space6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FacteurSpacing.space4),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                  border: Border.all(color: colors.surfaceElevated),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WIDGET',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            letterSpacing: 1.5,
                          ),
                    ),
                    const SizedBox(height: FacteurSpacing.space3),
                    InkWell(
                      onTap: () async {
                        await WidgetService.requestPinWidget();
                      },
                      borderRadius: BorderRadius.circular(FacteurRadius.medium),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
                            color: colors.primary,
                            size: 20,
                          ),
                          const SizedBox(width: FacteurSpacing.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ajouter le widget Facteur',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Affiche ton essentiel du jour sur l\'écran d\'accueil',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            PhosphorIcons.arrowSquareOut(
                                PhosphorIconsStyle.regular),
                            color: colors.textTertiary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // Bouton Déconnexion
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(authStateProvider.notifier).signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Se déconnecter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  side: BorderSide(color: colors.surfaceElevated),
                  padding: const EdgeInsets.symmetric(
                    vertical: FacteurSpacing.space3,
                  ),
                ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space3),

            // Bouton Supprimer compte
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _showDeleteConfirmation(context),
                style: TextButton.styleFrom(
                  foregroundColor: colors.error,
                  padding: const EdgeInsets.symmetric(
                    vertical: FacteurSpacing.space3,
                  ),
                ),
                child: const Text('Supprimer mon compte'),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space8),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
  }

  void _editDisplayName(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final currentValue = ref.read(userProfileProvider).displayName ?? '';
    final controller = TextEditingController(text: currentValue);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Nom d\'affichage',
            style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Votre nom',
            hintStyle: TextStyle(color: colors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                Text('Annuler', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(userProfileProvider.notifier).updateProfile(
                    displayName: controller.text.trim(),
                  );
              Navigator.of(context).pop();
            },
            child: Text('Enregistrer', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }
}

/// Widget pour afficher une ligne d'information éditable
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, color: colors.textTertiary, size: 18),
        ],
      ),
    );
  }
}

/// Dialog de confirmation de suppression de compte avec garde-fou textuel.
///
/// Apple 5.1.1(v) et Google Play Account Deletion : la suppression doit être
/// initiable depuis l'app et exécutable sans interaction manuelle du support.
/// Le backend fait un soft-delete (deleted_at + email_hash) avec purge cron à
/// J+30 — l'utilisateur peut se reconnecter pendant cette fenêtre pour annuler.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  static const _confirmationKeyword = 'SUPPRIMER';

  final _controller = TextEditingController();
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canDelete =>
      !_isDeleting && _controller.text == _confirmationKeyword;

  Future<void> _confirmDelete() async {
    setState(() => _isDeleting = true);
    try {
      await ref.read(userApiServiceProvider).deleteAccount();
      await ref.read(authStateProvider.notifier).signOut();
      if (!mounted) return;
      // Sortir explicitement du stack Settings vers le login. Le router a déjà
      // un redirect basé sur isAuthenticated, mais goNamed garantit qu'on ne
      // revient pas dans un écran orphelin (ex. Profile) après le pop.
      Navigator.of(context).pop();
      context.goNamed(RouteNames.login);
    } on DioException {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      NotificationService.showError(
        'Suppression impossible. Vérifie ta connexion et réessaye.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      NotificationService.showError(
        'Une erreur est survenue. Réessaye plus tard.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Supprimer mon compte ?',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Toutes tes données (profil, préférences, historique de lecture) '
            'seront supprimées. Tu as 30 jours pour annuler la suppression en '
            'te reconnectant — passé ce délai, l\'effacement est définitif.',
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space4),
          Text(
            'Tape $_confirmationKeyword pour confirmer.',
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isDeleting,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: _confirmationKeyword,
              hintStyle: TextStyle(color: colors.textTertiary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: Text('Annuler', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: _canDelete ? _confirmDelete : null,
          child: _isDeleting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.error,
                  ),
                )
              : Text('Supprimer', style: TextStyle(color: colors.error)),
        ),
      ],
    );
  }
}
