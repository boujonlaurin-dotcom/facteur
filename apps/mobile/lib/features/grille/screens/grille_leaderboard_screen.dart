import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../shared/widgets/loaders/editorial_loader_card.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../models/grille_models.dart';
import '../providers/grille_leaderboard_provider.dart';
import '../providers/grille_provider.dart';
import '../utils/grille_share_text.dart';
import '../widgets/g_app_bar.dart';
import '../widgets/grille_button.dart';
import '../widgets/leaderboard_distribution.dart';
import '../widgets/leaderboard_hero.dart';
import '../widgets/leaderboard_podium.dart';

/// Écran Classement du jour (`GClassement`) : hero percentile, podium du
/// quartier, distribution des essais, streak.
class GrilleLeaderboardScreen extends ConsumerStatefulWidget {
  const GrilleLeaderboardScreen({super.key});

  @override
  ConsumerState<GrilleLeaderboardScreen> createState() =>
      _GrilleLeaderboardScreenState();
}

class _GrilleLeaderboardScreenState
    extends ConsumerState<GrilleLeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final numero = ref.read(grilleProvider).valueOrNull?.today.numero;
      ref.read(analyticsServiceProvider).trackGrilleLeaderboardOpened(numero: numero);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final async = ref.watch(grilleLeaderboardProvider);

    return Scaffold(
      backgroundColor: c.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            const GAppBar(showBack: true),
            Expanded(
              child: async.when(
                loading: () => const Center(child: EditorialLoaderCard()),
                error: (e, _) => FriendlyErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(grilleLeaderboardProvider),
                ),
                data: (l) => _buildContent(context, l),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, GrilleLeaderboardResponse l) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
            child: Column(
              children: [
                LeaderboardHero(leaderboard: l),
                const SizedBox(height: 22),
                LeaderboardPodium(quartier: l.quartier),
                const SizedBox(height: 24),
                LeaderboardDistribution(
                  distribution: l.distribution,
                  monScore: l.monScore,
                ),
                const SizedBox(height: 22),
                _StreakStrip(streak: l.streak),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: GrilleButton(
            label: 'Défier un·e ami·e',
            style: GrilleButtonStyle.steel,
            icon: PhosphorIcons.shareNetwork(),
            onPressed: () => _defier(context),
          ),
        ),
      ],
    );
  }

  Future<void> _defier(BuildContext context) async {
    final today = ref.read(grilleProvider).valueOrNull?.today;
    if (today == null) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: buildGrilleShareLink(today)));
    unawaited(ref.read(analyticsServiceProvider).trackGrilleShared(
          numero: today.numero,
          medium: 'lien',
        ));
    messenger.showSnackBar(
      const SnackBar(content: Text('Lien copié — défie un·e ami·e !')),
    );
  }
}

/// Bande de streak (`.gl-streak`) : flamme, compteur, 7 pastilles.
class _StreakStrip extends StatelessWidget {
  const _StreakStrip({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: 0.10),
            ),
            child: Icon(
              PhosphorIcons.fire(PhosphorIconsStyle.fill),
              size: 24,
              color: c.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$streak jours d’affilée',
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'Reviens demain pour tenir la série',
                  style: FacteurTypography.bodySmall(c.textSecondary)
                      .copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 7; i++) ...[
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < streak ? c.primary : Colors.transparent,
                    border: Border.all(
                      color: i < streak ? c.primary : c.border,
                      width: 1.5,
                    ),
                  ),
                ),
                if (i < 6) const SizedBox(width: 5),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
