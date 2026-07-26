/// Primitives de matching de la recherche universelle (story 30.1).
///
/// Isolées du widget pour rester testables sans pompe à widgets : la sheet ne
/// fait qu'appeler [rankMatches] sur des listes déjà en mémoire (sources,
/// sujets suivis, thèmes) — aucun appel réseau n'est impliqué.
library;

/// Qualité d'un match, de la meilleure à la moins bonne.
///
/// L'ordre de déclaration **est** l'ordre de tri (`index` croissant = meilleur
/// match), c'est ce qui pilote le classement dans [rankMatches].
enum MatchQuality {
  /// Libellé identique à la requête (aux accents/casse près).
  exact,

  /// Le libellé commence par la requête (« mediap » → « Mediapart »).
  prefix,

  /// Un mot du libellé commence par la requête (« monde » → « Le Monde »).
  wordPrefix,

  /// Tolérance aux fautes de frappe : un mot du libellé est à faible distance
  /// de Levenshtein de la requête (« libertaion » → « Libération »). Seuil
  /// borné par la longueur de la requête (cf. [_fuzzyThreshold]).
  fuzzy,

  /// Aucun match.
  none,
}

/// Replie casse et accents FR courants. **Préserve la longueur** (repli
/// caractère par caractère) : les offsets restent valides pour un éventuel
/// surlignage côté UI. Repli de référence partagé (p. ex. importé par
/// `grille_result_view.dart`).
String foldForSearch(String input) {
  const map = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'å': 'a', 'ã': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
    'û': 'u', 'ü': 'u', 'ù': 'u', 'ú': 'u',
    'ç': 'c', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
  };
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final ch = lower[i];
    buf.write(map[ch] ?? ch);
  }
  return buf.toString();
}

/// Vrai si [code] n'est ni une lettre ASCII ni un chiffre — donc une frontière
/// de mot dans un libellé déjà replié (« l'équipe », « France-Info »).
bool _isWordBoundary(int code) {
  const zero = 0x30, nine = 0x39, a = 0x61, z = 0x7a;
  if (code >= a && code <= z) return false;
  if (code >= zero && code <= nine) return false;
  return true;
}

/// Qualité du match de [query] dans [candidate]. Les deux sont repliés ici :
/// les appelants passent des chaînes brutes.
///
/// Une requête vide (ou uniquement des séparateurs) ne matche jamais — sinon
/// tout le catalogue remonterait au premier caractère saisi puis effacé.
MatchQuality matchQuality(String query, String candidate) =>
    qualityOfFolded(foldForSearch(query.trim()), candidate);

/// Variante de [matchQuality] pour un `foldedQuery` **déjà replié**.
///
/// [rankMatches] balaie tout le catalogue avec la même requête : replier
/// celle-ci une fois par candidat (et par alias) revenait à des centaines de
/// `StringBuffer` identiques par frappe.
///
/// Le tier `contains` (sous-chaîne n'importe où) a été **retiré** : c'est lui
/// qui remontait « Isabelle » pour « belle » ou « poubelle » pour « belle ». Ne
/// restent que les frontières de mot (`exact`/`prefix`/`wordPrefix`) et, en
/// dernier recours, un tier `fuzzy` tolérant aux fautes de frappe.
MatchQuality qualityOfFolded(String foldedQuery, String candidate) {
  if (foldedQuery.isEmpty) return MatchQuality.none;
  final c = foldForSearch(candidate.trim());
  if (c.isEmpty) return MatchQuality.none;

  if (c == foldedQuery) return MatchQuality.exact;
  if (c.startsWith(foldedQuery)) return MatchQuality.prefix;

  // Frontière de mot : une occurrence précédée d'un séparateur → wordPrefix.
  var from = 0;
  while (true) {
    final i = c.indexOf(foldedQuery, from);
    if (i < 0) break;
    // i == 0 est déjà couvert par `startsWith` ci-dessus.
    if (_isWordBoundary(c.codeUnitAt(i - 1))) return MatchQuality.wordPrefix;
    from = i + 1;
  }

  // Fuzzy : la requête est comparée **mot à mot** aux mots du candidat, avec un
  // seuil de Levenshtein borné par sa longueur. Rattrape les fautes de frappe
  // (« lemonde » → « Le Monde », « libertaion » → « Libération ») sans rouvrir
  // la porte aux sous-chaînes en milieu de mot.
  final threshold = _fuzzyThreshold(foldedQuery.length);
  if (threshold > 0) {
    for (final word in c.split(_wordSplit)) {
      if (word.isEmpty) continue;
      if (_boundedLevenshtein(foldedQuery, word, threshold) <= threshold) {
        return MatchQuality.fuzzy;
      }
    }
  }
  return MatchQuality.none;
}

