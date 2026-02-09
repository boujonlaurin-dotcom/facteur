import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:facteur/core/services/push_notification_service.dart';

part 'push_notification_provider.g.dart';

@Riverpod(keepAlive: true)
PushNotificationService pushNotificationService(
    PushNotificationServiceRef ref) {
  return PushNotificationService();
}
