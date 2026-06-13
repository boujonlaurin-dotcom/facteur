import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kGrilleIntroSeenKey = 'grille_intro_seen';

/// Vrai si l'utilisateur a déjà vu l'intro « Comment jouer » de La Grille.
/// Une fois vue, elle ne s'affiche plus automatiquement (reste accessible via
/// l'icône « ? » de l'app bar).
final grilleIntroSeenProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kGrilleIntroSeenKey) ?? false;
});

/// Marque l'intro comme vue (persisté dans SharedPreferences).
Future<void> markGrilleIntroSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kGrilleIntroSeenKey, true);
}
