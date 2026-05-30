import 'package:flutter/material.dart';

/// Constantes du module « La Grille du jour ».
///
/// Centralise les valeurs **hors-token** explicitement validées dans le design
/// (`.context/attachments/0rGiaa/grille.css`) — celles qui n'existent pas dans
/// `FacteurPalettes`/`FacteurRadius` — ainsi que les dimensions et timings
/// d'animation. Toute valeur qui EXISTE déjà comme token doit passer par le
/// thème (`context.facteurColors`, `FacteurRadius`, `FacteurSpacing`), jamais
/// être redéclarée ici.
class GrilleConstants {
  GrilleConstants._();

  // ── Couleurs hors-token (validées dans grille.css) ──────────────────────
  /// Tuile « absente » : charbon chaud — « n'habite pas ici ». (`.mt-tile.s-absent`)
  static const Color absentGrille = Color(0xFF837A6D);

  /// Touche clavier « absente » : gris plus clair. (`.kb-key.s-absent`)
  static const Color absentClavier = Color(0xFFBBB1A1);

  /// Bouton « steel » (footer Défier un·e ami·e). (`.g-btn.steel`)
  static const Color steel = Color(0xFF34495E);

  /// Jauge de distribution (barres remplies hors « moi »). (`.gl-dist .row .fill`)
  static const Color gauge = Color(0xFFCDBFA6);

  /// Fond d'avatar fallback (illustration Facteur). (`background: #F0E6D2`)
  static const Color avatarFallback = Color(0xFFF0E6D2);

  // ── Rayons custom hors FacteurRadius ────────────────────────────────────
  /// Rayon d'une tuile de jeu. (`.mt-tile { border-radius: 6px }`)
  static const double tileRadius = 6;

  /// Rayon d'un carré de partage. (`.msg-cell { border-radius: 4px }`)
  static const double shareCellRadius = 4;

  /// Rayon d'une touche de clavier. (`.kb-key { border-radius: 7px }`)
  static const double keyRadius = 7;

  // ── Dimensions de jeu ───────────────────────────────────────────────────
  /// Côté d'une tuile sur l'écran de jeu. (`.mot-grid { --tile: 50px }`)
  static const double tileSize = 50;

  /// Côté d'une tuile sur l'écran résultat. (`.mot-grid.v-resultat { --tile: 44px }`)
  static const double tileSizeResult = 44;

  /// Espace entre tuiles (jeu). (`--gap: 6px`)
  static const double tileGap = 6;

  /// Espace entre tuiles (résultat). (`.v-resultat { --gap: 5px }`)
  static const double tileGapResult = 5;

  /// Hauteur d'une touche de clavier. (`.kb-key { height: 50px }`)
  static const double keyHeight = 50;

  /// Côté d'un carré de partage. (`.msg-cell { width/height: 24px }`)
  static const double shareCellSize = 24;

  /// Côté d'une mini-tuile (carte d'entrée). (`.mt-mini { width/height: 18px }`)
  static const double miniTileSize = 18;

  // ── Animations ──────────────────────────────────────────────────────────
  /// Durée du flip de révélation d'une tuile. (`@keyframes mt-flip { 420ms }`)
  static const Duration flipDuration = Duration(milliseconds: 420);

  /// Décalage du flip par colonne. (`animation-delay: calc(var(--i) * 95ms)`)
  static const Duration flipStagger = Duration(milliseconds: 95);

  /// Durée du shake d'un mot invalide. (contrôleur séparé, ~250ms)
  static const Duration shakeDuration = Duration(milliseconds: 250);

  // ── Lien de partage ─────────────────────────────────────────────────────
  /// Base de lien de partage (sans spoiler). Le deep-link entrant est hors MVP.
  static const String shareBaseUrl = 'https://facteur.app/grille';
}
