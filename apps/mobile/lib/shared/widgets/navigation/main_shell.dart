import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../features/app_update/providers/app_update_provider.dart';
import '../../../features/feed/widgets/profile_avatar_button.dart';
import '../../../features/gamification/widgets/streak_indicator.dart';
import '../../../widgets/design/facteur_logo.dart';
import 'main_bottom_nav.dart';

/// Shell partagé des deux onglets principaux (L'Essentiel / Flâner).
///
/// C'est le `builder` du `StatefulShellRoute` : il pose un header **fixe** et un
/// footer **fixe** (`MainBottomNav`), et confie le contenu central à
/// [navigationShell] (rendu par [BranchPageView] via le `navigatorContainerBuilder`).
/// Seul ce contenu glisse au changement d'onglet — header et footer restent
/// immobiles.
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.facteurColors.backgroundPrimary,
      // Le contenu passe sous le footer glassmorphique pour que le flou révèle
      // les cartes qui défilent derrière (chaque écran réserve un padding bas).
      extendBody: true,
      bottomNavigationBar: MainBottomNav(
        currentIndex: navigationShell.currentIndex,
        onSelect: (index) {
          if (index == navigationShell.currentIndex) {
            // Re-tap de l'onglet actif → scroll-to-top, sans navigation (donc
            // sans slide). L'écran concerné écoute son trigger.
            final trigger = index == 0
                ? essentielScrollTriggerProvider
                : feedScrollTriggerProvider;
            ref.read(trigger.notifier).state++;
          } else {
            navigationShell.goBranch(index);
          }
        },
      ),
      body: Column(
        children: [
          const _SharedTopHeader(),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// Header partagé fixe : streak (gauche) · logo (centre) · avatar réglages
/// (droite, avec pastille « mise à jour disponible »).
///
/// Repris du header historique de `FluxContinuScreen` afin de garder l'apparence
/// identique tout en le sortant du scroll (il ne défile plus ni ne glisse).
class _SharedTopHeader extends StatelessWidget {
  const _SharedTopHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space3,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const FacteurLogo(size: 22, showIcon: false),
            const Align(
              alignment: Alignment.centerLeft,
              child: StreakIndicator(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Consumer(
                builder: (context, ref, _) {
                  final hasUpdate = ref
                          .watch(appUpdateProvider)
                          .valueOrNull
                          ?.updateAvailable ==
                      true;
                  final settingsButton = ProfileAvatarButton(
                    onTap: () => context.push(RoutePaths.settings),
                  );
                  if (!hasUpdate) return settingsButton;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      settingsButton,
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colors.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.backgroundPrimary,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Conteneur des navigators de branche (le `navigatorContainerBuilder`).
///
/// Héberge les branches dans un [PageView] piloté programmatiquement : le
/// changement d'onglet anime un slide horizontal directionnel (direction
/// implicite via l'index de page), et le swipe utilisateur est désactivé
/// (`NeverScrollableScrollPhysics`) pour ne pas entrer en conflit avec les
/// carrousels horizontaux de Flâner.
class BranchPageView extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  const BranchPageView({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  @override
  State<BranchPageView> createState() => _BranchPageViewState();
}

class _BranchPageViewState extends State<BranchPageView> {
  late final PageController _controller =
      PageController(initialPage: widget.navigationShell.currentIndex);

  @override
  void didUpdateWidget(BranchPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.hasClients) return;
    final target = widget.navigationShell.currentIndex;
    final current = _controller.page?.round() ?? target;
    if (target != current) {
      _controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _controller,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final child in widget.children) _KeepAlive(child: child),
      ],
    );
  }
}

/// Garde le navigator de la branche **inactive** monté dans le [PageView]
/// (sinon perte du scroll et de la pile de navigation au changement d'onglet).
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
