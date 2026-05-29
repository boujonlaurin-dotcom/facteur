import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';

enum MainBottomNavDestination { essentiel, flaner }

class MainBottomNav extends StatelessWidget {
  final MainBottomNavDestination current;

  const MainBottomNav({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: current.index,
      onTap: (index) {
        final destination = MainBottomNavDestination.values[index];
        switch (destination) {
          case MainBottomNavDestination.essentiel:
            context.go(RoutePaths.fluxContinu);
          case MainBottomNavDestination.flaner:
            context.go(RoutePaths.flaner);
        }
      },
      items: [
        BottomNavigationBarItem(
          icon: Icon(PhosphorIcons.newspaper()),
          activeIcon: Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.fill)),
          label: 'L’Essentiel',
        ),
        BottomNavigationBarItem(
          icon: Icon(PhosphorIcons.compass()),
          activeIcon: Icon(PhosphorIcons.compass(PhosphorIconsStyle.fill)),
          label: 'Flâner',
        ),
      ],
    );
  }
}
