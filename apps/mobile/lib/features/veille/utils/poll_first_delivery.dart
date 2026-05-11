import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_delivery.dart';
import '../providers/veille_repository_provider.dart';
import '../repositories/veille_repository.dart';

/// Poll `/deliveries/{id}` jusqu'à `succeeded` ou 90 s écoulées. Backoff 2 s
/// pendant les 20 premières secondes (≈ p50 de la génération), puis 5 s.
/// Renvoie `true` si la livraison est `succeeded`, `false` sinon (failed,
/// timeout, ou widget unmount). Affiche un snackbar en cas de timeout/failed.
Future<bool> pollFirstDelivery({
  required BuildContext context,
  required WidgetRef ref,
  required String deliveryId,
  required String onTimeoutMessage,
  String onFailedMessage =
      'La génération a échoué. On retentera à la prochaine livraison.',
}) async {
  const totalBudget = Duration(seconds: 90);
  const fastInterval = Duration(seconds: 2);
  const slowInterval = Duration(seconds: 5);
  const fastWindow = Duration(seconds: 20);

  final repo = ref.read(veilleRepositoryProvider);
  final start = DateTime.now();

  while (true) {
    if (!context.mounted) return false;
    final elapsed = DateTime.now().difference(start);
    if (elapsed >= totalBudget) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(onTimeoutMessage)),
      );
      return false;
    }

    try {
      final delivery = await repo.getDelivery(deliveryId);
      if (!context.mounted) return false;
      if (delivery.generationState == VeilleGenerationState.succeeded) {
        return true;
      }
      if (delivery.generationState == VeilleGenerationState.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(onFailedMessage)),
        );
        return false;
      }
    } on VeilleApiException {
      // Erreur transitoire — on continue à poll, le timeout protégera.
    }

    final next = elapsed < fastWindow ? fastInterval : slowInterval;
    await Future<void>.delayed(next);
    if (!context.mounted) return false;
  }
}
