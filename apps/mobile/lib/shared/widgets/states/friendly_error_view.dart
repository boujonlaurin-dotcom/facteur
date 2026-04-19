import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../strings/loader_error_strings.dart';
import '../buttons/primary_button.dart';

/// Vue d'erreur Facteur — ton chaleureux et contextuel.
///
/// Sélectionne le bon message d'après le type d'erreur (réseau, timeout, 503,
/// générique) et propose un bouton « Réessayer ».
///
/// Pour les erreurs persistantes, préférer [LaurinFallbackView].
class FriendlyErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const FriendlyErrorView({
    super.key,
    required this.error,
    required this.onRetry,
  });

  _ErrorCopy _copyFor(Object error) {
    if (error is TimeoutException) {
      return _ErrorCopy(
        title: FriendlyErrorStrings.timeoutTitle,
        subtitle: FriendlyErrorStrings.timeoutSubtitle,
        icon: PhosphorIcons.hourglassMedium(PhosphorIconsStyle.duotone),
      );
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return _ErrorCopy(
        title: FriendlyErrorStrings.networkTitle,
        subtitle: FriendlyErrorStrings.networkSubtitle,
        icon: PhosphorIcons.wifiSlash(PhosphorIconsStyle.duotone),
      );
    }
    if (msg.contains('503') || msg.contains('service unavailable')) {
      return _ErrorCopy(
        title: FriendlyErrorStrings.serverDownTitle,
        subtitle: FriendlyErrorStrings.serverDownSubtitle,
        icon: PhosphorIcons.cloudSlash(PhosphorIconsStyle.duotone),
      );
    }
    return _ErrorCopy(
      title: FriendlyErrorStrings.genericTitle,
      subtitle: FriendlyErrorStrings.genericSubtitle,
      icon: PhosphorIcons.smileyMeh(PhosphorIconsStyle.duotone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final copy = _copyFor(error);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space4,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                copy.icon,
                size: 56,
                color: colors.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                copy.title,
                textAlign: TextAlign.center,
                style: FacteurTypography.displaySmall(colors.textPrimary),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                copy.subtitle,
                textAlign: TextAlign.center,
                style: FacteurTypography.bodyMedium(colors.textSecondary),
              ),
              const SizedBox(height: FacteurSpacing.space6),
              PrimaryButton(
                label: FriendlyErrorStrings.retryLabel,
                icon: PhosphorIcons.arrowClockwise(PhosphorIconsStyle.bold),
                onPressed: onRetry,
                fullWidth: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorCopy {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ErrorCopy({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
