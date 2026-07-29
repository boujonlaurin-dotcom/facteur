import 'package:facteur/features/sources/utils/publication_frequency.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cadence des cibles d'alerte — le devis de bruit qui a remplacé le gate de
/// rareté de la v1. Miroir de `tests/services/test_alert_cadence.py`, qui reste
/// l'arbitre : les deux doivent lire la même cadence, sinon la fiche promet un
/// rythme que le serveur ne tient pas.
void main() {
  final now = DateTime(2026, 7, 26, 12);
  final month = now.subtract(const Duration(days: 30));

  group('humanizeFrequency', () {
    test('source sans article = peu actif', () {
      expect(humanizeFrequency(0, null, now: now), 'peu actif');
    });

    test('gros volume = moyenne arrondie', () {
      expect(
        humanizeFrequency(600, month, now: now),
        '20 articles par jour en moyenne',
      );
    });

    test('source mensuelle', () {
      expect(
        humanizeFrequency(1, month, now: now),
        'quelques articles par mois',
      );
    });
  });

  group('cadencePerWeek', () {
    test('fenêtre pleine de 30 j par défaut', () {
      expect(cadencePerWeek(30, month, now: now), closeTo(7, 0.001));
    });

    test('source fraîche non sous-estimée par le clamp', () {
      // 3 articles en 2 jours : sans le clamp, la fenêtre de 30 j diluerait le
      // volume et le devis de bruit promettrait le calme.
      expect(
        cadencePerWeek(3, now.subtract(const Duration(days: 2)), now: now),
        greaterThan(7),
      );
    });

    test('sans historique connu, fenêtre pleine de 30 j', () {
      expect(cadencePerWeek(30, null, now: now), closeTo(7, 0.001));
    });
  });

  group('isNoisy', () {
    test('seuil à 3 parutions par semaine', () {
      expect(isNoisy(12, month, now: now), isFalse); // ~2,8 / semaine
      expect(isNoisy(14, month, now: now), isTrue); // ~3,3 / semaine
    });

    test('source muette jamais bruyante', () {
      expect(isNoisy(0, null, now: now), isFalse);
    });
  });

  group('cadencePhrase', () {
    test('adapte son unité au rythme réel', () {
      expect(cadencePhrase(0, month, now: now), 'Publie rarement');
      expect(
        cadencePhrase(1, month, now: now),
        'Publie environ une fois par mois',
      );
      expect(
        cadencePhrase(4, month, now: now),
        'Publie environ une fois par semaine',
      );
      expect(
        cadencePhrase(10, month, now: now),
        'Publie environ 2 fois par semaine',
      );
      expect(
        cadencePhrase(30, month, now: now),
        'Publie environ une fois par jour',
      );
      expect(
        cadencePhrase(150, month, now: now),
        'Publie environ 5 fois par jour',
      );
    });

    test('bascule en « par jour » au-delà du seuil de bruit', () {
      // Passé 3/semaine, un chiffre hebdomadaire ne se visualise plus.
      expect(cadencePhrase(60, month, now: now), contains('par jour'));
    });
  });

  group('variantes « At » — cadence donnée directement', () {
    test('même verdict que les fonctions dérivées du profil', () {
      // Les sujets reçoivent leur cadence déjà calculée du backend : les deux
      // chemins doivent produire exactement la même copy, sinon le devis
      // affiché divergerait de celui qui gouverne les envois.
      for (final articles in [0, 1, 4, 10, 30, 150]) {
        final perWeek = cadencePerWeek(articles, month, now: now);
        expect(cadencePhraseAt(perWeek), cadencePhrase(articles, month, now: now));
        expect(isNoisyAt(perWeek), isNoisy(articles, month, now: now));
        expect(
          expectedAlertsPhraseAt(perWeek),
          expectedAlertsPhrase(articles, month, now: now),
        );
      }
    });
  });

  group('expectedAlertsPhrase', () {
    test('le devis honnête, dans l\'unité qui se lit', () {
      expect(
        expectedAlertsPhrase(12, month, now: now),
        'Environ 3 alertes par semaine',
      );
      expect(
        expectedAlertsPhrase(150, month, now: now),
        'Environ 5 alertes par jour',
      );
    });
  });
}
