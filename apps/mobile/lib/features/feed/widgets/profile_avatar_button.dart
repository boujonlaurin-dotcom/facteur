import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../settings/providers/user_profile_provider.dart';

/// Round avatar showing the current user's initials.
///
/// Used as the "open settings" affordance in the feed header. Initials are
/// computed from `userProfileProvider.displayName` (max 2 letters, uppercased).
class ProfileAvatarButton extends ConsumerWidget {
  final double size;
  final VoidCallback? onTap;

  const ProfileAvatarButton({
    super.key,
    required VoidCallback this.onTap,
    this.size = 32,
  });

  /// Display-only variant (non-interactive — for cases where the parent
  /// already provides the tap target, e.g. inside a tappable card).
  const ProfileAvatarButton.display({super.key, this.size = 32}) : onTap = null;

  String _computeInitials(String? displayName) {
    final name = (displayName ?? '').trim();
    if (name.isEmpty) return '·';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final profile = ref.watch(userProfileProvider);
    final initials = _computeInitials(profile.displayName);

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
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
