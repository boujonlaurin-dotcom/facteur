import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/feed/widgets/profile_avatar_button.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/gamification/widgets/streak_indicator.dart';
import 'package:facteur/shared/widgets/loaders/loading_view.dart';
import 'package:facteur/widgets/design/facteur_button.dart';
import 'package:facteur/widgets/design/facteur_logo.dart';

/// Rituel matinal « Ton édition vient d'arriver » (Story 28.1).
///
/// Premier open du jour : écran enveloppe affiché **instantanément** (zéro
/// spinner) à partir de l'état déjà préchargé. Quand l'édition du jour est
/// prête, on révèle le sommaire des sections + le CTA. Tap → micro-chargement
/// (LoadingView 2 s) → fondu vers l'Essentiel.
///
/// Si l'édition n'est pas prête après [_maxWait], on file au feed **sans**
/// marquer « vu » (décision PO #4 : le rituel revient au prochain open).
class MorningRitualScreen extends ConsumerStatefulWidget {
  const MorningRitualScreen({super.key});

  @override
  ConsumerState<MorningRitualScreen> createState() =>
      _MorningRitualScreenState();
}

class _MorningRitualScreenState extends ConsumerState<MorningRitualScreen> {
  /// Délai borné d'attente de l'édition avant de filer au feed sans marquer vu.
  static const Duration _maxWait = Duration(seconds: 4);

  /// Durée du micro-chargement (LoadingView) après le tap CTA.
  static const Duration _loaderDuration = Duration(seconds: 2);

  Timer? _waitTimer;
  Timer? _loaderTimer;
  late final DateTime _shownAt;
  bool _opening = false; // cross-fade vers LoadingView en cours
  bool _revealHandled = false; // timer d'attente déjà annulé

  @override
  void initState() {
    super.initState();
    _shownAt = DateTime.now();
    _waitTimer = Timer(_maxWait, _forwardIfNotReady);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(analyticsServiceProvider).trackMorningRitualShown(
            dayKey: TourneeProgressService.dayKey(DateTime.now()),
          ));
    });
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _loaderTimer?.cancel();
    super.dispose();
  }

  void _forwardIfNotReady() {
    if (!mounted || _opening || _revealHandled) return;
    unawaited(ref.read(analyticsServiceProvider).trackMorningRitualSkippedNotReady(
          dayKey: TourneeProgressService.dayKey(DateTime.now()),
        ));
    context.go(RoutePaths.fluxContinu);
  }

  Future<void> _open() async {
    if (_opening) return;
    _waitTimer?.cancel();
    final tournee = ref.read(tourneeProgressServiceProvider);
    await tournee.setMorningRitualShownToday();
    if (!mounted) return;
    unawaited(ref.read(analyticsServiceProvider).trackMorningRitualOpened(
          dayKey: TourneeProgressService.dayKey(DateTime.now()),
          waitedMs: DateTime.now().difference(_shownAt).inMilliseconds,
        ));
    setState(() => _opening = true);
    _loaderTimer = Timer(_loaderDuration, () {
      if (!mounted) return;
      context.go(RoutePaths.fluxContinu);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final fluxState = ref.watch(fluxContinuProvider).valueOrNull;
    final digest = ref.watch(digestProvider).valueOrNull;
    final editionReady = isEditionReady(fluxState, digest);

    // Dès que l'édition est prête, on annule l'attente bornée (pas de forward).
    if (editionReady && !_revealHandled) {
      _revealHandled = true;
      _waitTimer?.cancel();
    }

    final editionDate = digest?.targetDate ?? DateTime.now();
    final entries = fluxState == null
        ? const <String>[]
        : editionSummaryEntries(
            fluxState.sections,
            grilleSlotIndex: fluxState.grilleSlotIndex,
          );

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: Stack(
        children: [
          // Fond vélo estompé (asset existant), discret en bas à droite.
          Positioned(
            right: -24,
            bottom: -12,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.06,
                child: Image.asset(
                  'assets/notifications/facteur_bike.png',
                  width: 240,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 400),
            child: _opening
                ? const LoadingView(
                    key: ValueKey('morning-loader'),
                    revealEditorialAfter: Duration(milliseconds: 300),
                  )
                : _RitualBody(
                    key: const ValueKey('morning-ritual'),
                    dateLabel: formatFrenchLongDate(editionDate),
                    entries: entries,
                    editionReady: editionReady,
                    reduceMotion: reduceMotion,
                    onOpen: _open,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RitualBody extends StatelessWidget {
  final String dateLabel;
  final List<String> entries;
  final bool editionReady;
  final bool reduceMotion;
  final VoidCallback onOpen;

  const _RitualBody({
    super.key,
    required this.dateLabel,
    required this.entries,
    required this.editionReady,
    required this.reduceMotion,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RitualHeader(),
          Expanded(
            child: MorningRitualContent(
              dateLabel: dateLabel,
              entries: entries,
              editionReady: editionReady,
              reduceMotion: reduceMotion,
              onOpen: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

/// Corps du rituel **sans** le header (logo/streak/avatar) — greeting + sommaire
/// + CTA. Provider-free et donc directement testable en widget test, sans avoir
/// à monter les providers du header (streak/profil/lettres).
class MorningRitualContent extends StatelessWidget {
  final String dateLabel;
  final List<String> entries;
  final bool editionReady;
  final bool reduceMotion;
  final VoidCallback onOpen;

  const MorningRitualContent({
    super.key,
    required this.dateLabel,
    required this.entries,
    required this.editionReady,
    required this.reduceMotion,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bonjour.',
            style: FacteurTypography.serifTitle(colors.textPrimary)
                .copyWith(fontSize: 34, height: 1.1),
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            'Ton édition du $dateLabel vient d\'arriver.',
            style: FacteurTypography.bodyLarge(colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space8),
          AnimatedOpacity(
            opacity: editionReady ? 1.0 : 0.0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 500),
            child: IgnorePointer(
              key: const ValueKey('morning-summary-gate'),
              ignoring: !editionReady,
              child: _EditionSummary(entries: entries, onOpen: onOpen),
            ),
          ),
        ],
      ),
    );
  }
}

/// Header léger (mêmes widgets que `_SharedTopHeader` mais décoratif : l'avatar
/// n'ouvre pas les réglages pendant le rituel).
class _RitualHeader extends StatelessWidget {
  const _RitualHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space6,
        vertical: FacteurSpacing.space3,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FacteurLogo(size: 22, showIcon: false),
          Align(
            alignment: Alignment.centerLeft,
            child: StreakIndicator(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ProfileAvatarButton.display(),
          ),
        ],
      ),
    );
  }
}

class _EditionSummary extends StatelessWidget {
  final List<String> entries;
  final VoidCallback onOpen;

  const _EditionSummary({required this.entries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'L\'ESSENTIEL DU JOUR',
          style: FacteurTypography.labelSmall(colors.sectionEssentiel),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            entries.join('   ·   '),
            style: FacteurTypography.bodyMedium(colors.textPrimary),
          ),
        ],
        const SizedBox(height: FacteurSpacing.space2),
        Text(
          'Reçue à 7h00',
          style: FacteurTypography.bodySmall(colors.textTertiary),
        ),
        const SizedBox(height: FacteurSpacing.space8),
        Align(
          alignment: Alignment.centerLeft,
          child: FacteurButton(
            label: 'Ouvrir l\'édition',
            icon: Icons.arrow_forward,
            onPressed: onOpen,
          ),
        ),
      ],
    );
  }
}
