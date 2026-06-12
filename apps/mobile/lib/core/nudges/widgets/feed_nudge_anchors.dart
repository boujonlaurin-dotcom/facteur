import 'package:flutter/widgets.dart';

/// Route-specific anchors avoid duplicate GlobalKeys when the shell keeps both
/// feed branches mounted.
final GlobalKey fluxContinuFirstCardKey = GlobalKey(
  debugLabel: 'fluxContinuFirstCardKey',
);
final GlobalKey flanerFirstCardKey = GlobalKey(
  debugLabel: 'flanerFirstCardKey',
);
