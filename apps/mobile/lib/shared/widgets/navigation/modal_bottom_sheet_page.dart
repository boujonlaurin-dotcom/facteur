import 'package:flutter/material.dart';

/// A [Page] that presents [child] as a modal bottom sheet driven by GoRouter.
///
/// `context.push('/settings')` opens the sheet; `context.pop()` closes it.
/// Deep links (e.g. `/settings/sources`) push the sub-route on top of the
/// open sheet.
class ModalBottomSheetPage<T> extends Page<T> {
  final Widget child;
  final bool isScrollControlled;

  const ModalBottomSheetPage({
    required this.child,
    this.isScrollControlled = true,
    super.key,
    super.name,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<T>(
      settings: this,
      builder: (_) => child,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
    );
  }
}
