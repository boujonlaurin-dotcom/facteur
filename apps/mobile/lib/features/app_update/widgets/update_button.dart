import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/app_update_provider.dart';
import 'update_bottom_sheet.dart';

/// Update button for the digest header.
/// Shows a download icon with a dot indicator when an update is available.
/// Hidden on non-Android platforms and dev builds.
class UpdateButton extends ConsumerWidget {
  const UpdateButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show on Android release builds
    if (kIsWeb || !Platform.isAndroid) {
      return const SizedBox(width: 48);
    }

    final updateAsync = ref.watch(appUpdateProvider);

    return updateAsync.when(
      data: (info) {
        if (info == null || !info.updateAvailable) {
          return const SizedBox(width: 48);
        }
        return _UpdateIcon(info: info);
      },
      loading: () => const SizedBox(width: 48),
      error: (_, __) => const SizedBox(width: 48),
    );
  }
}

class _UpdateIcon extends StatelessWidget {
  final AppUpdateInfo info;

  const _UpdateIcon({required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(
              PhosphorIcons.arrowCircleDown(PhosphorIconsStyle.regular),
              color: colors.primary,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => UpdateBottomSheet.show(context, info: info),
          ),
          // Red dot indicator
          Positioned(
            top: 0,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
