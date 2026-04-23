import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../widgets/tour_page_essentiel.dart';
import '../widgets/tour_page_feed.dart';
import '../widgets/tour_page_perso.dart';

/// Post-onboarding welcome tour : 3 écrans animés présentant Essentiel / Feed /
/// Perso.
///
/// Déclenché par le redirect GoRouter quand `authState.welcomeTourSeen=false`.
/// Couvre :
///   - nouveau user : après la `ConclusionAnimationScreen` qui navigue vers
///     `/digest` → intercepté par le redirect.
///   - user existant (post-merge PR2) : à la 1ʳᵉ relance de l'app, même
///     interception depuis `/digest`.
///
/// Fermeture :
///   - "Passer" (top-right) : marque seen + go /digest
///   - "Commencer" (last page) : marque seen + go /digest?first=true (déclenche
///     le `DigestWelcomeModal` existant).
class WelcomeTourScreen extends ConsumerStatefulWidget {
  const WelcomeTourScreen({super.key});

  @override
  ConsumerState<WelcomeTourScreen> createState() => _WelcomeTourScreenState();
}

class _WelcomeTourScreenState extends ConsumerState<WelcomeTourScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pagesCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool firstDigest}) async {
    await ref.read(authStateProvider.notifier).markWelcomeTourSeen();
    if (!mounted) return;
    final target = firstDigest
        ? '${RoutePaths.digest}?first=true'
        : RoutePaths.digest;
    context.go(target);
  }

  void _next() {
    if (_index < _pagesCount - 1) {
      _controller.nextPage(
        duration: FacteurDurations.medium,
        curve: Curves.easeOut,
      );
    } else {
      _finish(firstDigest: true);
    }
  }

  void _skip() => _finish(firstDigest: false);

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isLast = _index == _pagesCount - 1;

    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: colors.backgroundPrimary,
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(onSkip: _skip),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: const [
                      TourPageEssentiel(),
                      TourPageFeed(),
                      TourPagePerso(),
                    ],
                  ),
                ),
                _Dots(index: _index, count: _pagesCount),
                const SizedBox(height: FacteurSpacing.space6),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space6,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 20),
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.large),
                        ),
                      ),
                      child: Text(
                        isLast ? 'Commencer' : 'Suivant',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space2,
        FacteurSpacing.space2,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: colors.textTertiary,
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space3,
                vertical: FacteurSpacing.space2,
              ),
            ),
            child: const Text(
              'Passer',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: FacteurDurations.fast,
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active
                ? colors.primary
                : colors.textTertiary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
