import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../utils/grille_format.dart';

/// Compte à rebours **live** « Nouveau mot dans {durée} » (`.gd-next`).
///
/// Décrémente chaque seconde et reformate avec NBSP (« 13 h 20 »). La valeur de
/// temps est en ocre, le libellé en gris ; mono, majuscules.
class GrilleCountdown extends StatefulWidget {
  const GrilleCountdown({
    super.key,
    required this.initialSeconds,
    this.fontSize = 12,
    this.iconSize = 14,
  });

  final int initialSeconds;
  final double fontSize;
  final double iconSize;

  @override
  State<GrilleCountdown> createState() => _GrilleCountdownState();
}

class _GrilleCountdownState extends State<GrilleCountdown> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= 0) {
        _timer?.cancel();
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final base = GoogleFonts.courierPrime(
      fontSize: widget.fontSize,
      letterSpacing: 1,
      color: c.textTertiary,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIcons.clock(), size: widget.iconSize, color: c.textTertiary),
        const SizedBox(width: 7),
        Text.rich(
          TextSpan(
            style: base,
            children: [
              const TextSpan(text: 'NOUVEAU MOT DANS '),
              TextSpan(
                text: formatCountdown(_remaining),
                style: base.copyWith(
                  color: c.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
