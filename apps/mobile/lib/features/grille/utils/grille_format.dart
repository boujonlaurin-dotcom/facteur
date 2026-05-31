/// Espace insécable (NBSP) — colle l'unité à son nombre (« 13 h 20 », « 5 min »).
const String nbsp = ' ';

/// Formate un compte à rebours (secondes) en libellé court avec NBSP.
///
/// Exemples (séparateurs = NBSP) : `13 h 20`, `13 h`, `45 min`, `30 s`.
/// - ≥ 1 h : `{h} h {mm}` (les minutes sont omises si nulles → `{h} h`).
/// - ≥ 1 min : `{m} min`.
/// - sinon : `{s} s`.
String formatCountdown(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;

  if (hours > 0) {
    if (minutes == 0) return '$hours${nbsp}h';
    return '$hours${nbsp}h$nbsp$minutes';
  }
  if (minutes > 0) return '$minutes${nbsp}min';
  return '$seconds${nbsp}s';
}
