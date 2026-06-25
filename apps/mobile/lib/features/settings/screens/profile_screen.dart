import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../../flux_continu/providers/morning_ritual_qa_provider.dart';
import '../../flux_continu/services/tournee_progress_service.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../widgets/profile_progression_card.dart';

/// Le bloc QA (rituel matinal) n'est monté qu'en staging/dev : build debug
/// **ou** canal beta (flavor staging). Jamais en prod (canal stable).
bool get _showQaTools =>
    kDebugMode || AppUpdateConstants.updateChannel == 'beta';

/// Page « Profil » regroupant les réglages applicatifs accessibles depuis
/// la sheet Réglages : compte, notifications, questionnaire, présentation
/// et liens secondaires.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
        child: Column(
          children: [
            const ProfileProgressionCard(),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'COMPTE',
              children: [
                _Tile(
                  icon: Icons.person_outline,
                  title: kIsWeb ? 'Compte' : 'Compte & Widget',
                  subtitle: 'Gérer vos informations',
                  onTap: () => context.pushNamed(RouteNames.account),
                ),
                if (!kIsWeb)
                  _Tile(
                    icon: Icons.notifications_none,
                    title: 'Notifications',
                    onTap: () => context.pushNamed(RouteNames.notifications),
                  ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'PRÉFÉRENCES',
              children: [
                _Tile(
                  icon: Icons.settings_suggest_outlined,
                  title: 'Refaire le questionnaire',
                  subtitle: 'Ajuster mon profil et mes préférences',
                  onTap: () {
                    ref.read(onboardingProvider.notifier).restartOnboarding();
                    ref
                        .read(authStateProvider.notifier)
                        .setNeedsOnboarding(true);
                  },
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'À PROPOS',
              children: [
                _Tile(
                  icon: Icons.info_outline,
                  title: 'Présentation Facteur',
                  subtitle: 'Version Beta 1.2',
                  onTap: () => context.pushNamed(RouteNames.about),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _Section(
              title: 'AIDE & INFORMATIONS',
              children: [
                _Tile(
                  icon: PhosphorIcons.shieldCheck(PhosphorIconsStyle.regular),
                  title: 'Politique de confidentialité',
                  onTap: () => _open(LegalLinks.privacy),
                ),
                _Tile(
                  icon: PhosphorIcons.fileText(PhosphorIconsStyle.regular),
                  title: 'Conditions d\'utilisation',
                  onTap: () => _open(LegalLinks.terms),
                ),
                _Tile(
                  icon: PhosphorIcons.lifebuoy(PhosphorIconsStyle.regular),
                  title: 'Contacter le support',
                  onTap: () => _open(LegalLinks.supportEmail),
                ),
              ],
            ),
            if (_showQaTools) ...[
              const SizedBox(height: FacteurSpacing.space6),
              _Section(
                title: 'RITUEL MATINAL (QA)',
                children: [
                  _Tile(
                    icon: Icons.replay,
                    title: 'Rejouer le rituel matinal',
                    subtitle: 'Réaffiche « Ton édition vient d\'arriver » au '
                        'prochain redémarrage',
                    onTap: () async {
                      await ref
                          .read(tourneeProgressServiceProvider)
                          .resetMorningRitualShown();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Rituel réarmé — relance l\'app pour le revoir.',
                          ),
                        ),
                      );
                    },
                  ),
                  _SwitchTile(
                    icon: Icons.hourglass_empty,
                    title: 'Forcer « édition pas prête »',
                    subtitle: 'Valide le repli vers le feed (état B)',
                    value: ref.watch(debugForceMorningRitualNotReadyProvider),
                    onChanged: (v) => ref
                        .read(debugForceMorningRitualNotReadyProvider.notifier)
                        .state = v,
                  ),
                ],
              ),
            ],
            const SizedBox(height: FacteurSpacing.space8),
          ],
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
            vertical: FacteurSpacing.space2,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 1.5,
                ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.surfaceElevated),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Variante de [_Tile] avec un interrupteur (réglages QA on/off).
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 24),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 24),
            const SizedBox(width: FacteurSpacing.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
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
