import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../config/theme.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';

class SourcePreviewCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool isLoading;

  const SourcePreviewCard({
    super.key,
    required this.data,
    required this.onConfirm,
    required this.onCancel,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    // Data extraction
    final name = (data['name'] as String?) ?? 'Source Inconnue';
    final description =
        (data['description'] as String?) ?? 'Pas de description';
    final logoUrl = data['logo_url'] as String?;
    final preview = data['preview'] as Map<String, dynamic>?;
    final titles = preview != null && preview['latest_titles'] != null
        ? (preview['latest_titles'] as List).cast<String>()
        : <String>[];

    final detectedType = (data['detected_type'] as String?) ?? 'article';
    IconData icon;
    if (detectedType == 'youtube') {
      icon = PhosphorIcons.youtubeLogo(PhosphorIconsStyle.fill);
    } else if (detectedType == 'podcast') {
      icon = PhosphorIcons.microphone(PhosphorIconsStyle.fill);
    } else {
      icon = PhosphorIcons.rss(PhosphorIconsStyle.fill);
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (logoUrl != null)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: NetworkImage(logoUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colors.primary),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detectedType.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          if (titles.isNotEmpty) ...[
            Text(
              "Derniers articles :",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            ...titles.map((title) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.dotOutline(PhosphorIconsStyle.fill),
                          size: 16, color: colors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: colors.border),
                  ),
                  child: Text(
                    "Annuler",
                    // ignore: deprecated_member_use
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: "Ajouter cette source",
                  onPressed: isLoading ? null : onConfirm,
                  isLoading: isLoading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
