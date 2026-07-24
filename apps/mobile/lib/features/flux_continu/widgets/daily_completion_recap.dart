import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/completion_stamp.dart';
import '../../gamification/providers/gamification_preference_provider.dart';
import '../../gamification/providers/streak_provider.dart';

/// Taglines du bloc de clôture. Ton affirmatif — proche de « Tu es à jour » et
/// du tampon « FIN DE TOURNÉE » —, tutoiement, présent, aucun emoji, aucun
/// point d'exclamation.
///
/// Volontairement **sans formulation comparative** (« deux articles lus valent
/// mieux que vingt survolés ») : le survol est le comportement de la grande
/// majorité des ouvertures, une telle phrase ferait honte à l'utilisateur
/// médian.
const List<String> kCompletionTaglines = [
  'Moins d’info, plus de compréhension.',
  'Tu n’as pas tout lu. Tu as bien lu.',
  'Lire jusqu’au bout, c’est déjà comprendre.',
  'Ce que tu retiendras demain, c’est ça.',
  'Le reste attendra. Ça, tu le sais maintenant.',
  'Une lecture finie vaut mieux qu’une pile commencée.',
  'Rien de plus à lire aujourd’hui. C’est le principe.',
];

/// Rotation déterministe (FNV-1a) sur le jour — même mécanisme que la file
/// « Notif du jour », sans son cap ni son cooldown : deux jours consécutifs ne
/// tombent pas sur la même phrase, et un même jour est stable entre rebuilds.
String pickCompletionTagline(DateTime now, {int index = 0}) {
  final epochDay = now.toUtc().millisecondsSinceEpoch ~/ 86400000;
  var hash = 2166136261;
  for (final unit in '$epochDay#$index'.codeUnits) {
    hash = (hash ^ unit) * 16777619 & 0xFFFFFFFF;
  }
  return kCompletionTaglines[hash % kCompletionTaglines.length];
}

/// Constat rétrospectif des lectures abouties du jour, embarqué dans la carte
/// de clôture.
///
/// Trois règlesnon négociables, qui font toute la différence entre un constat et
/// une injonction :
///
/// 1. **Aucune jauge.** Pas de barre, pas d'anneau, pas de « 2/2 », pas de
///    cases à remplir — deux cases à remplir *sont* une jauge.
/// 2. **Zéro lecture aboutie ⇒ le bloc ne se rend pas du tout.** C'est le cas
///    majoritaire. Il n'y a pas d'objectif raté parce que l'objectif n'est
///    jamais affiché comme cible.
/// 3. **Aucun « plus qu'un ! »** à une seule lecture : on énonce ce qui a été
///    fait, jamais ce qui manque.
class DailyCompletionRecap extends ConsumerWidget {
  const DailyCompletionRecap({super.key, this.now});

  /// Injectable pour les tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // L'objectif journalier est de la gamification : il passe par la même gate
    // que la flamme. Le cachet dans le reader, lui, n'est pas gaté — c'est un
    // affordance d'état de lecture, pas une récompense.
    final gamificationOn =
        ref.watch(gamificationPreferenceProvider).valueOrNull ?? false;
    if (!gamificationOn) return const SizedBox.shrink();

    final streak = ref.watch(streakProvider).valueOrNull;
    final completed = streak?.dailyCompleted ?? 0;
    if (completed <= 0) return const SizedBox.shrink();

    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CompletionStamp(),
          const SizedBox(height: 12),
          Text(
            _sentence(completed),
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pickCompletionTagline(now ?? DateTime.now()),
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: colors.textTertiary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// « Un article lu jusqu'au bout aujourd'hui. » / « Deux articles … ».
/// Au-delà de dix on repasse au chiffre, les lettres devenant illisibles.
String _sentence(int count) {
  const words = [
    '',
    'Un',
    'Deux',
    'Trois',
    'Quatre',
    'Cinq',
    'Six',
    'Sept',
    'Huit',
    'Neuf',
    'Dix',
  ];
  final label = count < words.length ? words[count] : '$count';
  final plural = count > 1 ? 's' : '';
  return '$label article$plural lu$plural jusqu’au bout aujourd’hui.';
}
