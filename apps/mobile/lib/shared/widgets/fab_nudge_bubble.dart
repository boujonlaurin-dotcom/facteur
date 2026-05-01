import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme.dart';

/// Petite bulle "nudge" affichée à gauche d'un FAB pour inviter à l'action.
/// Speech-bubble avec petit triangle pointant vers la droite (le FAB).
///
/// Quand [dismissKey] est fourni, la bulle se masque automatiquement après
/// [autoDismissAfter] (fade-out) et persiste l'état dans SharedPreferences :
/// elle ne réapparaît plus une fois auto-dismissée.
class FabNudgeBubble extends StatefulWidget {
  final String text;
  final double maxWidth;
  final String? dismissKey;
  final Duration autoDismissAfter;

  const FabNudgeBubble({
    super.key,
    required this.text,
    this.maxWidth = 160,
    this.dismissKey,
    this.autoDismissAfter = const Duration(seconds: 7),
  });

  @override
  State<FabNudgeBubble> createState() => _FabNudgeBubbleState();
}

class _FabNudgeBubbleState extends State<FabNudgeBubble> {
  bool _visible = true;
  bool _checked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.dismissKey != null) {
      _checkDismissed();
    } else {
      _checked = true;
      _scheduleDismiss();
    }
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(widget.dismissKey!) ?? false;
    if (!mounted) return;
    setState(() {
      _checked = true;
      _visible = !dismissed;
    });
    if (_visible) _scheduleDismiss();
  }

  void _scheduleDismiss() {
    _timer = Timer(widget.autoDismissAfter, () async {
      if (!mounted) return;
      setState(() => _visible = false);
      if (widget.dismissKey != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(widget.dismissKey!, true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    final colors = context.facteurColors;
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(FacteurRadius.medium),
                    border: Border.all(color: colors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.text,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                          height: 1.25,
                        ),
                  ),
                ),
              ),
              CustomPaint(
                size: const Size(8, 12),
                painter: _BubbleTailPainter(
                  fill: colors.surface,
                  border: colors.border,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color fill;
  final Color border;

  _BubbleTailPainter({required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.border != border;
}
