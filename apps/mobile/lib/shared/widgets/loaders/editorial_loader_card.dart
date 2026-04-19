import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../data/loader_blurbs.dart';

/// Carte qui pioche aléatoirement dans le pool de [loaderBlurbs] et fait
/// tourner les entrées toutes les ~6 secondes avec une transition fade.
///
/// Affichée par [LoadingView] après un délai (chargement prolongé), pour
/// rendre l'attente plus agréable et personnaliser le moment.
class EditorialLoaderCard extends StatefulWidget {
  final Duration rotateEvery;

  const EditorialLoaderCard({
    super.key,
    this.rotateEvery = const Duration(seconds: 6),
  });

  @override
  State<EditorialLoaderCard> createState() => _EditorialLoaderCardState();
}

class _EditorialLoaderCardState extends State<EditorialLoaderCard> {
  final _random = math.Random();
  late LoaderBlurb _current;
  late int _currentIndex;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentIndex = _random.nextInt(loaderBlurbs.length);
    _current = loaderBlurbs[_currentIndex];
    _timer = Timer.periodic(widget.rotateEvery, (_) => _rotate());
  }

  void _rotate() {
    if (!mounted || loaderBlurbs.length < 2) return;
    int next;
    do {
      next = _random.nextInt(loaderBlurbs.length);
    } while (next == _currentIndex);
    setState(() {
      _currentIndex = next;
      _current = loaderBlurbs[next];
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isCitation = _current.kind == LoaderBlurbKind.citation;
    final textStyle = GoogleFonts.fraunces(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: colors.textSecondary,
      height: 1.55,
      fontStyle: isCitation ? FontStyle.italic : FontStyle.normal,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Container(
        key: ValueKey(_currentIndex),
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space4,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color: colors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _current.label.toUpperCase(),
              style: FacteurTypography.stamp(colors.textStamp),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              isCitation ? '« ${_current.text} »' : _current.text,
              style: textStyle,
            ),
            if (_current.attribution != null) ...[
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                '— ${_current.attribution!}',
                style: GoogleFonts.fraunces(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
