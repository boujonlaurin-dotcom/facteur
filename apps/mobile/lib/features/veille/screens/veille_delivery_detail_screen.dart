import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/veille_delivery.dart';
import '../providers/veille_deliveries_provider.dart';
import '../widgets/veille_cluster_card.dart';

class VeilleDeliveryDetailScreen extends ConsumerWidget {
  final String deliveryId;
  const VeilleDeliveryDetailScreen({super.key, required this.deliveryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDelivery = ref.watch(veilleDeliveryProvider(deliveryId));

    return Scaffold(
      backgroundColor: const Color(0xFFF2E8D5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2E8D5),
        elevation: 0,
        title: asyncDelivery.maybeWhen(
          data: (d) => Text(
            _formatTargetDate(d.targetDate),
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2A2419),
            ),
          ),
          orElse: () => Text(
            'Livraison',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2A2419),
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2A2419)),
      ),
      body: asyncDelivery.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(veilleDeliveryProvider(deliveryId)),
        ),
        data: (delivery) => _DeliveryBody(
          delivery: delivery,
          onArticleTap: (a) => _openArticle(context, a.url),
        ),
      ),
    );
  }

  Future<void> _openArticle(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir l\'article: $e')),
        );
      }
    }
  }

  String _formatTargetDate(DateTime d) {
    const months = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juill.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    final m = months[d.month - 1];
    return '${d.day} $m ${d.year}';
  }
}

class _DeliveryBody extends StatelessWidget {
  final VeilleDeliveryResponse delivery;
  final void Function(VeilleDeliveryArticle) onArticleTap;
  const _DeliveryBody({
    required this.delivery,
    required this.onArticleTap,
  });

  @override
  Widget build(BuildContext context) {
    if (delivery.generationState == VeilleGenerationState.failed) {
      return _DeliveryFailedView(lastError: delivery.lastError);
    }
    if (delivery.generationState == VeilleGenerationState.running ||
        delivery.generationState == VeilleGenerationState.pending) {
      return const _DeliveryPendingView();
    }
    if (delivery.items.isEmpty) {
      return const _DeliveryEmptyView();
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: delivery.items.length,
      itemBuilder: (context, i) => VeilleClusterCard(
        item: delivery.items[i],
        onArticleTap: onArticleTap,
      ),
    );
  }
}

class _DeliveryPendingView extends StatelessWidget {
  const _DeliveryPendingView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Génération en cours…',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0xFF8B7E63),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryFailedView extends StatelessWidget {
  final String? lastError;
  const _DeliveryFailedView({this.lastError});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.warningCircle(),
              size: 36,
              color: const Color(0xFFB67C2E),
            ),
            const SizedBox(height: 12),
            Text(
              'La livraison a échoué',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2A2419),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Le scanner réessaiera bientôt — pas besoin de relancer la veille.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFF8B7E63),
              ),
            ),
            if (lastError != null) ...[
              const SizedBox(height: 12),
              Text(
                lastError!,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: const Color(0xFFAFA38B),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeliveryEmptyView extends StatelessWidget {
  const _DeliveryEmptyView();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Pas de cluster pour cette livraison.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            color: const Color(0xFF8B7E63),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.cloudSlash(), size: 32, color: const Color(0xFFB67C2E)),
            const SizedBox(height: 12),
            Text(
              'Erreur réseau',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2A2419),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
