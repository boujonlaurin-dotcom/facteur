import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/routes.dart';
import '../../core/providers/analytics_provider.dart';

/// Ouvre l'écran d'ajout de source avec la recherche intelligente **déjà
/// lancée** sur [query], et émet `search_add_source_bridged`.
///
/// Story 30.1 — deux surfaces mènent ici (la sheet de recherche et l'état vide
/// de Flâner) ; le contrat analytics et le passage de `extra` vivent donc en un
/// seul endroit plutôt qu'en deux copies qui divergeront.
void openAddSourceFor(BuildContext context, WidgetRef ref, String query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return;
  unawaited(
    ref
        .read(analyticsServiceProvider)
        .trackSearchAddSourceBridged(bridgeCase: 'smart_search'),
  );
  context.pushNamed(RouteNames.addSource, extra: trimmed);
}
