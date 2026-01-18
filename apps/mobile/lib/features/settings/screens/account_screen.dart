import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
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
        title: const Text('Compte'),
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
                    label: 'Prénom',
                    value: ref.watch(userProfileProvider).firstName ??
                        'Non renseigné',
                    onTap: () => _editFirstName(context, ref),
                  ),
                  const SizedBox(height: FacteurSpacing.space2),
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: 'Nom',
                    value: ref.watch(userProfileProvider).lastName ??
                        'Non renseigné',
                    onTap: () => _editLastName(context, ref),
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
                onPressed: () => _showDeleteConfirmation(context, ref),
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

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Supprimer mon compte ?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Cette action est irréversible. Toutes vos données seront perdues.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child:
                Text('Annuler', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              // TODO: Implémenter la suppression via Supabase RPC
              // Pour l'instant, on se contente de déconnecter
              NotificationService.showError(
                'Contactez le support pour supprimer votre compte.',
              );
            },
            child: Text('Supprimer', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }

  void _editFirstName(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final currentValue = ref.read(userProfileProvider).firstName ?? '';
    final controller = TextEditingController(text: currentValue);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Prénom', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Votre prénom',
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
                    firstName: controller.text.trim(),
                    lastName: ref.read(userProfileProvider).lastName,
                  );
              Navigator.of(context).pop();
            },
            child: Text('Enregistrer', style: TextStyle(color: colors.primary)),
          ),
        ],
      ),
    );
  }

  void _editLastName(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final currentValue = ref.read(userProfileProvider).lastName ?? '';
    final controller = TextEditingController(text: currentValue);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Nom', style: TextStyle(color: colors.textPrimary)),
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
                    firstName: ref.read(userProfileProvider).firstName,
                    lastName: controller.text.trim(),
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
