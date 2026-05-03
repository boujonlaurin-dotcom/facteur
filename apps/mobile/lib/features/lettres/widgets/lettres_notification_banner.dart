import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/letters_provider.dart';
import 'envelope_thumb.dart';

/// Banner inline (feed) — apparait quand une lettre est `active`, masqué sur
/// `/lettres*` et après dismiss session-only (cohérent avec les autres
/// nudges, cf. notification_renudge_banner.dart).
class LettresNotificationBanner extends ConsumerStatefulWidget {
  const LettresNotificationBanner({super.key});

  @override
  ConsumerState<LettresNotificationBanner> createState() =>
      _LettresNotificationBannerState();
}

class _LettresNotificationBannerState
    extends ConsumerState<LettresNotificationBanner>
    with SingleTickerProviderStateMixin {
  bool _dismissedThisSession = false;
  late final AnimationController _wobble;

  @override
  void initState() {
    super.initState();
    _wobble = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) return const SizedBox.shrink();

    final letters = ref.watch(lettersProvider).valueOrNull;
    final active = letters?.activeLetter;
    if (active == null) return const SizedBox.shrink();

    final route = GoRouterState.of(context).matchedLocation;
    if (route.startsWith(RoutePaths.lettres)) return const SizedBox.shrink();

    final colors = context.facteurColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(width: 3, color: colors.primary)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                    AnimatedBuilder(
                      animation: _wobble,
                      builder: (context, child) {
                        // -3..3 deg, -3..0 px translate Y
                        final t = _wobble.value;
                        final eased = Curves.easeInOut.transform(t);
                        final dy = -3 * eased;
                        final rotateDeg = -3 + 6 * eased;
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: Transform.rotate(
                            angle: rotateDeg * math.pi / 180,
                            child: child,
                          ),
                        );
                      },
                      child: const EnvelopeThumb(width: 36, height: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'NOUVELLE ÉTAPE · ${active.letterNum}',
                            style: GoogleFonts.courierPrime(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            active.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: colors.textPrimary,
                            ),
                          ),
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
                  onPressed: () =>
                      setState(() => _dismissedThisSession = true),
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
