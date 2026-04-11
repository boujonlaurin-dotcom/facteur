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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inline quote: « text » — author
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '\u00AB ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: colors.primary.withValues(alpha: isDark ? 0.50 : 0.35),
                  ),
                ),
                TextSpan(
                  text: quote.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
                TextSpan(
                  text: ' \u00BB',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: colors.primary.withValues(alpha: isDark ? 0.50 : 0.35),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '\u2014 ${quote.author}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
