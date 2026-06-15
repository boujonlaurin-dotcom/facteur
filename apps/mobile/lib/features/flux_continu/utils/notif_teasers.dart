import '../../digest/models/digest_models.dart';
import '../models/flux_continu_models.dart';

/// Helpers purs (sans Riverpod/Hive) qui dérivent les bullet points des deux
/// notifications locales personnalisées à partir des données déjà chargées par
/// le home (`fluxContinuProvider`).
///
/// - [buildEssentielTeasers] : source = la carte « L'Essentiel du jour »
///   (`GET /api/essentiel`). En mode serein, cet endpoint est déjà filtré aux
///   articles sereins **côté serveur** (`essentiel.py` lit `serein_enabled`),
///   donc utiliser `essentielArticles[].title` satisfait directement l'exigence
///   PO « filtré aux articles sereins, comme dans l'app ».
/// - [buildGoodNewsTeasers] : source = le top 3 des sujets du digest serein
///   (`label`, fallback titre du 1er article du sujet).
///
/// Les deux passent par [sanitizeTeasers] : trim, drop des vides, dedup
/// case-insensitive (1ère occurrence gagne), cap à 3.

/// Top 3 titres de la carte Essentiel, triés par `rank` croissant.
List<String> buildEssentielTeasers(List<EssentielArticle> articles) {
  final sorted = [...articles]..sort((a, b) => a.rank.compareTo(b.rank));
  return sanitizeTeasers(sorted.map((a) => a.title));
}

/// Top 3 labels des sujets du digest serein, triés par `rank` croissant.
/// Fallback sur le titre du 1er article quand le label stocké est vide ; un
/// sujet vide (label vide ET sans article) est ignoré.
List<String> buildGoodNewsTeasers(DigestResponse? serein) {
  if (serein == null) return const [];
  final sorted = [...serein.topics]..sort((a, b) => a.rank.compareTo(b.rank));
  return sanitizeTeasers(
    sorted.map((t) {
      final label = t.label.trim();
      if (label.isNotEmpty) return label;
      return t.articles.isNotEmpty ? t.articles.first.title : '';
    }),
  );
}

/// Normalise une suite de teasers candidats : trim, retrait des chaînes vides,
/// dedup case-insensitive (la 1ère occurrence est conservée), puis cap à 3.
List<String> sanitizeTeasers(Iterable<String> raw) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in raw) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    if (!seen.add(trimmed.toLowerCase())) continue;
    result.add(trimmed);
    if (result.length == 3) break;
  }
  return result;
}
