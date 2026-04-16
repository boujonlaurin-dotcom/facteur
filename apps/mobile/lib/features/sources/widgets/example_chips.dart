import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

enum _ExampleType { youtube, newsletter, podcast, reddit, media }

class _Example {
  final String label;
  final _ExampleType type;
  const _Example(this.label, this.type);
}

class ExampleChips extends StatelessWidget {
  final void Function(String text) onTap;

  const ExampleChips({super.key, required this.onTap});

  static const _examples = <_Example>[
    _Example('@HugoDécrypte', _ExampleType.youtube),
    _Example('@Underscore_', _ExampleType.youtube),
    _Example('Snowball', _ExampleType.newsletter),
    _Example('Sismique', _ExampleType.podcast),
    _Example('GDIY', _ExampleType.podcast),
    _Example('r/france', _ExampleType.reddit),
    _Example('Numerama', _ExampleType.media),
    _Example('Le Grand Continent', _ExampleType.media),
  ];

  IconData _iconFor(_ExampleType type) {
    switch (type) {
      case _ExampleType.youtube:
        return PhosphorIcons.youtubeLogo(PhosphorIconsStyle.fill);
      case _ExampleType.newsletter:
        return PhosphorIcons.envelope(PhosphorIconsStyle.fill);
      case _ExampleType.podcast:
        return PhosphorIcons.microphone(PhosphorIconsStyle.fill);
      case _ExampleType.reddit:
        return PhosphorIcons.redditLogo(PhosphorIconsStyle.fill);
      case _ExampleType.media:
        return PhosphorIcons.newspaper(PhosphorIconsStyle.fill);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIcons.lightbulb(PhosphorIconsStyle.regular),
                size: 16, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Quelques exemples :',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _examples
              .map((example) => ActionChip(
                    avatar: Icon(_iconFor(example.type),
                        size: 16, color: colors.primary),
                    label: Text(example.label),
                    labelStyle: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.primary),
                    side: BorderSide(color: colors.primary.withOpacity(0.3)),
                    backgroundColor: colors.primary.withOpacity(0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                    onPressed: () => onTap(example.label),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
