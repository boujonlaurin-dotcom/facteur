import 'dart:convert';
import 'dart:io';

import 'package:facteur/config/topic_labels.dart';
import 'package:facteur/core/services/widget_service.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests du payload poussé vers le widget d'accueil.
///
/// Le widget est un **miroir de Flâner** : plus de bloc « Essentiel » en tête,
/// une seule source (le buffer feed), un ordre chronologique. Ces tests gardent
/// ce contrat — c'est lui qui a lâché en production (cf.
/// docs/bugs/bug-widget-flaner-android.md).
///
/// `WidgetService.buildWidgetPayload` est pure ; le reste du service écrit dans
/// SharedPreferences via `home_widget`, ce qui demande le platform channel et
/// n'est pas exercé ici. La sérialisation d'un `Content` est donc reproduite
/// par un picker de référence local ([_pickFeedList]).
void main() {
  _namespaceGuardTests();

  group('Feed → forme des lignes du widget', () {
    test('rangs à partir de 1, ordre préservé par le picker', () {
      final items = [
        _content('c1', 'Première'),
        _content('c2', 'Deuxième'),
        _content('c3', 'Troisième'),
      ];
      final picked = _pickFeedList(items);
      expect(picked.map((e) => e['id']), ['c1', 'c2', 'c3']);
      expect(picked.map((e) => e['rank']), [1, 2, 3]);
    });

    test('cap à 80 lignes même sur un flux plus long', () {
      final items = List.generate(120, (i) => _content('c$i', 'T$i'));
      final picked = _pickFeedList(items);
      expect(picked.length, 80);
      expect(picked.last['id'], 'c79');
    });

    test('slug de thème connu → libellé français, sinon vide', () {
      final picked = _pickFeedList([
        _content('c1', 'Tech', topics: ['ai']),
        _content('c2', 'Inconnu', topics: ['totally-unknown-slug']),
        _content('c3', 'Sans topic', topics: []),
      ]);
      expect(picked[0]['topic_label'], topicSlugToLabel['ai']);
      expect(picked[1]['topic_label'], '');
      expect(picked[2]['topic_label'], '');
    });

    test('source + published_at_iso survivent au round-trip JSON', () {
      final picked = _pickFeedList([
        _content('c1', 'Titre', sourceName: 'Le Monde'),
      ]);
      final decoded = jsonDecode(jsonEncode(picked)) as List<dynamic>;
      final first = decoded.first as Map<String, dynamic>;
      expect(first['source_name'], 'Le Monde');
      expect((first['published_at_iso'] as String).endsWith('Z'), isTrue);
    });

    test(
      'une date absente sérialise une chaîne vide, jamais « maintenant »',
      () {
        // Le cœur du bug « articles vieux de plusieurs jours affichés à
        // l'instant » : `Content.publishedAt` retombe sur `DateTime.now()`
        // quand le serveur n'envoie rien. Cette valeur inventée était figée
        // dans le payload et relue des jours plus tard comme si elle était
        // vraie. Le widget doit recevoir une chaîne vide et n'afficher aucune
        // date.
        final undated = Content.fromJson({
          'id': 'c1',
          'title': 'Sans date',
          'url': 'https://example.com/c1',
          'content_type': 'article',
          'source': {'id': 's1', 'name': 'Le Monde', 'type': 'article'},
        });
        expect(undated.publishedAtRaw, isNull);
        expect(_pickFeedList([undated]).single['published_at_iso'], '');
      },
    );

    test('une date présente est bien remontée dans publishedAtRaw', () {
      final dated = Content.fromJson({
        'id': 'c1',
        'title': 'Daté',
        'url': 'https://example.com/c1',
        'content_type': 'article',
        'published_at': '2026-08-01T09:00:00Z',
        'source': {'id': 's1', 'name': 'Le Monde', 'type': 'article'},
      });
      expect(dated.publishedAtRaw, DateTime.utc(2026, 8, 1, 9));
      expect(dated.publishedAt, dated.publishedAtRaw);
    });
  });

  group('buildWidgetPayload — dédup, tri chrono, cap', () {
    Map<String, dynamic> entry(String id, {String? publishedAt, int rank = 0}) {
      return {
        'id': id,
        'rank': rank,
        'topic_id': 't',
        'topic_label': 'Topic',
        'title': 'Title $id',
        'source_name': 'Source',
        'source_logo_path': '',
        'published_at_iso': publishedAt ?? '',
      };
    }

    test('trie du plus récent au plus ancien', () {
      final payload = WidgetService.buildWidgetPayload([
        entry('vieux', publishedAt: '2026-08-01T09:00:00.000Z'),
        entry('recent', publishedAt: '2026-08-11T09:00:00.000Z'),
        entry('moyen', publishedAt: '2026-08-05T09:00:00.000Z'),
      ]);
      expect(payload.map((e) => e['id']), ['recent', 'moyen', 'vieux']);
    });

    test('réindexe les rangs après le tri', () {
      final payload = WidgetService.buildWidgetPayload([
        entry('a', publishedAt: '2026-08-01T09:00:00.000Z', rank: 42),
        entry('b', publishedAt: '2026-08-11T09:00:00.000Z', rank: 7),
      ]);
      expect(payload.map((e) => e['id']), ['b', 'a']);
      expect(payload.map((e) => e['rank']), [1, 2]);
    });

    test(
      'une page fraîche posée devant un vieux buffer ressort dans le bon ordre',
      () {
        // Reproduit `updateWidgetMergingFlux` : 2 lignes fraîches concaténées
        // devant un cache plus ancien. Sans tri, le widget affichait l'ordre
        // d'arrivée réseau et ne ressemblait plus à Flâner dès la première
        // fusion de fond.
        final fresh = [
          entry('f1', publishedAt: '2026-08-11T08:00:00.000Z'),
          entry('f2', publishedAt: '2026-08-09T08:00:00.000Z'),
        ];
        final cached = [
          entry('c1', publishedAt: '2026-08-10T08:00:00.000Z'),
          entry('c2', publishedAt: '2026-08-08T08:00:00.000Z'),
        ];
        final payload = WidgetService.buildWidgetPayload([...fresh, ...cached]);
        expect(payload.map((e) => e['id']), ['f1', 'c1', 'f2', 'c2']);
      },
    );

    test('les entrées sans date sont conservées mais reléguées en fin', () {
      final payload = WidgetService.buildWidgetPayload([
        entry('sans-date'),
        entry('date', publishedAt: '2026-08-01T09:00:00.000Z'),
      ]);
      expect(payload.map((e) => e['id']), ['date', 'sans-date']);
    });

    test('une date illisible est traitée comme absente, sans planter', () {
      final payload = WidgetService.buildWidgetPayload([
        entry('cassee', publishedAt: 'pas-une-date'),
        entry('ok', publishedAt: '2026-08-01T09:00:00.000Z'),
      ]);
      expect(payload.map((e) => e['id']), ['ok', 'cassee']);
    });

    test('déduplique par id en gardant la première occurrence', () {
      final payload = WidgetService.buildWidgetPayload([
        entry('dup', publishedAt: '2026-08-11T09:00:00.000Z'),
        entry('dup', publishedAt: '2026-08-01T09:00:00.000Z'),
        entry('autre', publishedAt: '2026-08-05T09:00:00.000Z'),
      ]);
      expect(payload.map((e) => e['id']), ['dup', 'autre']);
    });

    test('le cap de 80 s\'applique APRÈS le tri', () {
      // Le cap avant tri jetait des articles récents simplement arrivés plus
      // tard dans la liste concaténée.
      final entries = [
        for (var i = 0; i < 100; i++)
          entry('old$i', publishedAt: '2026-01-01T09:00:00.000Z'),
        entry('recent', publishedAt: '2026-08-11T09:00:00.000Z'),
      ];
      final payload = WidgetService.buildWidgetPayload(entries);
      expect(payload.length, 80);
      expect(payload.first['id'], 'recent');
    });

    test('entrée sans id ignorée, liste vide en entrée → vide en sortie', () {
      expect(WidgetService.buildWidgetPayload(const []), isEmpty);
      final payload = WidgetService.buildWidgetPayload([entry(''), entry('a')]);
      expect(payload.map((e) => e['id']), ['a']);
    });

    test('aucune ligne ne porte de marqueur Essentiel', () {
      // Garde de non-régression : le bloc Essentiel figé en tête est la cause
      // racine du « widget qui n'a pas bougé depuis 14 jours ».
      final payload = WidgetService.buildWidgetPayload([
        entry('a', publishedAt: '2026-08-11T09:00:00.000Z'),
      ]);
      expect(payload.single.containsKey('source_kind'), isFalse);
      expect(payload.single.containsKey('is_main'), isFalse);
    });
  });
}

