import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../core/services/push_notification_service.dart';
import '../models/veille_config_dto.dart';
import '../providers/veille_active_config_provider.dart';
import '../providers/veille_repository_provider.dart';
import '../repositories/veille_repository.dart';

class VeilleDashboardScreen extends ConsumerWidget {
  const VeilleDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncConfig = ref.watch(veilleActiveConfigProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2E8D5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2E8D5),
        elevation: 0,
        title: Text(
          'Ma veille',
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2A2419),
          ),
        ),
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(), color: const Color(0xFF2A2419)),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePaths.feed);
            }
          },
        ),
      ),
      body: asyncConfig.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(veilleActiveConfigProvider),
        ),
        data: (cfg) {
          if (cfg == null) {
            // L'utilisateur n'a plus de veille (peut arriver après DELETE).
            // On le redirige vers le flow de configuration.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go(RoutePaths.veilleConfig);
            });
            return const SizedBox.shrink();
          }
          return _DashboardBody(cfg: cfg);
        },
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final VeilleConfigDto cfg;
  const _DashboardBody({required this.cfg});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaused = cfg.status == 'paused';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          cfg.themeLabel,
          style: GoogleFonts.dmSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2A2419),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isPaused ? 'En pause' : _scheduleHuman(cfg),
          style: GoogleFonts.dmSans(
            fontSize: 13,
            color: const Color(0xFF8B7E63),
          ),
        ),
        const SizedBox(height: 24),
        _SectionLabel(label: 'Tes angles (${cfg.topics.length})'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: cfg.topics
              .map((t) => _Chip(label: t.label))
              .toList(growable: false),
        ),
        const SizedBox(height: 24),
        _SectionLabel(label: 'Tes sources (${cfg.sources.length})'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: cfg.sources
              .map((s) => _Chip(label: s.source.name))
              .toList(growable: false),
        ),
        if (!isPaused && cfg.nextScheduledAt != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E1D6)),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.calendar(),
                    size: 18, color: const Color(0xFF8B7E63)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prochaine livraison',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: const Color(0xFF8B7E63),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatNextScheduled(cfg.nextScheduledAt!),
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2A2419),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _PrimaryButton(
          icon: PhosphorIcons.envelope(),
          label: 'Voir l\'historique',
          onTap: () => context.pushNamed(RouteNames.veilleDeliveries),
        ),
        const SizedBox(height: 10),
        _SecondaryButton(
          icon: PhosphorIcons.pencilSimple(),
          label: 'Modifier ma veille',
          onTap: () => context.go(RoutePaths.veilleConfig),
        ),
        const SizedBox(height: 10),
        _SecondaryButton(
          icon: isPaused ? PhosphorIcons.play() : PhosphorIcons.pause(),
          label: isPaused ? 'Reprendre' : 'Mettre en pause',
          onTap: () => _togglePause(context, ref, cfg),
        ),
        const SizedBox(height: 10),
        _DangerButton(
          icon: PhosphorIcons.trash(),
          label: 'Supprimer ma veille',
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _togglePause(
    BuildContext context,
    WidgetRef ref,
    VeilleConfigDto cfg,
  ) async {
    final repo = ref.read(veilleRepositoryProvider);
    final nextStatus = cfg.status == 'paused' ? 'active' : 'paused';
    try {
      final updated = await repo.patchConfig(
        VeilleConfigPatchRequest(status: nextStatus),
      );
      ref
          .read(veilleActiveConfigProvider.notifier)
          .hydrateFromServer(updated);

      // Reschedule / cancel local notif selon l'état.
      final pushService = PushNotificationService();
      if (nextStatus == 'paused') {
        await pushService.cancelVeilleNotification();
      } else if (updated.nextScheduledAt != null) {
        await pushService.scheduleVeilleNotification(
          scheduledAt: updated.nextScheduledAt!.add(const Duration(minutes: 30)),
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextStatus == 'paused' ? 'Veille mise en pause' : 'Veille reprise',
          ),
        ),
      );
    } on VeilleApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur (${e.statusCode ?? '?'}). Réessaie.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ma veille ?'),
        content: const Text(
          'Cette action est définitive. L\'historique des livraisons sera conservé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB73B3B)),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(veilleRepositoryProvider);
    try {
      await repo.deleteConfig();
      await PushNotificationService().cancelVeilleNotification();
      ref
          .read(veilleActiveConfigProvider.notifier)
          .hydrateFromServer(null);
      if (!context.mounted) return;
      context.go(RoutePaths.feed);
    } on VeilleApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur (${e.statusCode ?? '?'}). Réessaie.')),
      );
    }
  }

  static String _scheduleHuman(VeilleConfigDto cfg) {
    final freq = switch (cfg.frequency) {
      'weekly' => 'chaque semaine',
      'biweekly' => 'toutes les 2 semaines',
      'monthly' => 'chaque mois',
      _ => cfg.frequency,
    };
    final dayLabel = cfg.dayOfWeek == null ? null : _dayLabel(cfg.dayOfWeek!);
    if (dayLabel == null) {
      return '$freq · ${cfg.deliveryHour}h';
    }
    return '$freq · $dayLabel · ${cfg.deliveryHour}h';
  }

  static String _dayLabel(int dow) {
    const labels = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];
    if (dow < 0 || dow >= labels.length) return '';
    return labels[dow];
  }

  static String _formatNextScheduled(DateTime d) {
    final local = d.toLocal();
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
    final m = months[local.month - 1];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} $m ${local.year} · $hh:$mm';
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: const Color(0xFF8B7E63),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          color: const Color(0xFF2A2419),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Material(
        color: const Color(0xFF2A2419),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E1D6)),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: const Color(0xFF2A2419)),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF2A2419),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DangerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFFB73B3B), size: 16),
      label: Text(
        label,
        style: GoogleFonts.dmSans(
          color: const Color(0xFFB73B3B),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
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
              'Impossible de charger ta veille.',
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
    );
  }
}
