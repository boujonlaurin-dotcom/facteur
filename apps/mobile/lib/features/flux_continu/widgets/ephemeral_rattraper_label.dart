import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';

/// Clé SharedPreferences : dernier `dayKey` (`YYYY-MM-DD`, frontière 07h30 Paris)
/// où le nudge éphémère « Rattraper ? » a été joué. Gate « au plus 1×/jour ».
const String kRattraperNudgeLastShownPrefsKey =
    'essentiel_rattraper_nudge_last_shown_v1';

/// Nudge **éphémère** « Rattraper ? » posé à droite de l'icône ⏪ de l'en-tête
/// Essentiel quand l'utilisateur a manqué l'édition d'hier.
///
/// Idiome auto-contenu (cf. `FabNudgeBubble`) : lit un flag prefs async puis joue
/// l'animation via des `Timer`. Séquence, jouée **une seule fois par montage** et
/// **au plus 1×/jour** : fondu-in (~1 s après le montage) → tient 2 s → fondu-out.
/// Le montage lui-même est conditionné à « en retard » côté carte : ce widget
/// n'est monté que dans ce cas (« actif » == « monté »).
///
/// Reduce-motion (`MediaQuery.disableAnimations`) : l'animation n'est pas jouée
/// (le point rouge immobile, lui, porte déjà le signal). Miroir de
/// `welcome_banner.dart`.
class EphemeralRattraperLabel extends StatefulWidget {
  /// Clé du jour-tournée courant (`YYYY-MM-DD`, frontière 07h30 Paris). Sert de
  /// gate « déjà joué aujourd'hui ? » dans les prefs.
  final String dayKey;

  const EphemeralRattraperLabel({super.key, required this.dayKey});

  @override
  State<EphemeralRattraperLabel> createState() =>
      _EphemeralRattraperLabelState();
}

class _EphemeralRattraperLabelState extends State<EphemeralRattraperLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  Timer? _enterTimer;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    // Un seul contrôleur pilote largeur (SizeTransition) ET opacité
    // (FadeTransition) → révélation/repli synchronisés.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _maybePlay();
  }

  Future<void> _maybePlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(kRattraperNudgeLastShownPrefsKey);
      if (!mounted) return;
      if (last == widget.dayKey) return; // déjà joué aujourd'hui → rien.
    } catch (_) {
      // Prefs indisponibles (ex. tests sans mock) → on tente quand même.
    }
    if (!mounted) return;
    _enterTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _controller.forward();
      // Marqué « vu » au moment exact du fondu-in (gate 1×/jour aligné sur la
      // visibilité réelle) ; best-effort.
      _persistShown();
      _exitTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _controller.reverse();
      });
    });
  }

  Future<void> _persistShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kRattraperNudgeLastShownPrefsKey, widget.dayKey);
    } catch (_) {
      // best-effort : l'état mémoire de la session suffit à ne pas rejouer.
    }
  }

  @override
  void dispose() {
    _enterTimer?.cancel();
    _exitTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion : ne rien animer ni afficher (le point rouge porte le signal).
    if (MediaQuery.of(context).disableAnimations) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return SizeTransition(
      axis: Axis.horizontal,
      axisAlignment: -1,
      sizeFactor: _animation,
      child: FadeTransition(
        opacity: _animation,
        child: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            // Typo FR : espace avant « ? ». Aucun em-dash.
            'Rattraper ?',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
