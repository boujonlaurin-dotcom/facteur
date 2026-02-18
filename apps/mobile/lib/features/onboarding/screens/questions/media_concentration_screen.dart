import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Écran de la carte de concentration des médias
class MediaConcentrationScreen extends ConsumerWidget {
  const MediaConcentrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 1),

          // Title
          Text(
            OnboardingStrings.mediaConcentrationTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Media concentration map image (tap to zoom)
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _openFullscreenImage(context, colors),
              child: Stack(
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                      child: Image.asset(
                        'assets/images/media_concentration_map.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(
                                FacteurRadius.medium),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image_outlined,
                                    size: 48,
                                    color: colors.textTertiary),
                                const SizedBox(height: 8),
                                Text(
                                  'Carte des médias',
                                  style: TextStyle(
                                      color: colors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Zoom hint
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            colors.textPrimary.withValues(alpha: 0.6),
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in,
                              size: 14,
                              color: colors.backgroundPrimary),
                          const SizedBox(width: 4),
                          Text(
                            'Agrandir',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.backgroundPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Explanatory text
          Text(
            OnboardingStrings.mediaConcentrationText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 1),

          // Continue button
          ElevatedButton(
            onPressed: () {
              ref
                  .read(onboardingProvider.notifier)
                  .continueAfterMediaConcentration();
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: colors.primary,
            ),
            child: const Text(
              OnboardingStrings.mediaConcentrationButton,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }

  void _openFullscreenImage(BuildContext context, FacteurColors colors) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullscreenImageViewer(colors: colors),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }
}

class _FullscreenImageViewer extends StatelessWidget {
  final FacteurColors colors;

  const _FullscreenImageViewer({required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              // Zoomable image
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Padding(
                    padding: const EdgeInsets.all(FacteurSpacing.space4),
                    child: Image.asset(
                      'assets/images/media_concentration_map.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: FacteurSpacing.space2,
                right: FacteurSpacing.space4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        colors.textPrimary.withValues(alpha: 0.5),
                  ),
                  icon: Icon(Icons.close,
                      color: colors.backgroundPrimary, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
