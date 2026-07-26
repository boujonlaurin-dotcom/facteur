import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/topic_labels.dart' show macroThemeToApiSlug;
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../sources/providers/sources_providers.dart' show userSourcesProvider;
import '../models/search_result.dart' show TopicResult;
import 'feed_provider.dart';

/// Libellé du filtre feed actif, **quelle que soit sa dimension** (mot-clé,
/// source, thème, sujet, entité). Source de vérité de la pill de la barre de
/// filtres ([FeedFilterBar]), qui suit **n'importe quelle** dimension (setters
/// exclusifs du notifier) et non plus seulement `keyword`. La loupe du header
/// ([HeaderSearchButton]) reste, elle, une icône simple et ne consomme pas ce
/// provider.
///
/// Renvoie `null` quand aucun filtre n'est posé. `isKeyword` distingue le
/// mot-clé des filtres de catalogue.
///
/// `resolved` distingue un libellé lisible (nom de source/thème/sujet trouvé,
/// ou mot-clé) d'un repli sur le slug/id brut le temps qu'un provider async se
/// peuple. La pill de la barre affiche toujours `label` (mieux vaut un slug
/// qu'une icône neutre alors qu'un filtre est actif) ; l'état vide de
/// `flaner_screen` n'affiche que les libellés `resolved` et garde sinon son
/// titre générique.
///
/// Le suffixe « · toutes sources » (recherche élargie) n'apparaît PAS ici : la
/// pill est persistante, la précision n'a de sens que juste après avoir
/// lancé/élargi la recherche — elle vit dans le bandeau éphémère de
/// `flaner_screen` (`_SearchNavBanner`).
final activeFilterLabelProvider =
    Provider<({String label, bool isKeyword, bool resolved})?>((ref) {
  final selection = ref.watch(feedFilterSelectionProvider);
  final kind = selection.activeKind;
  if (kind == null) return null;

  switch (kind) {
    case FeedFilterKind.keyword:
      final kw = selection.keyword!.trim();
      return (label: kw, isKeyword: true, resolved: true);
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
