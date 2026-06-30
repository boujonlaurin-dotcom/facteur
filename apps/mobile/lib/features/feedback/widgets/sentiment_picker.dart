import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/feedback_providers.dart';

/// Micro-feedback emoji affiché en fin de Tournée du jour (Epic 13).
///
/// 3 niveaux : 😴 ("low"), 🙂 ("ok"), 🔥 ("high"). Un tap, optionnel, non
/// bloquant. Intégré dans la carte de fin de tournée (`FeedbackClosingCard`).
class SentimentPicker extends ConsumerStatefulWidget {
  /// Date du digest noté (par défaut : aujourd'hui côté backend).
  final DateTime? digestDate;

  const SentimentPicker({super.key, this.digestDate});

  @override
  ConsumerState<SentimentPicker> createState() => _SentimentPickerState();
}

class _SentimentPickerState extends ConsumerState<SentimentPicker> {
  String? _selected;

  static const List<({String value, String emoji, String label})> _options = [
    (value: 'low', emoji: '😴', label: 'Bof'),
    (value: 'ok', emoji: '🙂', label: 'Sympa'),
    (value: 'high', emoji: '🔥', label: 'Top'),
  ];

  Future<void> _onTap(String value) async {
    if (_selected != null) return;
    setState(() => _selected = value);
    await ref
        .read(feedbackRepositoryProvider)
        .submitSentiment(value, date: widget.digestDate);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    if (_selected != null) {
      return Padding(
        padding: const EdgeInsets.only(top: FacteurSpacing.space3),
        child: Text(
          'Merci pour ton retour 🙏',
          style: textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: FacteurSpacing.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Ta tournée du jour, c\'était comment ?',
            style: textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final option in _options)
                _EmojiButton(
                  emoji: option.emoji,
                  label: option.label,
                  onTap: () => _onTap(option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 4),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
