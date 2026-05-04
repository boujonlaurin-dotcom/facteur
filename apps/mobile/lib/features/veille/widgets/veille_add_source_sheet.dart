import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../sources/models/smart_search_result.dart';
import '../../sources/widgets/source_add_panel.dart';

/// Sheet "Ajouter une source" hébergé par le flow Veille (Step 3).
/// Délègue le moteur de recherche / preview / ajout à [SourceAddPanel] —
/// quand l'ajout réussit, on remonte la `SmartSearchResult` au parent qui
/// décide d'injecter la source dans le state Step 3 et de fermer le sheet.
///
/// À ouvrir via :
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => VeilleAddSourceSheet(onSourceAdded: ...),
/// );
/// ```
class VeilleAddSourceSheet extends ConsumerWidget {
  final ValueChanged<SmartSearchResult> onSourceAdded;

  const VeilleAddSourceSheet({super.key, required this.onSourceAdded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Drag handle + close button
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.regular),
                        color: colors.textSecondary,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Ajouter une source à ta veille',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PrimaryScrollController(
                  controller: scrollController,
                  child: SourceAddPanel(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    showIntro: false,
                    showCommunityGems: false,
                    showAddedNudge: false,
                    autoFocusSearch: true,
                    onSourceAdded: onSourceAdded,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
