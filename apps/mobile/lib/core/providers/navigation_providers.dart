import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to trigger scroll to top on the Feed tab
final feedScrollTriggerProvider = StateProvider<int>((ref) => 0);
