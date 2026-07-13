import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../lettres/widgets/lettres_notification_banner.dart';
import '../models/notif_du_jour_message.dart';
import '../providers/notif_du_jour_day_store.dart';
import '../providers/notif_du_jour_dismissal_store.dart';
import '../providers/notif_du_jour_provider.dart';

/// « Notif du jour » : ligne de notification unique en tête de l'Essentiel.
///
/// Le Facteur reprend la parole : un seul message à la fois (premier de la
/// file [notifDuJourQueueProvider] non consommé), jusqu'à 3 par jour. Tap →
/// action + repli ; croix → repli. Dans les deux cas le message est consommé
/// pour la journée et le suivant apparaît.
///
/// Cède la place aux modales restantes de l'orchestrateur (iOS add-to-home,
/// activation notif) et au bandeau Lettres (traité en PR ultérieure).
class NotifDuJourCard extends ConsumerStatefulWidget {
  const NotifDuJourCard({super.key});

  @override
  ConsumerState<NotifDuJourCard> createState() => _NotifDuJourCardState();
}

/// Durée du repli (hors tokens : medium 250 / slow 400 ne matchent pas le hifi).
const _kCollapseDuration = Duration(milliseconds: 300);

class _NotifDuJourCardState extends ConsumerState<NotifDuJourCard> {
  /// Message en cours de repli : reste rendu (replié) pendant l'animation,
  /// la consommation effective (day store) n'arrive qu'à la fin.
  String? _collapsingId;
  bool _pressed = false;

  /// Repli animé puis consommation. [sideEffect] (action CTA / effets du
  /// dismiss) part immédiatement, avant l'animation.
  Future<void> _consume(
    NotifDuJourMessage message, {
    Future<void> Function()? sideEffect,
  }) async {
    if (_collapsingId != null) return;
    unawaited(HapticFeedback.mediumImpact());
    if (sideEffect != null) unawaited(sideEffect());

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      await ref.read(notifDuJourDayStoreProvider.notifier).consume(message.id);
      return;
    }
    setState(() => _collapsingId = message.id);
    await Future<void>.delayed(_kCollapseDuration);
    if (!mounted) return;
    await ref.read(notifDuJourDayStoreProvider.notifier).consume(message.id);
    if (!mounted) return;
    setState(() => _collapsingId = null);
  }

  @override
  Widget build(BuildContext context) {
    // Cède aux modales restantes de l'orchestrateur.
    if (ref.watch(firstImpressionSlotProvider) != FirstImpressionSlot.none) {
      return const SizedBox.shrink();
    }
    // Un seul point de parole en tête de feed : si le bandeau Lettres est
    // affiché cette session, la notif du jour s'efface.
    if (ref.watch(lettresBannerVisibleThisSessionProvider)) {
      return const SizedBox.shrink();
    }

    final day = ref.watch(notifDuJourDayStoreProvider);
    final dismissalLoaded = ref.watch(
      notifDuJourDismissalStoreProvider.select((s) => s.loaded),
    );
    // Anti-flash : rien tant que les deux stores (jour + cooldown) ne sont pas
    // chargés — sinon on flasherait un message en cooldown le temps du disque.
    if (!day.loaded || !dismissalLoaded || day.capReached) {
      return const SizedBox.shrink();
    }

    final queue = ref.watch(notifDuJourQueueProvider);
    final visibleId = _collapsingId ??
        queue.where((id) => !day.consumed.contains(id)).firstOrNull;
    if (visibleId == null) return const SizedBox.shrink();

    final message = buildNotifDuJourMessage(visibleId);
    if (message == null) return const SizedBox.shrink();

    final collapsed = _collapsingId != null;

    // Repli : hauteur (Align heightFactor 0 animé par AnimatedSize) + fondu +
    // translation vers le haut, simultanés sur 300ms.
    return ClipRect(
      child: AnimatedSize(
        duration: _kCollapseDuration,
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: collapsed ? 0 : 1,
          child: AnimatedOpacity(
            duration: _kCollapseDuration,
            opacity: collapsed ? 0 : 1,
            child: AnimatedContainer(
              duration: _kCollapseDuration,
              curve: Curves.easeInOut,
              transform: Matrix4.translationValues(0, collapsed ? -8 : 0, 0),
              child: _buildCard(context, message),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, NotifDuJourMessage message) {
    final colors = context.facteurColors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final (tintBg, tintFg) = _tint(context, message.tint);
    final hasCustomBody = message.customBodyBuilder != null;

    final card = Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 11, 10),
        child: Row(
          crossAxisAlignment: hasCustomBody
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tintBg,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(message.icon, size: 17, color: tintFg),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.title,
                    // Les prompts à corps custom (sondage NPS « bien informé »)
                    // portent une vraie question : 2 lignes pour ne pas la
                    // tronquer. Les autres restent sur 1 ligne.
                    maxLines: hasCustomBody ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (hasCustomBody)
                    message.customBodyBuilder!(
                      context,
                      ref,
                      () => _consume(message),
                    )
                  else if (message.ctaLabel != null)
                    _CtaLink(
                      label: message.ctaLabel!,
                      green: message.ctaIsGreen,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CloseButton(
              // Dismiss (croix) : pose le cooldown durable (~30j) sur ce
              // message en plus de l'effet éventuel `onDismissed`. Le cooldown
              // ne se pose qu'au dismiss, jamais au tap (un tap = intérêt).
              onTap: () => _consume(
                message,
                sideEffect: () async {
                  await ref
                      .read(notifDuJourDismissalStoreProvider.notifier)
                      .recordDismissed(message.id);
                  await message.onDismissed?.call(ref);
                },
              ),
            ),
          ],
        ),
      ),
    );

    // Un rendu custom (mini-form NPS) porte ses propres taps : pas de tap
    // carte global, pour ne pas intercepter les scores.
    if (hasCustomBody) return card;

    return GestureDetector(
      onTapDown: (_) {
        unawaited(HapticFeedback.mediumImpact());
        if (!reduceMotion) setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => _consume(
        message,
        sideEffect: message.onTap == null
            ? null
            : () => message.onTap!(context, ref),
      ),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: FacteurDurations.fast,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.9 : 1,
          duration: FacteurDurations.fast,
          child: card,
        ),
      ),
    );
  }

  /// (fond, icône/texte) par teinte — tokens du thème quand ils matchent,
  /// littéraux hifi sinon.
  (Color, Color) _tint(BuildContext context, NotifTint tint) {
    switch (tint) {
      case NotifTint.ocre:
        return (const Color(0x1AD35400), const Color(0xFFC15A11));
      case NotifTint.green:
        return (const Color(0x1F2E7D32), context.facteurColors.sectionBonnes);
      case NotifTint.steel:
        return (const Color(0x245D6D7E), context.facteurColors.secondary);
    }
  }
}

class _CtaLink extends StatelessWidget {
  const _CtaLink({required this.label, required this.green});

  final String label;
  final bool green;

  @override
  Widget build(BuildContext context) {
    final color =
        green ? context.facteurColors.sectionBonnes : const Color(0xFFC15A11);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Icon(PhosphorIcons.arrowRight(), size: 11, color: color),
        ],
      ),
    );
  }
}


class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0x0F000000),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Icon(
              PhosphorIcons.x(),
              size: 15,
              color: const Color(0xFFB5AC99),
            ),
          ),
        ),
      ),
    );
  }
}

