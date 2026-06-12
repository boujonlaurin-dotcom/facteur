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

    test('variant B body is the full first title (no clip)', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: ['Trump'],
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, 'Trump');
      expect(
        copy.bigText,
        "À la une dans l'Essentiel :\n• Trump\n"
        "${PushNotificationService.digestCta}",
      );
    });

    test('variant B caps at 2 titles + CTA line in bigText', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: ['Trump', 'Climat', 'Marseille', 'Quatrième'],
      );
      expect(copy.body, 'Trump');
      expect(
        copy.bigText,
        "À la une dans l'Essentiel :\n• Trump\n• Climat\n"
        "Pour le reste, viens faire un tour sur l'app !",
      );
    });

    test('variant B serene swaps header and CTA, keeps the 2 titles', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: ['Trump', 'Climat', 'Marseille'],
        serene: true,
      );
      expect(copy.body, 'Trump');
      expect(
        copy.bigText,
        'Du calme dans ton actu :\n• Trump\n• Climat\n'
        "Le reste t'attend tranquillement dans l'app.",
      );
    });

    test('variant B keeps full title even beyond 60 chars', () {
      final teaser = 'A' * 80;
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: [teaser],
      );
      expect(copy.body, teaser);
      expect(copy.body, isNot(endsWith('…')));
    });

    test('variant B without teasers falls back to A', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantB,
        teasers: const [],
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, "Ton récap du jour t'attend quand tu veux.");
    });

    test('variant C returns calm copy', () {
      final copy = PushNotificationService.buildCopy(
        variant: NotifVariant.variantC,
      );
      expect(copy.title, 'Facteur');
      expect(copy.body, contains("Belle journée"));
    });
  });

  group('PushNotificationService.buildGoodNewsCopy', () {
    test('no teasers falls back to generic good news copy', () {
      final copy = PushNotificationService.buildGoodNewsCopy();
      expect(copy.title, PushNotificationService.goodNewsTitle);
      expect(copy.body, PushNotificationService.goodNewsBody);
      expect(copy.bigText, PushNotificationService.goodNewsBody);
    });

    test('empty teasers list falls back to generic copy', () {
      final copy = PushNotificationService.buildGoodNewsCopy(teasers: const []);
      expect(copy.body, PushNotificationService.goodNewsBody);
    });

    test('teasers render bullet bigText (max 3) + collapsed body', () {
      final copy = PushNotificationService.buildGoodNewsCopy(
        teasers: ['Solidarité', 'Avancée médicale', 'Climat positif', 'Quatrième'],
      );
      expect(copy.title, PushNotificationService.goodNewsTitle);
      expect(copy.body, 'À la une : Solidarité');
      expect(
        copy.bigText,
        'Vos bonnes nouvelles du jour :\n'
        '• Solidarité\n• Avancée médicale\n• Climat positif',
      );
    });

    test('truncates first teaser longer than 60 chars', () {
      final copy = PushNotificationService.buildGoodNewsCopy(
        teasers: ['A' * 80],
      );
      expect(copy.body, endsWith('…'));
      expect(copy.body.length, lessThanOrEqualTo('À la une : '.length + 58));
    });
  });
}
