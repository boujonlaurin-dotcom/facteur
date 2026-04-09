import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Bandeau discret affiché après un pull-to-refresh, offrant la possibilité
/// d'annuler l'action pendant [autoDismissDuration].
///
/// Story 4.5b — Feed Refresh Viewport-Aware + Undo.
/// Pattern inspiré de [DismissBanner] mais avec une seule action (undo).
class FeedRefreshUndoBanner extends StatefulWidget {
  final VoidCallback onUndo;
  final VoidCallback onAutoResolve;
  final Duration autoDismissDuration;

  const FeedRefreshUndoBanner({
    super.key,
    required this.onUndo,
    required this.onAutoResolve,
    this.autoDismissDuration = const Duration(seconds: 6),
  });

  @override
  State<FeedRefreshUndoBanner> createState() => _FeedRefreshUndoBannerState();
}

class _FeedRefreshUndoBannerState extends State<FeedRefreshUndoBanner>
    with SingleTickerProviderStateMixin {
  Timer? _autoResolveTimer;
  bool _isCollapsed = false;
  // Single-source-of-truth flag: whichever of auto-resolve / manual undo
  // fires first wins, and the other becomes a no-op. Prevents double
  // onAutoResolve callbacks when the user taps Annuler during the
  // auto-dismiss fade-out animation.
  bool _resolved = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
    _autoResolveTimer = Timer(widget.autoDismissDuration, _autoResolve);
  }

  @override
  void dispose() {
    _autoResolveTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _autoResolve() {
    if (!mounted || _resolved) return;
    _resolved = true;
    setState(() => _isCollapsed = true);
    _fadeController.reverse().then((_) {
      if (mounted) widget.onAutoResolve();
    });
  }

  void _handleUndo() {
    if (_resolved) return;
    _resolved = true;
    _autoResolveTimer?.cancel();
    widget.onUndo();
    if (mounted) setState(() => _isCollapsed = true);
    _fadeController.reverse().then((_) {
      if (mounted) widget.onAutoResolve();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCollapsed && !_fadeController.isAnimating) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Semantics(
        label:
            'Feed rafraîchi. Bouton Annuler disponible ${widget.autoDismissDuration.inSeconds} secondes.',
        container: true,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.bold),
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Feed rafraîchi',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: _handleUndo,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIcons.arrowCounterClockwise(
                            PhosphorIconsStyle.bold),
                        size: 14,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Annuler',
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
