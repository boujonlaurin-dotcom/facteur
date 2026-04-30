import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Round filled button (primary) with a Phosphor user icon — opens settings
/// from the feed header.
class ProfileAvatarButton extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;

  const ProfileAvatarButton({
    super.key,
    required VoidCallback this.onTap,
    this.size = 32,
  });

  const ProfileAvatarButton.display({super.key, this.size = 32}) : onTap = null;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final avatar = Icon(
      PhosphorIcons.gear(PhosphorIconsStyle.regular),
      size: size,
      color: colors.textSecondary,
    );

    if (onTap == null) return avatar;

    return Semantics(
      button: true,
      label: 'Réglages',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        child: avatar,
      ),
    );
  }
}
