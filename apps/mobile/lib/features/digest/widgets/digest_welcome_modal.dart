import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_button.dart';

/// Provider to track if user has seen the digest welcome
final digestWelcomeShownProvider = StateProvider<bool>((ref) => false);

/// Welcome modal shown on first digest visit
///
/// Displays educational content about the Essentiel feature
/// with animated entrance and dismissal
class DigestWelcomeModal extends ConsumerStatefulWidget {
  /// Callback when modal is dismissed
  final VoidCallback onDismiss;

  const DigestWelcomeModal({
    super.key,
    required this.onDismiss,
  });

  @override
  ConsumerState<DigestWelcomeModal> createState() => _DigestWelcomeModalState();

  /// Check if welcome should be shown and mark as shown
  static Future<bool> shouldShowWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_digest_welcome') ?? false;

    if (!hasSeenWelcome) {
      await prefs.setBool('has_seen_digest_welcome', true);
      return true;
    }

    return false;
  }
}

class _DigestWelcomeModalState extends ConsumerState<DigestWelcomeModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _backdropAnimation;
  late Animation<double> _contentAnimation;
  late Animation<Offset> _contentSlideAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Backdrop fade in
    _backdropAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Content slide + fade
    _contentAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _contentSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: _dismiss,
      child: FadeTransition(
        opacity: _backdropAnimation,
        child: Container(
          color: colors.backgroundPrimary.withValues(alpha: 0.9),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent tap through
              child: SlideTransition(
                position: _contentSlideAnimation,
                child: FadeTransition(
                  opacity: _contentAnimation,
                  child: Container(
                    margin: const EdgeInsets.all(FacteurSpacing.space4),
                    padding: const EdgeInsets.all(FacteurSpacing.space6),
                    decoration: BoxDecoration(
                      color: colors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(FacteurRadius.large),
                      boxShadow: [
                        BoxShadow(
                          color: colors.textPrimary.withValues(alpha: 0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Icon(
                          PhosphorIcons.article(PhosphorIconsStyle.fill),
                          size: 48,
                          color: colors.primary,
                        ),

                        const SizedBox(height: FacteurSpacing.space4),

                        // Title
                        Text(
                          'Bienvenue dans votre Essentiel',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: FacteurSpacing.space3),

                        // Description
                        Text(
                          'Chaque jour, 5 articles sélectionnés pour vous',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: FacteurSpacing.space4),

                        // Feature list
                        _FeatureItem(
                          icon: PhosphorIcons.eye(),
                          title: 'Lisez',
                          description: 'Marquez comme lu après lecture',
                        ),

                        const SizedBox(height: FacteurSpacing.space3),

                        _FeatureItem(
                          icon: PhosphorIcons.bookmark(),
                          title: 'Sauvegardez',
                          description: 'Gardez pour plus tard',
                        ),

                        const SizedBox(height: FacteurSpacing.space3),

                        _FeatureItem(
                          icon: PhosphorIcons.xCircle(),
                          title: 'Passez',
                          description: 'Ignorez ce qui ne vous intéresse pas',
                        ),

                        const SizedBox(height: FacteurSpacing.space4),

                        // Streak info
                        Container(
                          padding: const EdgeInsets.all(FacteurSpacing.space3),
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(FacteurRadius.medium),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIcons.fire(PhosphorIconsStyle.fill),
                                color: colors.warning,
                                size: 20,
                              ),
                              const SizedBox(width: FacteurSpacing.space2),
                              Flexible(
                                child: Text(
                                  'Complétez les 5 pour maintenir votre série !',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: colors.textSecondary,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: FacteurSpacing.space4),

                        // Start button
                        FacteurButton(
                          label: 'Commencer',
                          onPressed: _dismiss,
                        ),

                        const SizedBox(height: FacteurSpacing.space3),

                        // Explorer hint
                        Text(
                          '💡 Vous pouvez explorer plus après votre Essentiel',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(FacteurSpacing.space2),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
