import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Layout commun aux 3 pages du Welcome Tour.
///
/// Structure : illustration au-dessus, titre, sous-titre. Padding et spacing
/// alignés avec les écrans d'onboarding pour continuité visuelle.
class TourPageScaffold extends StatelessWidget {
  const TourPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.illustration,
  });

  final String title;
  final String subtitle;
  final Widget illustration;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
          Center(child: illustration),
          const SizedBox(height: FacteurSpacing.space8),
          Text(
            title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}
