import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../models/veille_delivery.dart';
import '../providers/veille_deliveries_provider.dart';

class VeilleDeliveriesScreen extends ConsumerWidget {
  const VeilleDeliveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncDeliveries = ref.watch(veilleDeliveriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2E8D5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2E8D5),
        elevation: 0,
        title: Text(
          'Historique de ma veille',
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2A2419),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF2A2419)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(veilleDeliveriesProvider),
        child: asyncDeliveries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(veilleDeliveriesProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const _EmptyView();
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _DeliveryListCard(
                delivery: list[i],
                onTap: () {
                  context.pushNamed(
                    RouteNames.veilleDeliveryDetail,
                    pathParameters: {'id': list[i].id},
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DeliveryListCard extends StatelessWidget {
  final VeilleDeliveryListItem delivery;
  final VoidCallback onTap;

  const _DeliveryListCard({required this.delivery, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE6E1D6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTargetDate(delivery.targetDate),
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2A2419),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(delivery),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: const Color(0xFF8B7E63),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIcons.caretRight(),
                size: 16,
                color: const Color(0xFF8B7E63),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(VeilleDeliveryListItem d) {
    switch (d.generationState) {
      case VeilleGenerationState.succeeded:
        return '${d.itemCount} sujet${d.itemCount > 1 ? 's' : ''}';
      case VeilleGenerationState.running:
      case VeilleGenerationState.pending:
        return 'Génération en cours…';
      case VeilleGenerationState.failed:
        return 'Échec — réessai automatique';
    }
  }

  static String _formatTargetDate(DateTime d) {
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView pour permettre le pull-to-refresh même quand vide.
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Column(
            children: [
              Icon(
                PhosphorIcons.envelope(),
                size: 36,
                color: const Color(0xFFB67C2E),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucune livraison pour le moment.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2A2419),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ta première livraison arrivera à la prochaine date programmée.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: const Color(0xFF8B7E63),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Column(
            children: [
              Icon(PhosphorIcons.cloudSlash(), size: 32, color: const Color(0xFFB67C2E)),
              const SizedBox(height: 12),
              Text(
                'Impossible de charger l\'historique.',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0xFF2A2419),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
            ],
          ),
        ),
      ],
    );
  }
}
