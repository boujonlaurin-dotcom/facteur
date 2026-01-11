import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';

/// Scaffold avec bottom navigation pour les écrans principaux
class ShellScaffold extends StatelessWidget {
  final Widget child;

  const ShellScaffold({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: const _BottomNavBar(),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    if (location.startsWith(RoutePaths.feed)) return 0;
    if (location.startsWith(RoutePaths.saved)) return 1;
    if (location.startsWith(RoutePaths.settings)) return 2;

    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.goNamed(RouteNames.feed);
      case 1:
        context.goNamed(RouteNames.saved);
      case 2:
        context.goNamed(RouteNames.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        border: Border(
          top: BorderSide(
            color: colors.surfaceElevated,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: PhosphorIcons.house(PhosphorIconsStyle.regular),
                activeIcon: PhosphorIcons.house(PhosphorIconsStyle.fill),
                label: 'Feed',
                isSelected: selectedIndex == 0,
                onTap: () => _onItemTapped(context, 0),
              ),
              _NavItem(
                icon: PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.regular),
                activeIcon:
                    PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill),
                label: 'Sauvegardés',
                isSelected: selectedIndex == 1,
                onTap: () => _onItemTapped(context, 1),
              ),
              _NavItem(
                icon: PhosphorIcons.gear(PhosphorIconsStyle.regular),
                activeIcon: PhosphorIcons.gear(PhosphorIconsStyle.fill),
                label: 'Profil',
                isSelected: selectedIndex == 2,
                onTap: () => _onItemTapped(context, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 24,
              color: isSelected ? colors.primary : colors.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: isSelected ? colors.primary : colors.textTertiary,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