// ──────────────────────────────────────────────────────────────
// Picker de référence — reproduit WidgetService._buildFeedArticleList
// sans les dépendances SharedPreferences / téléchargement de logo.
// ──────────────────────────────────────────────────────────────

const _maxFeedArticles = 80;

List<Map<String, dynamic>> _pickFeedList(List<Content> items) {
  final capped = items.take(_maxFeedArticles).toList();
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < capped.length; i++) {
    final item = capped[i];
    final topicSlug = item.topics.isNotEmpty ? item.topics.first : '';
    final topicLabel = topicSlugToLabel[topicSlug] ?? '';
    result.add({
      'id': item.id,
      'rank': i + 1,
      'topic_id': topicSlug,
      'topic_label': topicLabel,
      'title': item.title,
      'source_name': item.source.name,
      'source_logo_path': '',
      'published_at_iso': item.publishedAtRaw?.toUtc().toIso8601String() ?? '',
    });
  }
  return result;
}

Content _content(
  String id,
  String title, {
  String sourceName = 'Le Monde',
  List<String> topics = const [],
  DateTime? publishedAt,
}) {
  final at = publishedAt ?? DateTime.utc(2026, 5, 6, 9, 0);
  return Content(
    id: id,
    title: title,
    url: 'https://example.com/$id',
    contentType: ContentType.article,
    publishedAt: at,
    publishedAtRaw: at,
    source: Source(
      id: 's1',
      name: sourceName,
      type: SourceType.article,
    ),
    topics: topics,
  );
}

