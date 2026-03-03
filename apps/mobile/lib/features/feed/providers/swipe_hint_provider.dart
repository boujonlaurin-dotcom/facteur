import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSwipeLeftHintKey = 'hasSeenSwipeLeftHint';

/// Whether the user has seen the swipe-left hint animation.
/// Once seen, the hint never plays again.
final swipeLeftHintSeenProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kSwipeLeftHintKey) ?? false;
});

/// Marks the swipe-left hint as seen (persisted in SharedPreferences).
Future<void> markSwipeLeftHintSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSwipeLeftHintKey, true);
}
