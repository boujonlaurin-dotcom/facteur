import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/release_notes/models/changelog_entry.dart';
import 'package:facteur/features/release_notes/services/changelog_service.dart';

class _StubAssetBundle extends CachingAssetBundle {
  _StubAssetBundle(this._payload);

  final String _payload;

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(_payload.codeUnits);
    return ByteData.view(bytes.buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    return _payload;
  }
}

const _samplePayload = '''
{
  "unreleased": [],
  "released": [
    {
      "version": "1.2.0",
      "date": "2026-06-09",
      "entries": [
        { "tag": "Perspectives", "summary": "Clustering plus pertinent." }
      ]
    },
    {
      "version": "1.1.0",
      "date": "2026-05-01",
      "entries": [
        { "tag": "Carte", "summary": "Nouvelle vue carte." }
      ]
    },
    {
      "version": "1.0.0",
      "date": "2026-04-01",
      "entries": [
        { "tag": "Quoi de neuf", "summary": "Découvrez ce qui change." }
      ]
    }
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('compareSemver', () {
    test('compares classic semver triples', () {
      expect(compareSemver('1.2.3', '1.2.3'), 0);
      expect(compareSemver('1.2.0', '1.2.1') < 0, isTrue);
      expect(compareSemver('1.3.0', '1.2.9') > 0, isTrue);
      expect(compareSemver('2.0.0', '1.99.99') > 0, isTrue);
    });

    test('strips build suffix (pubspec X.Y.Z+B)', () {
      expect(compareSemver('1.2.3+42', '1.2.3+1'), 0);
      expect(compareSemver('1.2.3+1', '1.2.4') < 0, isTrue);
    });

    test('treats missing segments as 0', () {
      expect(compareSemver('1.2', '1.2.0'), 0);
      expect(compareSemver('1', '1.0.0'), 0);
    });
  });

  group('ChangelogService.loadReleased', () {
    test('parses released entries in file order', () async {
      final service = ChangelogService(bundle: _StubAssetBundle(_samplePayload));
      final released = await service.loadReleased();

      expect(released.map((r) => r.version),
          equals(['1.2.0', '1.1.0', '1.0.0']));
      expect(released.first.entries.single.tag, 'Perspectives');
    });
  });

  group('ChangelogService.unseenReleases', () {
    final service = ChangelogService(bundle: _StubAssetBundle(_samplePayload));

    test('returns empty when lastSeen is null (first launch)', () async {
      final all = await service.loadReleased();
      final result = service.unseenReleases(
        all: all,
        currentVersion: '1.2.0',
        lastSeen: null,
      );
      expect(result, isEmpty);
    });

    test('returns releases strictly between lastSeen and currentVersion',
        () async {
      final all = await service.loadReleased();
      final result = service.unseenReleases(
        all: all,
        currentVersion: '1.2.0',
        lastSeen: '1.0.0',
      );
      expect(result.map((r) => r.version), equals(['1.2.0', '1.1.0']));
    });

    test('caps at currentVersion (no future leaks)', () async {
      final all = await service.loadReleased();
      final result = service.unseenReleases(
        all: all,
        currentVersion: '1.1.0',
        lastSeen: '1.0.0',
      );
      expect(result.map((r) => r.version), equals(['1.1.0']));
    });

    test('returns empty when already up to date', () async {
      final all = await service.loadReleased();
      final result = service.unseenReleases(
        all: all,
        currentVersion: '1.2.0',
        lastSeen: '1.2.0',
      );
      expect(result, isEmpty);
    });
  });

  group('bootstrap + markSeen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
    });

    test('bootstrapIfFirstLaunch stamps current version when key absent',
        () async {
      final service = ChangelogService(bundle: _StubAssetBundle(_samplePayload));
      final stamped = await service.bootstrapIfFirstLaunch('1.2.0');
      expect(stamped, isTrue);
      expect(await service.readLastSeen(), '1.2.0');
    });

    test('bootstrapIfFirstLaunch is a no-op when key already present',
        () async {
      SharedPreferences.setMockInitialValues(
          const {kLastSeenChangelogVersionKey: '1.0.0'});
      final service = ChangelogService(bundle: _StubAssetBundle(_samplePayload));
      final stamped = await service.bootstrapIfFirstLaunch('1.2.0');
      expect(stamped, isFalse);
      expect(await service.readLastSeen(), '1.0.0');
    });

    test('markSeen persists the version', () async {
      final service = ChangelogService(bundle: _StubAssetBundle(_samplePayload));
      await service.markSeen('1.2.0');
      expect(await service.readLastSeen(), '1.2.0');
    });
  });

  test('ChangelogRelease.fromJson roundtrip', () {
    final raw = {
      'version': '2.0.0',
      'date': '2026-12-01',
      'entries': [
        {'tag': 'X', 'summary': 'Y'},
      ],
    };
    final release = ChangelogRelease.fromJson(raw);
    expect(release.version, '2.0.0');
    expect(release.entries.single.tag, 'X');
    expect(release.entries.single.summary, 'Y');
  });

  // ─── Garde-fou sur l'asset réel ─────────────────────────────────────────
  //
  // `assets/changelog.json` a été livré cassé deux fois (dernière : PR #1029,
  // une entrée insérée sans son `},{`, ce qui fusionnait deux entrées). Comme
  // `loadReleased` fait un `json.decode` du document entier et que le provider
  // traite l'erreur comme « liste vide », la panne est **silencieuse** : plus
  // aucune note de version, sans un log. Les tests ci-dessus ne tournaient que
  // sur un payload en dur, donc ne voyaient rien. Ceux-ci lisent le vrai
  // fichier.
  group('assets/changelog.json (fichier réel)', () {
    Map<String, dynamic> decodeAsset() {
      final raw = File('assets/changelog.json').readAsStringSync();
      return json.decode(raw) as Map<String, dynamic>;
    }

    test('est un JSON valide', () {
      expect(decodeAsset, returnsNormally);
    });

    test('chaque entrée a exactement un tag et un summary non vides', () {
      final decoded = decodeAsset();
      final blocks = <String, dynamic>{
        'unreleased': decoded['unreleased'],
        'released': decoded['released'],
      };

      for (final entry in (blocks['unreleased'] as List<dynamic>)) {
        final map = entry as Map<String, dynamic>;
        expect(map.keys.toSet(), {'tag', 'summary'},
            reason: 'entrée unreleased malformée : $map');
        expect((map['tag'] as String).trim(), isNotEmpty);
        expect((map['summary'] as String).trim(), isNotEmpty);
      }

      for (final release in (blocks['released'] as List<dynamic>)) {
        final map = release as Map<String, dynamic>;
        expect(map.containsKey('version'), isTrue);
        for (final entry in (map['entries'] as List<dynamic>)) {
          final e = entry as Map<String, dynamic>;
          expect(e.keys.toSet(), {'tag', 'summary'},
              reason: 'entrée released malformée : $e');
        }
      }
    });

    test("pas d'em-dash dans la copy user-facing", () {
      final raw = File('assets/changelog.json').readAsStringSync();
      expect(raw.contains('\u2014'), isFalse,
          reason: 'le tiret cadratin est proscrit dans la copy user-facing');
    });
  });
}
