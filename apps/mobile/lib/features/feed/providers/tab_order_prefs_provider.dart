/// Ordre unifié des onglets épinglés de Flâner (sujets + sources mélangés).
///
/// Les sujets (custom topics) et les sources sont deux systèmes de favoris
/// distincts côté backend, chacun avec sa propre `position` serveur. Pour
/// permettre un drag interleaved (sujet ↔ source) dans la modal d'épinglage,
/// on stocke ici l'ordre global voulu par l'utilisateur sous forme de clés
/// typées (`"topic:<id>"` / `"source:<id>"`) en SharedPreferences. Au rendu des
/// onglets, [applyOrder] applique cet ordre ; les items absents de la liste
/// (nouvellement épinglés) conservent leur ordre d'origine, en fin.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTabOrderKey = 'pinned_tabs_order_v1';

/// Préfixe de clé d'un sujet épinglé dans l'ordre unifié.
String tabOrderTopicKey(String topicId) => 'topic:$topicId';

/// Préfixe de clé d'une source épinglée dans l'ordre unifié.
String tabOrderSourceKey(String sourceId) => 'source:$sourceId';

/// Trie [items] selon [order] (liste de clés). Les items dont la clé figure
/// dans [order] viennent en premier, dans l'ordre de [order] ; les autres
/// suivent en conservant leur ordre relatif d'entrée (tri stable). Si [order]
/// est vide, [items] est renvoyé tel quel.
List<T> applyOrder<T>(
  List<T> items,
  List<String> order,
  String Function(T) keyOf,
) {
  if (order.isEmpty || items.isEmpty) return items;
  final rank = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  final indexed = <({T item, int i})>[
    for (var i = 0; i < items.length; i++) (item: items[i], i: i),
  ];
  indexed.sort((a, b) {
    final ra = rank[keyOf(a.item)];
    final rb = rank[keyOf(b.item)];
    if (ra != null && rb != null) return ra.compareTo(rb);
    if (ra != null) return -1; // a est ordonné, b ne l'est pas → a d'abord
    if (rb != null) return 1;
    return a.i.compareTo(b.i); // les deux absents → ordre d'origine
  });
  return [for (final e in indexed) e.item];
}

final tabOrderPrefsProvider =
    StateNotifierProvider<TabOrderPrefsNotifier, List<String>>((ref) {
  return TabOrderPrefsNotifier();
});

class TabOrderPrefsNotifier extends StateNotifier<List<String>> {
  TabOrderPrefsNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getStringList(_kTabOrderKey) ?? const [];
    } catch (_) {
      // Pas de prefs disponibles (ex. tests sans mock) → ordre vide.
      state = const [];
    }
  }

  /// Écrit le nouvel ordre global (clés `"topic:<id>"` / `"source:<id>"`).
  Future<void> setOrder(List<String> keys) async {
    state = List.unmodifiable(keys);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kTabOrderKey, keys);
    } catch (_) {
      // best-effort : l'ordre en mémoire reste appliqué pour la session.
    }
  }
}
