import 'package:flutter/material.dart';

import '../../../config/theme.dart';

// TODO(PR3): replace with CourrierScreen
class LettresPlaceholderScreen extends StatelessWidget {
  const LettresPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        title: Text(
          'Courrier',
          style: FacteurTypography.displaySmall(colors.textPrimary),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Text(
            'Courrier — coming soon',
            style: FacteurTypography.bodyMedium(colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
