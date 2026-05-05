import 'package:facteur/core/services/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushNotificationService.buildCopy', () {
    test('variant A returns default copy', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantA,
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, "Ton récap du jour t'attend quand tu veux.");
      expect(copy.bigText, copy.body);
    });

    test('variant B with teasers uses tutoiement + personnification', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: ['Trump'],
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, 'À la une : Trump');
      expect(copy.bigText, "À la une dans l'Essentiel :\n• Trump");
    });

    test('variant B with multiple teasers renders bullet bigText (max 3)', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: ['Trump', 'Climat', 'Marseille', 'Quatrième'],
      );
      expect(copy.body, 'À la une : Trump');
      expect(
        copy.bigText,
        "À la une dans l'Essentiel :\n• Trump\n• Climat\n• Marseille",
      );
    });

    test('variant B without teasers falls back to A', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: const [],
      );
      expect(copy.title, 'Facteur');
    });

    test('variant B truncates first teaser longer than 60 chars', () {
      final teaser = 'A' * 80;
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: [teaser],
      );
      expect(copy.body.length, lessThanOrEqualTo('À la une : '.length + 58));
      expect(copy.body, endsWith('…'));
    });

    test('variant C returns calm copy', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantC,
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, contains("Belle journée"));
    });
  });
}
