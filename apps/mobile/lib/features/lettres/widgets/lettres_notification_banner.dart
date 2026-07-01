import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../settings/providers/user_profile_provider.dart';
import '../models/facteur_grade.dart';
import '../providers/letters_provider.dart';
import 'letter_mini_progress.dart';
import 'ring_avatar.dart';

/// Accent chaud « dernière étape » : un doré cire/parchemin cohérent avec la
/// palette postale, distinct du primary (ocre rouge). Signal visuel « tu y es
/// presque » quand il ne reste qu'une action sur la lettre active.
const _kLastStepGold = Color(0xFFD4A24E);

/// Clé de throttle du bandeau : dernier affichage (epoch ms). Suffixe `_v1`
/// cohérent avec les autres prefs (`pinned_tabs_order_v1`).
const _kLastShownKey = 'lettres_banner_last_shown_v1';

/// Fenêtre de throttle : au plus 1 affichage par 7 jours. Un dismiss manuel
/// compte comme un affichage (le timestamp est déjà persisté à l'affichage).
const _kThrottleWindow = Duration(days: 7);

/// Banner inline (feed) — apparait quand une lettre est `active`, masqué sur
/// `/lettres*`, après dismiss session-only (cohérent avec les autres nudges,
/// cf. notification_renudge_banner.dart) et throttlé à 1 affichage / 7 jours
/// (persisté via SharedPreferences).
///
/// Mini-réplique du `ProgressionHeader` : avatar de grade (anneau animé + badge
/// de niveau) + titre de grade + étapes de la lettre en cours.
class LettresNotificationBanner extends ConsumerStatefulWidget {
  const LettresNotificationBanner({super.key});

  @override
  ConsumerState<LettresNotificationBanner> createState() =>
      _LettresNotificationBannerState();
}

class _LettresNotificationBannerState
    extends ConsumerState<LettresNotificationBanner> {
  bool _dismissedThisSession = false;

  // Throttle : tant que les prefs ne sont pas chargées on masque (évite un
  // flash avant décision) ; `_suppressedByThrottle` gate les affichages futurs
  // (< 7j depuis le dernier). `_recordedThisSession` garde-fou anti-écritures
  // répétées à chaque build.
  bool _prefsLoaded = false;
  bool _suppressedByThrottle = false;
  bool _recordedThisSession = false;

  @override
  void initState() {
    super.initState();
    _loadThrottle();
  }

  Future<void> _loadThrottle() async {
    var suppressed = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_kLastShownKey);
      if (lastMs != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        suppressed = DateTime.now().difference(last) < _kThrottleWindow;
      }
    } catch (_) {
      // best-effort : en cas d'échec on n'empêche pas l'affichage.
    }
    if (!mounted) return;
    setState(() {
      _suppressedByThrottle = suppressed;
      _prefsLoaded = true;
    });
  }

  Future<void> _recordShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastShownKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // best-effort
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded || _suppressedByThrottle) return const SizedBox.shrink();
    if (_dismissedThisSession) return const SizedBox.shrink();

    final state = ref.watch(lettersProvider).valueOrNull;
    final active = state?.activeLetter;
    if (active == null) return const SizedBox.shrink();

    final route = GoRouterState.of(context).matchedLocation;
    if (route.startsWith(RoutePaths.lettres)) return const SizedBox.shrink();

    // 1er build réellement visible de la session → persiste l'affichage.
    // Couvre « affiché puis ignoré » ET « affiché puis dismiss ».
    if (!_recordedThisSession) {
      _recordedThisSession = true;
      _recordShown();
    }

    final colors = context.facteurColors;
    final grade = state!.grade;
    final displayName = ref.watch(userProfileProvider).displayName;
    final done = active.doneActionCount;
    final total = active.totalActionCount;
    final lastStep = total > 0 && done == total - 1;
    final accent = lastStep ? _kLastStepGold : colors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(width: 3, color: accent)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.pushNamed(
            RouteNames.openLetter,
            pathParameters: {'id': active.id},
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 36, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    RingAvatar.fromName(
                      displayName,
                      active.progress,
                      level: grade.level,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            grade.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.15,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (total > 0) ...[
                            const SizedBox(height: 7),
                            LetterMiniProgress(
                              progress: active.progress,
                              done: done,
                              total: total,
                              showCount: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      PhosphorIcons.arrowRight(),
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(
                    PhosphorIcons.x(),
                    color: colors.textTertiary,
                  ),
                  onPressed: () {
                    _recordShown();
                    setState(() => _dismissedThisSession = true);
                  },
                  tooltip: 'Masquer',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
