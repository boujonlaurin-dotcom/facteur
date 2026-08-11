import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde sur les **ressources natives** du widget d'accueil Android.
///
/// Pourquoi des tests Dart qui lisent du XML et du Kotlin : le widget est la
/// seule surface du produit dont le rendu ne dépend d'aucune ligne de Dart
/// exécutée. Renommer un `@+id`, supprimer un layout, changer le nom d'une clé
/// SharedPreferences ou casser le contrat d'URI entre Kotlin et Dart ne fait
/// échouer **aucun** test de la suite mobile — mais vide le widget sur le
/// téléphone. Ces régressions sont exactement celles qui ont été livrées à
/// répétition (cf. docs/bugs/bug-widget-flaner-android.md, D8).
///
/// Ces tests sont volontairement grossiers (présence de chaînes) : ils ne
/// remplacent pas une vérification device, ils empêchent les ruptures muettes.
void main() {
  final layoutDir = Directory('android/app/src/main/res/layout');
  final drawableDir = Directory('android/app/src/main/res/drawable');
  final fontDir = Directory('android/app/src/main/res/font');
  final kotlinDir =
      Directory('android/app/src/main/kotlin/com/example/facteur');

  String layout(String name) =>
      File('${layoutDir.path}/$name.xml').readAsStringSync();
  String kotlin(String name) =>
      File('${kotlinDir.path}/$name.kt').readAsStringSync();

  group('Masthead — logo + wordmark Fraunces', () {
    test('la police Fraunces Bold est embarquée dans les ressources', () {
      expect(
        File('${fontDir.path}/fraunces_bold.ttf').existsSync(),
        isTrue,
        reason: 'res/font/fraunces_bold.ttf est référencée par les layouts du '
            'widget — sans elle, aapt échoue au build.',
      );
    });

    for (final theme in ['light', 'dark']) {
      test('facteur_widget_$theme : wordmark en Fraunces, pas en gras système',
          () {
        final xml = layout('facteur_widget_$theme');
        expect(xml, contains('android:fontFamily="@font/fraunces_bold"'));
        // Le wordmark ne doit pas retomber sur le bold système.
        final wordmarkBlock = xml.substring(
          xml.indexOf('@+id/masthead_wordmark'),
          xml.indexOf('</LinearLayout>', xml.indexOf('@+id/masthead_wordmark')),
        );
        expect(wordmarkBlock, isNot(contains('android:textStyle="bold"')));
      });

      test('facteur_widget_$theme : la marque Facteur remplace la pastille « F »',
          () {
        final xml = layout('facteur_widget_$theme');
        expect(xml, contains('@drawable/ic_facteur_mark_$theme'));
        expect(
          xml,
          isNot(contains('@drawable/widget_masthead_mark_$theme')),
          reason: 'la pastille « F » a été remplacée par le logo produit',
        );
        expect(
          File('${drawableDir.path}/ic_facteur_mark_$theme.xml').existsSync(),
          isTrue,
        );
      });

      test('facteur_widget_$theme : masthead_brand et masthead_refresh sont '
          'des cibles de tap distinctes', () {
        final xml = layout('facteur_widget_$theme');
        expect(xml, contains('@+id/masthead_brand'));
        expect(xml, contains('@+id/masthead_refresh'));
        expect(xml, contains('@+id/masthead_meta'));
      });
    }
  });

  group('Rows — miroir de Flâner', () {
    for (final theme in ['light', 'dark']) {
      test('widget_article_row_$theme : ids consommés par le Kotlin présents',
          () {
        final xml = layout('widget_article_row_$theme');
        for (final id in [
          'row_root',
          'row_title',
          'row_source_logo',
          'row_source_name',
          'row_time',
        ]) {
          expect(xml, contains('@+id/$id'), reason: '$id est bindé en Kotlin');
        }
      });

      test('widget_article_row_$theme : plus de vues Essentiel orphelines', () {
        final xml = layout('widget_article_row_$theme');
        // Ces vues étaient VISIBLE par défaut et pilotées par du Kotlin qui
        // n'existe plus : les laisser ajoutait une ligne vide par article.
        for (final id in ['row_header', 'row_topic', 'row_a_la_une']) {
          expect(xml, isNot(contains('@+id/$id')));
        }
      });
    }
  });

  group('Contrats Kotlin ↔ Dart', () {
    test('le host de refresh est identique des deux côtés', () {
      final host = RegExp(r'const _widgetRefreshHost = .([\w-]+).')
          .firstMatch(File('lib/main.dart').readAsStringSync())
          ?.group(1);
      expect(host, isNotNull, reason: '_widgetRefreshHost introuvable');
      expect(
        kotlin('FacteurWidget'),
        contains('facteur://$host'),
        reason: 'FacteurWidget.REFRESH_URI doit viser le host écouté par '
            'homeWidgetBackgroundCallback, sinon le bouton 🔄 est un no-op',
      );
    });

    test('les clés SharedPreferences correspondent', () {
      final widgetService =
          File('lib/core/services/widget_service.dart').readAsStringSync();
      final kt = kotlin('FacteurWidget');
      for (final key in ['widget_articles_json', 'articles_updated_at']) {
        expect(widgetService, contains("'$key'"));
        expect(kt, contains('"$key"'));
      }
    });

    test('toutes les lignes pointent vers Flâner, jamais vers le digest', () {
      final kt = kotlin('FacteurWidgetService');
      expect(kt, contains('io.supabase.facteur://feed/content/'));
      expect(
        kt,
        isNot(contains('io.supabase.facteur://digest/')),
        reason: 'le widget est un miroir de Flâner : une seule destination',
      );
    });

    test('le bouton refresh n’ouvre plus MainActivity', () {
      final kt = kotlin('FacteurWidget');
      expect(kt, contains('ACTION_REFRESH'));
      expect(kt, contains('PendingIntent.getBroadcast'));
      expect(
        kt,
        isNot(contains('feed?refresh=1')),
        reason: 'le refresh se fait en place, sans passer par un deep link '
            'qui ouvre l’app',
      );
    });
  });

  group('Manifest', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('les deux providers et le service sont déclarés', () {
      expect(manifest, contains('android:name=".FacteurWidgetLight"'));
      expect(manifest, contains('android:name=".FacteurWidgetDark"'));
      expect(manifest, contains('android:name=".FacteurWidgetService"'));
      expect(
        manifest,
        contains('android.permission.BIND_REMOTEVIEWS'),
        reason: 'sans cette permission le launcher refuse le RemoteViewsService',
      );
    });

    test('les trampolines Glance restent retirées (crash FLUTTER-1D)', () {
      expect(manifest, contains('ActionTrampolineActivity'));
      expect(manifest, contains('tools:node="remove"'));
    });

    test('le receiver de fond home_widget est déclaré', () {
      // Le manifest de l'AAR home_widget est vide (`<manifest package=... />`),
      // donc rien n'est mergé : sans ces déclarations le PendingIntent du
      // bouton 🔄 ne résout aucun composant et le refresh est un no-op muet.
      expect(
        manifest,
        contains('es.antonborri.home_widget.HomeWidgetBackgroundReceiver'),
      );
      expect(
        manifest,
        contains('es.antonborri.home_widget.HomeWidgetBackgroundService'),
      );
      expect(manifest, contains('android.permission.BIND_JOB_SERVICE'));
    });
  });
}
