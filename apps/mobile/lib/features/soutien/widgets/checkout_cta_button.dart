import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../core/ui/notification_service.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../providers/checkout_link_provider.dart';

/// CTA « Reçois ton lien … » : envoie le lien de checkout par email puis
/// navigue vers la confirmation « lien envoyé ».
///
/// Depuis une bottom sheet ([popBeforePush]) : on ferme d'abord la sheet puis
/// on pushe l'écran de confirmation sur le navigator root.
class CheckoutCtaButton extends ConsumerWidget {
  const CheckoutCtaButton({
    super.key,
    required this.label,
    this.popBeforePush = false,
  });

  final String label;
  final bool popBeforePush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(checkoutLinkProvider).isLoading;
    return PrimaryButton(
      label: label,
      icon: PhosphorIcons.envelopeSimple(),
      isLoading: isLoading,
      onPressed: () => _send(context, ref),
    );
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final navigator = popBeforePush ? Navigator.of(context) : null;
    try {
      await ref.read(checkoutLinkProvider.notifier).sendLink();
    } catch (e) {
      NotificationService.showError(checkoutErrorMessage(e));
      return;
    }
    navigator?.pop();
    unawaited(router.pushNamed(RouteNames.soutienLinkSent));
  }
}
