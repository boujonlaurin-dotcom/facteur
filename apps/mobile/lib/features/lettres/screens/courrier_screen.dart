import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../models/letter.dart';
import '../models/letter_progress.dart';
import '../providers/letters_provider.dart';
import '../widgets/letter_row.dart';
import '../widgets/lettres_empty_state.dart';

class CourrierScreen extends ConsumerWidget {
  const CourrierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final state = ref.watch(lettersProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: state.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorView(onRetry: () {
          ref.read(lettersProvider.notifier).refresh();
        }),
        data: (data) => _Body(state: data),
      ),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _TopBar(),
          Expanded(
            child: Center(
              child: CircularProgressIndicator(
                color: context.facteurColors.primary,
              ),
            ),
          ),
        ],
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
      child: Column(
        children: [
          const _TopBar(),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Impossible de charger ton courrier.',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final LetterProgressState state;

  const _Body({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    if (state.letters.isEmpty) {
      return const SafeArea(
        child: Column(
          children: [
            _TopBar(),
            Expanded(child: LettresEmptyState()),
          ],
        ),
      );
    }

    final active = state.letters
        .where((l) => l.status == LetterStatus.active)
        .toList(growable: false);
    final upcoming = state.letters
        .where((l) => l.status == LetterStatus.upcoming)
        .toList(growable: false);
    final archived = state.letters
        .where((l) => l.status == LetterStatus.archived)
        .toList(growable: false);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(lettersProvider.notifier).refresh(),
        color: colors.primary,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _TopBar()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 16),
                child: Text(
                  'Ces étapes sont là pour t\'aider à créer l\'app parfaite pour t\'informer au quotidien. Nous ajouterons des étapes petit à petit, pour te pousser pas-à-pas à construire ton front de sources fiables.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    height: 1.45,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (active.isNotEmpty) ...[
                    const _SectionHeader(label: 'EN COURS'),
                    ...active.map((l) => _buildRow(context, l)),
                  ],
                  if (upcoming.isNotEmpty) ...[
                    const _SectionHeader(label: 'À VENIR'),
                    ...upcoming.map((l) => _buildRow(context, l)),
                  ],
                  if (archived.isNotEmpty) ...[
                    const _SectionHeader(label: 'CLASSÉES'),
                    ...archived.map((l) => _buildRow(context, l)),
                  ],
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, Letter letter) {
    return LetterRow(
      letter: letter,
      onTap: () {
        if (letter.status == LetterStatus.upcoming) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cette lettre arrivera après la précédente'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          context.pushNamed(
            RouteNames.openLetter,
            pathParameters: {'id': letter.id},
          );
        }
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        children: [
          IconButton(
            icon: Icon(PhosphorIcons.arrowLeft(), color: colors.textPrimary),
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go(RoutePaths.feed);
              }
            },
            tooltip: 'Retour',
          ),
          Expanded(
            child: Text(
              'Mon courrier (progression)',
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '— $label —',
            style: GoogleFonts.courierPrime(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.black.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }
}
