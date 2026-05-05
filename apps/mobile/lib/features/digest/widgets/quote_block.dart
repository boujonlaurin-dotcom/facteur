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

    final separatorColor = colors.primary.withOpacity(isDark ? 0.45 : 0.38);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top separator
          Center(
            child: Container(
              width: 56,
              height: 1.5,
              decoration: BoxDecoration(
                color: separatorColor,
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Inline quote: « text » — author
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '\u00AB ',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w300,
                    color: colors.primary.withOpacity(isDark ? 0.55 : 0.40),
                  ),
                ),
                TextSpan(
                  text: quote.text,
                  style: TextStyle(
                    fontSize: 17,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary.withOpacity(0.85),
                    height: 1.5,
                  ),
                ),
                TextSpan(
                  text: ' \u00BB',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w300,
                    color: colors.primary.withOpacity(isDark ? 0.55 : 0.40),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '\u2014 ${quote.author}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary.withOpacity(0.65),
            ),
          ),
          const SizedBox(height: 8),
          // Bottom separator
          Center(
            child: Container(
              width: 56,
              height: 1.5,
              decoration: BoxDecoration(
                color: separatorColor,
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
