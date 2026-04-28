import 'package:facteur/core/services/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushNotificationService.buildCopy', () {
    test('variant A returns default copy', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantA,
      );
      expect(copy.title, 'Le facteur est passé !');
      expect(copy.body, "Ton récap du jour t'attend.");
    });

    test('variant B with teaser uses tutoiement + personnification', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teaser: 'Trump',
      );
      expect(copy.title, 'Je suis passé.');
      expect(copy.body, 'À la une : Trump');
    });

    test('variant B without teaser falls back to A', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teaser: '',
      );
      expect(copy.title, 'Le facteur est passé !');
    });

    test('variant B truncates teaser longer than 60 chars', () {
      final teaser = 'A' * 80;
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teaser: teaser,
      );
      // body = "À la une : <57 chars>…"
      expect(copy.body.length, lessThanOrEqualTo('À la une : '.length + 58));
      expect(copy.body, endsWith('…'));
    });

    test('variant C returns calm copy', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantC,
      );
      expect(copy.title, 'Le facteur est passé !');
      expect(copy.body, contains("Belle journée"));
    });
  });
}
