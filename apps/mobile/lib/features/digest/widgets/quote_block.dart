import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';

/// Editorial quote block — displayed in serein digest only.
/// Elegant card with large decorative guillemets and centered text.
class QuoteBlock extends StatelessWidget {
  final QuoteResponse quote;

  const QuoteBlock({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    if (quote.text.trim().isEmpty) return const SizedBox.shrink();
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : colors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : colors.primary.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          children: [
            // Decorative opening guillemet
            Text(
              '\u00AB',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w300,
                height: 1,
                color: colors.primary.withValues(alpha: isDark ? 0.40 : 0.28),
              ),
            ),
            const SizedBox(height: 8),
            // Quote text
            Text(
              quote.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary.withValues(alpha: 0.80),
                height: 1.55,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 12),
            // Thin accent line
            Container(
              width: 32,
              height: 1.5,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: isDark ? 0.30 : 0.22),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 10),
            // Author attribution
            Text(
              quote.author,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: colors.textSecondary.withValues(alpha: 0.70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
