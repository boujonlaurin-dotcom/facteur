import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/letter.dart';
import '../models/letter_progress.dart';
import '../providers/letters_provider.dart';
import '../widgets/envelope_thumb.dart';
import '../widgets/letter_action_tile.dart';
import '../widgets/letter_completion_overlay.dart';
import '../widgets/palier_toast.dart';

class OpenLetterScreen extends ConsumerStatefulWidget {
  final String letterId;

  const OpenLetterScreen({super.key, required this.letterId});

  @override
  ConsumerState<OpenLetterScreen> createState() => _OpenLetterScreenState();
}

class _OpenLetterScreenState extends ConsumerState<OpenLetterScreen> {
  bool _completionShown = false;
  // Anti-cascade : on snapshot les actions déjà done au premier load pour ne
  // pas afficher de toast pour des paliers déjà acquis avant cette session.
  final Set<String> _seenDoneActionIds = <String>{};
  bool _seenInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(lettersProvider.notifier).refreshLetterStatus(widget.letterId);
    });
  }

  void _maybeShowCompletion(LetterProgressState state) {
    if (_completionShown) return;
    final letter = state.letters
        .where((l) => l.id == widget.letterId)
        .cast<Letter?>()
        .firstOrNull;
    if (letter == null || letter.status != LetterStatus.archived) return;
    _completionShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          transitionDuration: const Duration(milliseconds: 280),
          pageBuilder: (_, __, ___) => LetterCompletionOverlay(
            letter: letter,
            onDismiss: () {},
          ),
        ),
      );
    });
  }

  void _maybeShowPalierToast(LetterProgressState state) {
    final letter = state.letters
        .where((l) => l.id == widget.letterId)
        .cast<Letter?>()
        .firstOrNull;
    if (letter == null) return;

    final doneActions = letter.actions
        .where((a) => a.status == LetterActionStatus.done)
        .toList();

    if (!_seenInitialized) {
      _seenInitialized = true;
      _seenDoneActionIds.addAll(doneActions.map((a) => a.id));
      return;
    }

    final newlyDone =
        doneActions.where((a) => !_seenDoneActionIds.contains(a.id)).toList();
    if (newlyDone.isEmpty) return;
    _seenDoneActionIds.addAll(newlyDone.map((a) => a.id));

    // Anti-cascade : on n'affiche QUE le palier de la dernière action de la
    // rafale. La complétion totale est traitée par _maybeShowCompletion
    // (overlay cachet) — pas de toast en plus dans ce cas.
    if (letter.status == LetterStatus.archived) return;
    final last = newlyDone.last;
    final msg = last.completionPalier;
    if (msg == null || msg.isEmpty) return;
    showPalierToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final state = ref.watch(lettersProvider);

    ref.listen<AsyncValue<LetterProgressState>>(lettersProvider, (_, next) {
      final v = next.valueOrNull;
      if (v == null) return;
      _maybeShowPalierToast(v);
      _maybeShowCompletion(v);
    });

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: state.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
        error: (e, _) => _ErrorView(
          onRetry: () => ref.read(lettersProvider.notifier).refresh(),
        ),
        data: (data) {
          final letter = data.letters
              .where((l) => l.id == widget.letterId)
              .cast<Letter?>()
              .firstOrNull;
          if (letter == null) {
            return const _NotFound();
          }
          return _Body(letter: letter);
        },
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon:
                    Icon(PhosphorIcons.arrowLeft(), color: colors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'Lettre introuvable.',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Impossible de charger cette lettre.',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final Letter letter;

  const _Body({required this.letter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final paragraphs = letter.message
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList(growable: false);

    final doneCount =
        letter.actions.where((a) => a.status == LetterActionStatus.done).length;
    final total = letter.actions.length;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(PhosphorIcons.arrowLeft(),
                        color: colors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Retour',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'MON COURRIER',
                        style: GoogleFonts.courierPrime(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(PhosphorIcons.dotsThreeVertical(),
                        color: colors.textTertiary),
                    onPressed: () {},
                    tooltip: 'Plus',
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _Illustration(colors: colors),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'LETTRE ${letter.letterNum}',
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  letter.title,
                  style: GoogleFonts.fraunces(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    height: 1.12,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...paragraphs.expand(
                  (p) => [
                    Text(
                      p,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        height: 1.55,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
                if (letter.introPalier != null && letter.introPalier!.isNotEmpty) ...[
                  Text(
                    letter.introPalier!,
                    style: GoogleFonts.fraunces(
                      fontSize: 14.5,
                      fontStyle: FontStyle.italic,
                      height: 1.55,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _Signature(letter: letter, colors: colors),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        "PREMIÈRES ACTIONS POUR SE LANCER",
                        style: GoogleFonts.courierPrime(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                    Text(
                      '$doneCount/$total',
                      style: GoogleFonts.courierPrime(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ProgressBar(progress: letter.progress, colors: colors),
                const SizedBox(height: 18),
                ...letter.actions.map(
                  (a) => LetterActionTile(
                    action: a,
                    onTap: () =>
                        ref.read(lettersProvider.notifier).silentRefresh(),
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Illustration extends StatefulWidget {
  final FacteurColors colors;

  const _Illustration({required this.colors});

  @override
  State<_Illustration> createState() => _IllustrationState();
}

class _IllustrationState extends State<_Illustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.4, -0.4),
          radius: 1.0,
          colors: [
            widget.colors.primary.withOpacity(0.06),
            Colors.transparent,
          ],
          stops: const [0, 0.6],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF8F0DD),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 46,
            right: 22,
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, child) {
                final t = _drift.value;
                final eased = Curves.easeInOut.transform(t);
                final dy = -5 * eased;
                final rotateDeg = 6 + 4 * eased;
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.rotate(
                    angle: rotateDeg * math.pi / 180,
                    child: child,
                  ),
                );
              },
              child: const EnvelopeThumb(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Signature extends StatelessWidget {
  final Letter letter;
  final FacteurColors colors;

  const _Signature({required this.letter, required this.colors});

  @override
  Widget build(BuildContext context) {
    final started = letter.startedAt;
    final dateStr = started != null ? _formatStarted(started.toLocal()) : null;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF8F0DD),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/notifications/facteur_avatar.png',
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  letter.signature,
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: colors.textSecondary,
                  ),
                ),
                if (dateStr != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'LE FACTEUR · DEPUIS $dateStr',
                    style: GoogleFonts.courierPrime(
                      fontSize: 9.5,
                      letterSpacing: 1,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final FacteurColors colors;

  const _ProgressBar({required this.progress, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 4, color: Colors.black.withOpacity(0.07)),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(height: 4, color: colors.primary),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'janv.',
  'févr.',
  'mars',
  'avril',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _formatStarted(DateTime d) {
  return '${d.day} ${_months[d.month - 1]}';
}
