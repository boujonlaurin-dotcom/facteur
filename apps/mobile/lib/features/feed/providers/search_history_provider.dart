import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSearchHistoryKey = 'feed_search_history';
const _maxHistorySize = 5;

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  return SearchHistoryNotifier();
});

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_kSearchHistoryKey) ?? [];
    state = history;
  }

  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final updated = [trimmed, ...state.where((s) => s != trimmed)];
    if (updated.length > _maxHistorySize) {
      updated.removeRange(_maxHistorySize, updated.length);
    }
    state = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSearchHistoryKey, updated);
  }

  Future<void> removeSearch(String query) async {
    final updated = state.where((s) => s != query).toList();
    state = updated;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSearchHistoryKey, updated);
  }

  Future<void> clearHistory() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSearchHistoryKey);
  }
}
