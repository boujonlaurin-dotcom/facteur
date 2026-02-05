import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facteur/core/ui/notification_service.dart';
import 'package:facteur/core/providers/navigation_providers.dart';
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

class _BottomNavBar extends ConsumerWidget {
  const _BottomNavBar();

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;

    // Tab 0: Essentiel (Digest)
    if (location.startsWith(RoutePaths.digest)) return 0;

    // Tab 1: Explorer (Feed)
    if (location.startsWith(RoutePaths.feed)) return 1;
    // MVP: Progressions tab removed - redirect to feed if accessed
    if (location.startsWith(RoutePaths.progress)) return 1;

    // Tab 2: Paramètres (Settings)
    if (location.startsWith(RoutePaths.settings)) return 2;

    // Default to digest (Essentiel) tab
    return 0;
  }

  void _onItemTapped(
      BuildContext context, WidgetRef ref, int index, int selectedIndex) {
    if (index == selectedIndex) {
      // Already selected: Trigger scroll to top
      HapticFeedback.mediumImpact();
      switch (index) {
        case 0:
          ref.read(digestScrollTriggerProvider.notifier).state++;
        case 1:
          ref.read(feedScrollTriggerProvider.notifier).state++;
        case 2:
          ref.read(settingsScrollTriggerProvider.notifier).state++;
      }
      return;
    }

    // New selection: Haptic feedback and navigation
    HapticFeedback.lightImpact();
    NotificationService.hide();
    switch (index) {
      case 0:
        context.goNamed(RouteNames.digest);
      case 1:
        context.goNamed(RouteNames.feed);
      case 2:
        context.goNamed(RouteNames.settings);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _calculateSelectedIndex(context);
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(
          top: BorderSide(
            color: colors.border.withValues(alpha: 0.5), // Increased visibility
            width: 0.8, // Slightly thicker for definition
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14), // Refined padding
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Tab 0: Essentiel (Digest)
              _NavItem(
                label: 'Essentiel',
                isSelected: selectedIndex == 0,
                onTap: () => _onItemTapped(context, ref, 0, selectedIndex),
              ),
              // Tab 1: Explorer (Feed)
              _NavItem(
                label: 'Explorer',
                isSelected: selectedIndex == 1,
                onTap: () => _onItemTapped(context, ref, 1, selectedIndex),
              ),
              // Tab 2: Paramètres (Settings)
              _NavItem(
                label: 'Paramètres',
                isSelected: selectedIndex == 2,
                onTap: () => _onItemTapped(context, ref, 2, selectedIndex),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90, // Increased hit area
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          // Very subtle primary tint for active item
          color: isSelected
              ? colors.primary.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color:
                        isSelected ? colors.textPrimary : colors.textTertiary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13, // Increased font size
                    letterSpacing: 0.1,
                  ),
            ),
            const SizedBox(height: 6),
            // Dot indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6, // Increased dot size
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colors.primary : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
