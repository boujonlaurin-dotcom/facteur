import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../widgets/source_add_panel.dart';

class AddSourceScreen extends ConsumerWidget {
  /// Requête pré-remplie, passée via `state.extra` depuis la recherche
  /// universelle (story 30.1) : l'écran s'ouvre avec la recherche déjà lancée.
  final String? initialQuery;

  const AddSourceScreen({super.key, this.initialQuery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
          onPressed: () => context.pop(),
        ),
        title: const Text('Ajouter une source'),
      ),
      body: SourceAddPanel(initialQuery: initialQuery),
    );
  }
}
