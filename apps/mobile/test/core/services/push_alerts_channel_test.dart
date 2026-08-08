import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/core/services/push_notification_service.dart';

void main() {
  group('canal Android des alertes (story 30.5)', () {
    test('le canal sonore porte un ID NEUF', () {
      // Android fige son et importance à la création d'un canal et ignore
      // toute modification ultérieure sur un ID existant. Réutiliser
      // `alerts_channel` laisserait les alertes muettes sur tout le parc
      // installé — d'où le `_v2`. Ce test verrouille l'invariant : si
      // quelqu'un « simplifie » en revenant à l'ancien ID, il casse le son.
      expect(PushNotificationService.alertsChannelId, 'alerts_channel_v2');
      expect(PushNotificationService.legacyAlertsChannelId, 'alerts_channel');
      expect(
        PushNotificationService.alertsChannelId,
        isNot(PushNotificationService.legacyAlertsChannelId),
      );
    });
  });
}
