import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lettres/providers/letters_provider.dart';
import '../../lettres/widgets/ring_avatar.dart';
import '../../settings/providers/user_profile_provider.dart';

/// Initials avatar with optional onboarding progress ring; opens settings.
class ProfileAvatarButton extends ConsumerWidget {
  final VoidCallback? onTap;

  const ProfileAvatarButton({
    super.key,
    required VoidCallback this.onTap,
  });

  const ProfileAvatarButton.display({super.key}) : onTap = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = ref.watch(userProfileProvider).displayName;
    final lettersAsync = ref.watch(lettersProvider);

    final progress = lettersAsync.maybeWhen(
      data: (state) {
        final active = state.activeLetter;
        if (active == null) return null;
        // Force a min visible dash even at 0/N so the ring is perceivable.
        return active.progress < 0.02 ? 0.02 : active.progress;
      },
      orElse: () => null,
    );

    final avatar = RingAvatar.fromName(displayName, progress);

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
