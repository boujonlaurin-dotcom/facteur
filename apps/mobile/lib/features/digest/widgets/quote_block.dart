import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';

/// Editorial quote block — displayed in serein digest only,
/// below the first topic (Bonne Nouvelle).
class QuoteBlock extends StatelessWidget {
  final QuoteResponse quote;

  const QuoteBlock({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    if (quote.text.trim().isEmpty) return const SizedBox.shrink();
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Column(
        children: [
          Text(
            '« ${quote.text} »',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: colors.textPrimary.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '— ${quote.author}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
