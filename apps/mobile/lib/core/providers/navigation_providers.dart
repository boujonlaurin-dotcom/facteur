import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to trigger scroll to top on the Digest tab
final digestScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Provider to trigger scroll to top on the Feed tab
final feedScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Provider to trigger scroll to top on the Settings tab
final settingsScrollTriggerProvider = StateProvider<int>((ref) => 0);
