import '../../feed/models/content_model.dart';
import '../models/flux_continu_models.dart';

/// Un récap par section : libellé + nombre d'articles lus.
typedef SectionRecap = ({String label, int count});

/// Compte les articles lus par section de la Tournée, en suivant la même
/// logique « lu » que [FluxContinuArticleCard] / [EssentielHiFiCard] :
///   - `EssentielArticle.isRead` OU `consumedIds.contains(contentId)`
///   - `DigestItem.isRead` OU `consumedIds.contains(contentId)`
///   - `Content.status == consumed` OU `readingProgress > 0` OU
///     `consumedIds.contains(id)`
///
/// Ne garde que les sections avec `count > 0`, triées par count décroissant.
List<SectionRecap> buildClosingRecap({
  required List<FluxSection> sections,
  required Set<String> consumedIds,
}) {
  final recaps = <SectionRecap>[];
  for (final section in sections) {
    final count = switch (section) {
      EssentielSection(:final articles) => articles
          .where((a) => a.isRead || consumedIds.contains(a.contentId))
          .length,
      DigestTopicSection(:final topics) => topics
          .expand((t) => t.articles)
          .where((a) => a.isRead || consumedIds.contains(a.contentId))
          .length,
      FeedThemeSection(:final items) => items
          .where(
            (c) =>
                c.status == ContentStatus.consumed ||
                c.readingProgress > 0 ||
                consumedIds.contains(c.id),
          )
          .length,
    };
    if (count > 0) {
      recaps.add((label: section.label, count: count));
    }
  }
  recaps.sort((a, b) => b.count.compareTo(a.count));
  return recaps;
}

/// Énumération française **avec articles** des sections lues. Renvoie `null`
/// quand rien n'a été lu (le rendu retombe alors sur `_stepLabel`).
///
/// - 1 : « Tu as lu sur la Tech (4). »
/// - 2 : « Tu as lu sur la Tech (4) et la Politique (2). »
/// - 3+ : virgules + « , et » avant le dernier libellé.
String? formatClosingRecap(List<SectionRecap> recaps) {
  if (recaps.isEmpty) return null;
  final parts = recaps
      .map((r) => '${_labelWithArticle(r.label)} (${r.count})')
      .toList(growable: false);
  return 'Tu as lu sur ${_joinFr(parts)}.';
}

/// Joint des fragments à la française : « a et b » à 2, « a, b, et c » à 3+.
String _joinFr(List<String> parts) {
  if (parts.length == 1) return parts.first;
  if (parts.length == 2) return '${parts[0]} et ${parts[1]}';
  final head = parts.sublist(0, parts.length - 1).join(', ');
  return '$head, et ${parts.last}';
}

/// Petite map curée des libellés connus → forme genrée avec article. Les
/// libellés inconnus (sources, sujets custom) retombent sur le libellé brut
/// **sans article** : jamais de faute, le formatter gère le mélange.
const Map<String, String> _articleLabels = {
  'L’Essentiel du jour': 'l’Essentiel du jour',
  "L'Essentiel du jour": 'l’Essentiel du jour',
  'Actus du jour': 'l’Actu du jour',
  'Actu du jour': 'l’Actu du jour',
  'Bonnes nouvelles': 'les Bonnes nouvelles',
  'Bonnes Nouvelles': 'les Bonnes nouvelles',
  'Tech': 'la Tech',
  'Technologie': 'la Technologie',
  'Politique': 'la Politique',
  'Économie': 'l’Économie',
  'Economie': 'l’Économie',
  'Sciences': 'les Sciences',
  'Science': 'les Sciences',
  'Société': 'la Société',
  'Societe': 'la Société',
  'Environnement': 'l’Environnement',
  'Culture': 'la Culture',
  'Géopolitique': 'la Géopolitique',
  'Geopolitique': 'la Géopolitique',
  'Sport': 'le Sport',
  'Ma veille': 'ta veille',
  'Veille': 'ta veille',
};

String _labelWithArticle(String label) {
  return _articleLabels[label] ?? _articleLabels[label.trim()] ?? label;
}