/// Séparateur de mots dans un libellé déjà replié (tout ce qui n'est ni lettre
/// ASCII ni chiffre) — même frontière que [_isWordBoundary].
final RegExp _wordSplit = RegExp(r'[^a-z0-9]+');

/// Seuil de distance de Levenshtein toléré selon la longueur de la requête.
///
/// - < 4 caractères → 0 (pas de fuzzy : sur des requêtes courtes une distance
///   de 1 rend presque tout équivalent).
/// - 4-6 caractères → 1.
/// - ≥ 7 caractères → 2.
int _fuzzyThreshold(int queryLen) {
  if (queryLen < 4) return 0;
  if (queryLen <= 6) return 1;
  return 2;
}

/// Distance de Levenshtein entre [a] et [b], **plafonnée** : renvoie
/// `threshold + 1` dès qu'on est sûr de dépasser [threshold] (early-exit sur
/// l'écart de longueur, puis sur le minimum de chaque ligne). Itératif à deux
/// lignes — coût négligeable sur des listes locales.
int _boundedLevenshtein(String a, String b, int threshold) {
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > threshold) return threshold + 1;
  if (la == 0) return lb;
  if (lb == 0) return la;

  var prev = List<int>.generate(lb + 1, (j) => j);
  var curr = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= lb; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      var m = del < ins ? del : ins;
      if (sub < m) m = sub;
      curr[j] = m;
      if (m < rowMin) rowMin = m;
    }
    if (rowMin > threshold) return threshold + 1;
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[lb];
}

/// Un candidat retenu par [rankMatches], avec la qualité qui a servi au tri.
class RankedMatch<T> {
  final T item;
  final MatchQuality quality;

  const RankedMatch({required this.item, required this.quality});

  @override
  String toString() => 'RankedMatch($item, ${quality.name})';
}

/// Classe [items] par pertinence vis-à-vis de [query].
///
/// - [label] fournit le libellé principal ; [aliases] des libellés secondaires
///   optionnels (nom canonique d'une entité, domaine d'une source…). La
///   meilleure qualité parmi label + alias est retenue.
/// - Tri : qualité décroissante, puis libellé le plus court (« Le Monde » avant
///   « Le Monde Diplomatique »), puis ordre alphabétique — déterministe, donc
///   pas de scintillement entre deux frappes.
///
/// Le cap d'affichage est appliqué par l'appelant (cf. `SearchSection`), qui a
/// besoin du total non borné pour afficher « voir tout (N) ».
List<RankedMatch<T>> rankMatches<T>(
  String query,
  Iterable<T> items, {
  required String Function(T item) label,
  List<String> Function(T item)? aliases,
}) {
  final foldedQuery = foldForSearch(query.trim());
  if (foldedQuery.isEmpty) return const [];

  // Décoré-trié-dédécoré : le comparateur ne doit ni rappeler `label()` ni
  // reminusculer à chaque comparaison — sur une requête courte (« le », « la »)
  // une grande partie du catalogue matche en `wordPrefix`, soit quelques
  // milliers de comparaisons par frappe.
  final decorated = <({RankedMatch<T> match, String label, String sortKey})>[];
  for (final item in items) {
    final primary = label(item);
    var best = qualityOfFolded(foldedQuery, primary);
    if (best != MatchQuality.exact && aliases != null) {
      for (final alias in aliases(item)) {
        final q = qualityOfFolded(foldedQuery, alias);
        if (q.index < best.index) best = q;
        if (best == MatchQuality.exact) break;
      }
    }
    if (best != MatchQuality.none) {
      decorated.add((
        match: RankedMatch(item: item, quality: best),
        label: primary,
        sortKey: primary.toLowerCase(),
      ));
    }
  }

  decorated.sort((a, b) {
    final byQuality = a.match.quality.index.compareTo(b.match.quality.index);
    if (byQuality != 0) return byQuality;
    final byLength = a.label.length.compareTo(b.label.length);
    if (byLength != 0) return byLength;
    return a.sortKey.compareTo(b.sortKey);
  });

  return [for (final d in decorated) d.match];
}

/// Heuristique « l'utilisateur cherche une source, pas un mot-clé ».
///
/// Vrai pour une URL ou un domaine collé dans le champ (`lemonde.fr`,
/// `https://…`, `www.…`). Utilisé pour remonter la section « Ajouter une
/// source » en tête des résultats : taper un domaine n'a aucun sens comme
/// filtre mot-clé sur les titres d'articles.
bool looksLikeSourceQuery(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return false;
  if (q.startsWith('http://') || q.startsWith('https://')) return true;
  if (q.startsWith('www.')) return true;
  // Un point entouré de caractères de nom de domaine, sans espace : « lemonde.fr ».
  if (q.contains(' ')) return false;
  return RegExp(r'^[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)+$').hasMatch(q);
}