// ──────────────────────────────────────────────────────────────
// Garde anti-régression C1 — noms qualifiés vs namespace Gradle
// ──────────────────────────────────────────────────────────────

/// Le bug d'origine : `HomeWidgetPlugin` résout un `androidName` nu en
/// `"${context.packageName}.$className"`, où `context.packageName` est
/// l'**applicationId** (`com.example.facteur.staging` sur le flavor beta,
/// `facteur.app` sur playstore) — jamais le **namespace** où vivent réellement
/// les receivers. Résultat : `ClassNotFoundException` sur les deux flavors, à
/// chaque appel, avalé par un `catch`. Zéro `ACTION_APPWIDGET_UPDATE` envoyé,
/// « Ajouter un Widget » mort.
///
/// Ce test lit le namespace directement dans `build.gradle.kts` : si quelqu'un
/// le change (ou change l'applicationId en croyant que c'est équivalent), la
/// suite rougit ici au lieu de casser silencieusement en prod.
void _namespaceGuardTests() {
  group('C1 — noms qualifiés alignés sur le namespace Gradle', () {
    late String gradleNamespace;

    setUpAll(() {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final match =
          RegExp(r'namespace\s*=\s*"([^"]+)"').firstMatch(gradle);
      expect(
        match,
        isNotNull,
        reason: 'namespace introuvable dans android/app/build.gradle.kts',
      );
      gradleNamespace = match!.group(1)!;
    });

    test('WidgetService.androidNamespace == namespace de build.gradle.kts', () {
      expect(WidgetService.androidNamespace, gradleNamespace);
    });

    test('le namespace n\'est pas dérivé de l\'applicationId des flavors', () {
      // Les deux flavors ont un applicationId différent du namespace : c'est
      // précisément ce qui rendait la concaténation du plugin invalide.
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationIdSuffix = ".staging"'));
      expect(gradle, contains('applicationId = "facteur.app"'));
      expect(WidgetService.androidNamespace, isNot('facteur.app'));
      expect(
        WidgetService.androidNamespace.endsWith('.staging'),
        isFalse,
      );
    });

    test('les deux receivers du manifest sont couverts', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      for (final receiver in ['FacteurWidgetLight', 'FacteurWidgetDark']) {
        expect(
          manifest,
          contains('android:name=".$receiver"'),
          reason: '$receiver doit rester déclaré dans le manifest',
        );
      }
    });
  });
}
