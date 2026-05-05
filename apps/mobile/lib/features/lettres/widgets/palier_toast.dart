import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Toast discret affiché quand un palier vient d'être validé.
///
/// L'appelant garantit l'anti-cascade (un seul toast par rafale d'actions).
void showPalierToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _PalierToast(
      message: message,
      onDismissed: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _PalierToast extends StatefulWidget {
  final String message;
  final VoidCallback onDismissed;

  const _PalierToast({required this.message, required this.onDismissed});

  @override
  State<_PalierToast> createState() => _PalierToastState();
}

class _PalierToastState extends State<_PalierToast>
    with SingleTickerProviderStateMixin {
  static const _fade = Duration(milliseconds: 250);
  static const _hold = Duration(milliseconds: 4000);

  late final AnimationController _ctl;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: _fade);
    _ctl.forward();
    _dismissTimer = Timer(_hold, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctl.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Positioned(
      left: 24,
      right: 24,
      bottom: 32 + MediaQuery.of(context).viewPadding.bottom,
      child: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: _ctl,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(color: colors.primary, width: 3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: GoogleFonts.fraunces(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
