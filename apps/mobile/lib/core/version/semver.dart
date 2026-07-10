/// Comparaison sémantique de versions `X.Y.Z` (numérique par composant).
///
/// Contrairement à une comparaison lexicographique (`"1.10.0" < "1.9.0"` en
/// texte), on compare composant par composant en entier : `1.10.0 > 1.9.0`.
///
/// Tolérances :
/// - suffixe de build (`1.2.0+8`) et pré-release (`1.2.0-rc1`) ignorés ;
/// - composants manquants traités comme `0` (`1.2` == `1.2.0`) ;
/// - composants en trop ignorés au-delà des trois premiers.
///
/// Renvoie `null` si l'une des deux entrées n'est pas parsable (le caller
/// décide alors de fail-open). Sinon `-1` (a < b), `0` (a == b), `1` (a > b).
int? compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  if (pa == null || pb == null) return null;

  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

/// Parse `X.Y.Z` (avec `X` et `Y` optionnels) en `[major, minor, patch]`.
/// Coupe tout suffixe `+build` ou `-prerelease` avant le parsing.
/// Renvoie `null` si un composant n'est pas un entier.
List<int>? _parse(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Retire suffixes build (`+...`) et pré-release (`-...`).
  var core = trimmed;
  final plus = core.indexOf('+');
  if (plus != -1) core = core.substring(0, plus);
  final dash = core.indexOf('-');
  if (dash != -1) core = core.substring(0, dash);

  final parts = core.split('.');
  final out = <int>[0, 0, 0];
  for (var i = 0; i < parts.length && i < 3; i++) {
    final v = int.tryParse(parts[i].trim());
    if (v == null || v < 0) return null;
    out[i] = v;
  }
  return out;
}
