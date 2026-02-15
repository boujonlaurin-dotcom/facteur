import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../feed/repositories/personalization_repository.dart';

part 'paid_content_provider.g.dart';

@riverpod
class HidePaidContent extends _$HidePaidContent {
  static const String _boxName = 'settings';
  static const String _key = 'hide_paid_content';

  @override
  bool build() {
    if (!Hive.isBoxOpen(_boxName)) {
      throw StateError('Settings box "$_boxName" is not open.');
    }
    final box = Hive.box(_boxName);
    return box.get(_key, defaultValue: true) as bool;
  }

  Future<void> toggle(bool value) async {
    if (!Hive.isBoxOpen(_boxName)) {
      throw StateError('Settings box "$_boxName" is not open.');
    }
    state = value;
    final box = Hive.box(_boxName);
    await box.put(_key, value);

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.togglePaidContent(value);
    } catch (e) {
      // Silent failure - local state is already updated
      print('HidePaidContent.toggle: API sync failed: $e');
    }
  }
}
