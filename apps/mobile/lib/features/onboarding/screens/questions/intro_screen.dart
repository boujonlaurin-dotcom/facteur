import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

import '../../../../widgets/design/facteur_logo.dart';

/// Welcome Screen: "Bienvenue sur Facteur !"
/// Replaces the old IntroScreen1.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _showManifesto = false;

  void _toggleManifesto() {
    setState(() {
      _showManifesto = !_showManifesto;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),

          // Logo
          const Center(child: FacteurLogo(size: 42)),

          const SizedBox(height: FacteurSpacing.space6),

          if (!_showManifesto) ...[
            // Headline
            Text(
              OnboardingStrings.welcomeTitle,
              style: Theme.of(context).textTheme.displayLarge,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: FacteurSpacing.space6),

            // Subtext
            Text(
              OnboardingStrings.welcomeSubtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
            const Spacer(flex: 2),
          ] else ...[
            // Manifesto Content
            Expanded(
              child: Container(
                margin:
                    const EdgeInsets.symmetric(vertical: FacteurSpacing.space4),
                padding: const EdgeInsets.all(FacteurSpacing.space4),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: colors.primary.withValues(alpha: 0.1)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notre Manifeste',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: FacteurSpacing.space4),
                      _buildManifestoSection(
                        'Le Projet',
                        'Facteur est un projet open-source visant à créer une brique engageante et facile d\'accès pour s\'approprier l\'information.',
                      ),
                      _buildManifestoSection(
                        'Notre But',
                        'Re-donner de la qualité, de l\'indépendance et de la pluralité à l\'information. Trier l\'info du bruit pour informer en profondeur.',
                      ),
                      _buildManifestoSection(
                        'Philosophie',
                        'Nous pensons que la technologie doit servir l\'humanité - pas l\'inverse. Nous avançons pas-à-pas avec notre communauté.',
                      ),
                      const SizedBox(height: FacteurSpacing.space4),
                      Text(
                        'Nos Combats :',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space2),
                      _buildCombatTag('Anti-trust des médias'),
                      _buildCombatTag('Biais cognitifs'),
                      _buildCombatTag('Algorithmes opaques'),
                      _buildCombatTag('Addiction numérique'),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // Manifesto Toggle Button
          TextButton(
            onPressed: _toggleManifesto,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: colors.textSecondary,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _showManifesto
                      ? 'Masquer le manifeste'
                      : OnboardingStrings.welcomeManifestoButton,
                  style: const TextStyle(
                    fontSize: 15,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _showManifesto ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // CTA Button
          ElevatedButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).continueToIntro2();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Text(
              OnboardingStrings.welcomeStartButton,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }

  Widget _buildManifestoSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            content,
            style: TextStyle(
              color: context.facteurColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCombatTag(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 14, color: context.facteurColors.primary),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Intro screen 2: Facteur's mission
/// Second part of the mission statement.
class IntroScreen2 extends ConsumerWidget {
  const IntroScreen2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          // Headline
          Text(
            OnboardingStrings.intro2Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Subtext
          Text(
            OnboardingStrings.intro2Subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          // CTA Button
          ElevatedButton(
            onPressed: () {
              ref.read(onboardingProvider.notifier).continueAfterIntro();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Text(
              OnboardingStrings.intro2Button,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
