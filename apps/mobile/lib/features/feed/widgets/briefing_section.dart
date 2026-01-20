import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/content_model.dart';
import 'briefing_card.dart';

class BriefingSection extends StatelessWidget {
  final List<DailyTop3Item> briefing;
  final void Function(DailyTop3Item) onItemTap;

  const BriefingSection({
    super.key,
    required this.briefing,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (briefing.isEmpty) return const SizedBox.shrink();

    final colors = context.facteurColors;

    // Check if fully consumed or not?
    // User story: "Briefing affiché en haut... Animation collapse après 3 lectures"
    // We implement basic display first. Collapse logic belongs in parent or state.

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Icon(Icons.coffee, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  "L'Essentiel du Jour",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: briefing.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = briefing[index];
              return BriefingCard(
                item: item,
                onTap: () => onItemTap(item),
              );
            },
          ),
        ],
      ),
    );
  }
}
