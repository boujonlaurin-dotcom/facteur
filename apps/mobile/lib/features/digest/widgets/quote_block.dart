import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';

/// Editorial quote block — displayed in serein digest only.
/// Compact inline quote with thin decorative separators above and below.
class QuoteBlock extends StatelessWidget {
  final QuoteResponse quote;

  const QuoteBlock({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    if (quote.text.trim().isEmpty) return const SizedBox.shrink();
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final separatorColor = colors.primary.withValues(alpha: isDark ? 0.18 : 0.14);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top separator
          Center(
            child: Container(
              width: 40,
              height: 1,
              decoration: BoxDecoration(
                color: separatorColor,
                borderRadius: BorderRadius.circular(0.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          // Bottom separator
          Center(
            child: Container(
              width: 40,
              height: 1,
              decoration: BoxDecoration(
                color: separatorColor,
                borderRadius: BorderRadius.circular(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
