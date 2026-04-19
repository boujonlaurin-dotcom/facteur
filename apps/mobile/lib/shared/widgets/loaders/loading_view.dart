import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../strings/loader_error_strings.dart';
import 'editorial_loader_card.dart';
import 'facteur_loader.dart';

/// Loading view Facteur — affiche un [FacteurLoader] dès le départ, puis fait
/// apparaître après [revealEditorialAfter] un hint texte + une carte
/// éditoriale rotative pour transformer l'attente en moment agréable.
///
/// - `compact: true` réduit la version aux dimensions adaptées à un Sliver
///   (pas de carte éditoriale, juste le FacteurLoader avec un peu d'espace).
class LoadingView extends StatefulWidget {
  final bool compact;
  final Duration revealEditorialAfter;

  const LoadingView({
    super.key,
    this.compact = false,
    this.revealEditorialAfter = const Duration(seconds: 3),
  });

  @override
  State<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<LoadingView> {
  Timer? _revealTimer;
  bool _showEditorial = false;
  late final String _hint;

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _hint = LoaderStrings.longLoadingHints[
        r.nextInt(LoaderStrings.longLoadingHints.length)];
    if (!widget.compact) {
      _revealTimer = Timer(widget.revealEditorialAfter, () {
        if (mounted) setState(() => _showEditorial = true);
      });
    }
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(FacteurSpacing.space6),
          child: FacteurLoader(width: 72, height: 72),
        ),
      );
    }

    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space6,
          vertical: FacteurSpacing.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FacteurLoader(),
            const SizedBox(height: FacteurSpacing.space4),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _showEditorial ? 1.0 : 0.0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint,
                    textAlign: TextAlign.center,
                    style: FacteurTypography.bodyMedium(colors.textTertiary),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                  if (_showEditorial) const EditorialLoaderCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
