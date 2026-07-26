import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/topic_labels.dart' show macroThemeToApiSlug;
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../sources/providers/sources_providers.dart' show userSourcesProvider;
import '../models/search_result.dart' show TopicResult;
import 'feed_provider.dart';

/// Libellé du filtre feed actif, **quelle que soit sa dimension** (mot-clé,
/// source, thème, sujet, entité). Source de vérité unique pour la loupe du
/// header ([HeaderSearchButton]) et la pill de la barre de filtres
/// ([FeedFilterBar]) : jusqu'ici le header ne regardait que `keyword` et
/// repassait en icône neutre dès qu'on filtrait par source/sujet/thème
/// (setters exclusifs du notifier), alors qu'un filtre était bien actif.
///
/// Renvoie `null` quand aucun filtre n'est posé. `isKeyword` distingue le
/// mot-clé — le seul à porter le suffixe « · toutes sources » quand la
/// recherche est élargie — des filtres de catalogue.
///
/// `resolved` distingue un libellé lisible (nom de source/thème/sujet trouvé,
/// ou mot-clé) d'un repli sur le slug/id brut le temps qu'un provider async se
/// peuple. Les pills du header et de la barre affichent toujours `label` (mieux
/// vaut un slug qu'une icône neutre alors qu'un filtre est actif) ; l'état vide
/// de `flaner_screen` n'affiche que les libellés `resolved` et garde sinon son
/// titre générique.
final activeFilterLabelProvider =
    Provider<({String label, bool isKeyword, bool resolved})?>((ref) {
  final selection = ref.watch(feedFilterSelectionProvider);
  final kind = selection.activeKind;
  if (kind == null) return null;

  switch (kind) {
    case FeedFilterKind.keyword:
      final kw = selection.keyword!.trim();
      final label = selection.includeUnfollowed ? '$kw · toutes sources' : kw;
      return (label: label, isKeyword: true, resolved: true);
    case FeedFilterKind.source:
      final id = selection.sourceId!;
      final sources = ref.watch(userSourcesProvider).valueOrNull;
      if (sources != null) {
        for (final s in sources) {
          if (s.id == id) {
            return (label: s.name, isKeyword: false, resolved: true);
          }
        }
      }
      return (label: id, isKeyword: false, resolved: false);
    case FeedFilterKind.theme:
      final slug = selection.theme!;
      for (final entry in macroThemeToApiSlug.entries) {
        if (entry.value == slug) {
          return (label: entry.key, isKeyword: false, resolved: true);
        }
      }
      return (label: slug, isKeyword: false, resolved: false);
    case FeedFilterKind.topic:
    case FeedFilterKind.entity:
      final value =
          kind == FeedFilterKind.topic ? selection.topic! : selection.entity!;
      final topics = ref.watch(customTopicsProvider).valueOrNull;
      if (topics != null) {
        for (final t in topics) {
          if (TopicResult(t).filterValue == value) {
            return (label: t.name, isKeyword: false, resolved: true);
          }
        }
      }
      return (label: value, isKeyword: false, resolved: false);
  }
});
