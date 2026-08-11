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

  /// Source Kotlin **sans les lignes de commentaire**.
  ///
  /// Ces assertions portent sur ce que le code *fait*, pas sur ce que les
  /// commentaires racontent — et les commentaires de ce widget décrivent
  /// abondamment l'ancien comportement (« il ouvrait auparavant MainActivity
  /// via `feed?refresh=1` »). Un `isNot(contains(...))` sur le fichier brut
  /// matchait donc l'explication du bug au lieu du bug.
  ///
  /// On ne retire que les lignes **entièrement** commentaires (`//`, `/*`,
  /// `*`) : un stripper naïf de `//` couperait aussi les URLs de deep link
  /// (`io.supabase.facteur://…`), que d'autres assertions vérifient.
  String kotlin(String name) {
    final raw = File('${kotlinDir.path}/$name.kt').readAsStringSync();
    return raw
        .split('\n')
        .where((line) {
          final t = line.trimLeft();
          return !t.startsWith('//') &&
              !t.startsWith('*') &&
              !t.startsWith('/*');
        })
        .join('\n');
  }

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

      test('facteur_widget_$theme : le vrai logo de l’app, pas l’icône de notif',
          () {
        final xml = layout('facteur_widget_$theme');
        expect(xml, contains('@drawable/ic_facteur_logo'));
        expect(
          xml,
          isNot(contains('@drawable/widget_masthead_mark_$theme')),
          reason: 'la pastille « F » a été remplacée par le logo produit',
        );
        // `ic_stat_facteur` est l'enveloppe monochrome de la barre de notifs :
        // ce n'est pas le logo du produit, et c'est ce qui avait été embarqué
        // par erreur.
        expect(xml, isNot(contains('ic_stat_facteur')));
        expect(xml, isNot(contains('ic_facteur_mark')));
      });

      test('facteur_widget_$theme : tracking aligné sur le wordmark in-app', () {
        // `FacteurLogo` rend « Facteur » en GoogleFonts.fraunces(w700,
        // letterSpacing: -0.5). Android exprime letterSpacing en em : à 17sp,
        // -0.5px ≈ -0.031em. Sans ça le mot paraissait plus lâche que dans
        // l'app.
        expect(
          layout('facteur_widget_$theme'),
          contains('android:letterSpacing="-0.031"'),
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

  group('Logo — bitmaps exportés pour toutes les densités', () {
    // Le logo officiel est un SVG Canva de 800 Ko (métadonnées C2PA, tracés
    // massifs) : inexploitable en VectorDrawable. Il est donc rastérisé,
    // détouré de son fond parchemin et de son filigrane, et exporté par
    // densité. Ce test garde l'export : un logo manquant sur une densité
    // donnerait un masthead vide sur les téléphones concernés.
    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      test('drawable-$density/ic_facteur_logo.png présent et non vide', () {
        final f = File(
          'android/app/src/main/res/drawable-$density/ic_facteur_logo.png',
        );
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(200));
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

    test('la clé du marqueur « en cours » est la même des deux côtés', () {
      // Si elle diverge, le natif n'entend jamais la fin du rafraîchissement
      // et le masthead reste sur « Mise à jour… » jusqu'à expiration du TTL.
      final ws =
          File('lib/core/services/widget_service.dart').readAsStringSync();
      expect(ws, contains("'widget_refreshing_since'"));
      expect(kotlin('FacteurWidget'), contains('"widget_refreshing_since"'));
    });

    test('l’état « Mise à jour… » expire tout seul', () {
      final kt = kotlin('FacteurWidget');
      expect(kt, contains('REFRESHING_TTL_MS'));
      expect(
        kt,
        contains('isRefreshing'),
        reason: 'l’état doit être dérivé d’un horodatage, pas d’un drapeau '
            'que rien ne remet à false si le refresh n’aboutit pas',
      );
    });

    test('une donnée plus fraîche annule à elle seule l’état « en cours »', () {
      // Le marqueur ne doit pas dépendre du seul effacement par Dart : si la
      // chaîne de fond ne rend jamais la main, le statut restait collé. Une
      // écriture de `articles_updated_at` postérieure au début du
      // rafraîchissement suffit à conclure qu'il a abouti.
      expect(
        kotlin('FacteurWidget'),
        contains('readLongPref(context, UPDATED_AT_KEY) >= since'),
      );
    });

    test('un repaint de sécurité est programmé au tap sur refresh', () {
      // Sans lui, sortir de « Mise à jour… » supposait qu'un repaint arrive de
      // quelque part — au pire l'alarme système, 30 min plus tard.
      final kt = kotlin('FacteurWidget');
      expect(kt, contains('ACTION_SETTLE'));
      expect(kt, contains('scheduleSettle'));
      expect(
        kt,
        contains('AlarmManager.RTC'),
        reason: 'alarme inexacte : `setExact*` exigerait SCHEDULE_EXACT_ALARM',
      );
    });

    test('le refresh immédiat n’est pas expedited', () {
      // `setExpedited()` lève quand le quota ou la config ne s'y prêtent pas —
      // et l'exception ne coûte pas de la latence, elle prive le bouton de
      // tout rafraîchissement.
      expect(
        File('lib/core/services/widget_background_refresh.dart')
            .readAsStringSync(),
        isNot(contains('outOfQuotaPolicy:')),
      );
    });

    test('le refresh immédiat passe par WorkManager, pas par l’isolate '
        'home_widget', () {
      // `HomeWidgetBackgroundService` est un JobIntentService dont
      // `onHandleWork` rend la main avant la fin du callback Dart : y faire du
      // réseau, c'est se faire tuer en plein vol. WorkManager, lui, tient le
      // process jusqu'au bout.
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('requestImmediateRefresh'));
      expect(
        main,
        isNot(contains('WidgetBackgroundRefresh.run()')),
        reason: 'le callback home_widget délègue, il n’exécute pas le refresh',
      );
      final bg = File('lib/core/services/widget_background_refresh.dart')
          .readAsStringSync();
      expect(bg, contains('registerOneOffTask'));
      expect(bg, contains('finishRefresh'));
    });
  });

  group('Horodatage — le widget parle comme Flâner', () {
    // Flâner formate ses dates avec `timeago` en locale `fr_short`, dont les
    // libellés vivent dans `fr_compact_messages.dart`. Le widget ne peut pas
    // appeler `timeago` (c'est du Kotlin) : il en reproduit les seuils et les
    // chaînes. Ce test garde l'alignement — si quelqu'un change un libellé
    // côté app, le widget doit suivre, sinon un même article s'affiche
    // différemment aux deux endroits.
    final kt = kotlin('WidgetRendering');
    final messages =
        File('lib/core/utils/fr_compact_messages.dart').readAsStringSync();

    test('les libellés de l’app se retrouvent tous dans le Kotlin', () {
      for (final label in ['< 1 min', '1 min', 'min', 'h', 'j', 'mo.']) {
        expect(
          messages,
          contains(label),
          reason: 'sanity check : $label doit exister côté app',
        );
        expect(
          kt,
          contains(label),
          reason: 'le widget doit afficher « $label » comme Flâner',
        );
      }
    });

    test('l’échelle maison a bien disparu', () {
      // « à l'instant » / « 45min » n'existaient nulle part dans l'app.
      expect(kt, isNot(contains("à l'instant")));
      expect(kt, isNot(contains('%dmin')));
    });

    test('un article tout juste publié affiche une date, pas du vide', () {
      // Le garde-fou `minutes < 0 -> ""` faisait disparaître la date des
      // articles les plus frais dès que l'horloge du téléphone devançait
      // légèrement le serveur. On borne à zéro au lieu de renvoyer vide.
      expect(kt, contains('coerceAtLeast(0L)'));
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
