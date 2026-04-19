import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/constants.dart';
import 'package:facteur/core/services/posthog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isEnabled reflects PostHogConstants.apiKey presence', () {
    final service = PostHogService();
    expect(service.isEnabled, PostHogConstants.apiKey.isNotEmpty);
  });

  test('identify/capture/reset are no-ops before init (no crash)', () async {
    final service = PostHogService();
    // Must not throw — all calls are guarded by _initialized.
    await service.identify(userId: 'u-1');
    await service.capture(event: 'test', properties: const {'k': 'v'});
    await service.reset();
  });
}
