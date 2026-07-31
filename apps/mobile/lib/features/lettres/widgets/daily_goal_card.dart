import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../../gamification/providers/gamification_preference_provider.dart';
import '../../gamification/providers/streak_provider.dart';

/// Carte de réglage de l'objectif quotidien de lectures abouties (story 30.2).
///
/// L'objectif (« lire N articles jusqu'au bout pour valider sa journée ») vivait
/// en constante serveur ; il devient réglable ici (1 → 7, défaut 2), persisté
/// via la colonne profil `daily_goal`. La valeur courante est lue depuis
/// `streakProvider` (source de vérité serveur) ; l'écriture invalide le streak
/// pour resynchroniser toutes les surfaces objectif (toast, anneau, recap).
///
/// Gate : masquée si la gamification est explicitement désactivée (même famille
/// de surfaces objectif). Le curseur applique une valeur optimiste pendant le
/// glissement et persiste sur `onChangeEnd`, avec rollback + SnackBar en échec.
class DailyGoalCard extends ConsumerStatefulWidget {
  const DailyGoalCard({super.key});

  static const int minGoal = 1;
  static const int maxGoal = 7;
  static const int defaultGoal = 2;

  @override
  ConsumerState<DailyGoalCard> createState() => _DailyGoalCardState();
}

class _DailyGoalCardState extends ConsumerState<DailyGoalCard> {
  // Valeur optimiste pendant le drag / la persistance (null = on suit le streak).
  int? _pending;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    // Masquée uniquement si la gamification est explicitement désactivée.
    final gamificationEnabled =
        ref.watch(gamificationPreferenceProvider).valueOrNull;
    if (gamificationEnabled == false) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final serverGoal =
        ref.watch(streakProvider).valueOrNull?.dailyGoal ??
        DailyGoalCard.defaultGoal;
    final value = (_pending ?? serverGoal).clamp(
      DailyGoalCard.minGoal,
      DailyGoalCard.maxGoal,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Objectif quotidien',
                        style: GoogleFonts.fraunces(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Nombre d'articles lus jusqu'au bout pour valider ta "
                        'journée',
                        style: GoogleFonts.dmSans(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _GoalPill(value: value),
              ],
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                activeTrackColor: colors.success,
                inactiveTrackColor: colors.textPrimary.withValues(alpha: 0.12),
                thumbColor: colors.success,
                overlayColor: colors.success.withValues(alpha: 0.16),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 9),
                tickMarkShape: SliderTickMarkShape.noTickMark,
              ),
              child: Slider(
                value: value.toDouble(),
                min: DailyGoalCard.minGoal.toDouble(),
                max: DailyGoalCard.maxGoal.toDouble(),
                divisions: DailyGoalCard.maxGoal - DailyGoalCard.minGoal,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _pending = v.round()),
                onChangeEnd: _saving
                    ? null
                    : (v) => _commit(v.round(), serverGoal),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commit(int picked, int previous) async {
    if (picked == previous) {
      setState(() => _pending = null);
      return;
    }
    setState(() {
      _pending = picked;
      _saving = true;
    });
    try {
      await ref.read(userApiServiceProvider).updateProfile({
        'daily_goal': picked,
      });
      if (!mounted) return;
      // Resynchronise streak (source de la valeur) + toutes les surfaces objectif.
      ref.invalidate(streakProvider);
      setState(() {
        _pending = null;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Rollback optimiste vers la valeur serveur.
      setState(() {
        _pending = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible d'enregistrer l'objectif. Réessaie."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _GoalPill extends StatelessWidget {
  final int value;

  const _GoalPill({required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final label = value == 1 ? '1 article' : '$value articles';
    return Container(
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
          color: colors.success,
        ),
      ),
    );
  }
}
