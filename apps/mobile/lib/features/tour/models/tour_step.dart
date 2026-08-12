/// Étapes du tour guidé post-onboarding (cf. `Tour guidé Facteur.dc.html`).
///
/// 7 états sont **joués** ; le proto n'affiche que 6 puces de progression car le
/// point « 2 / 6 » est partagé entre deux panneaux ([descendsCartes] qui montre
/// les sections de la Tournée et [favorisSheet] qui présente la feuille « Mes
/// favoris »). Le mapping vit dans [TourStepDisplay.displayIndex].
enum TourStep {
  /// 1/6 — hero « L'Essentiel du jour » (ta Tournée du jour).
  essentielHero,

  /// 2/6 (a) — invite à descendre dans les sections de la Tournée.
  descendsCartes,

  /// 2/6 (b) — feuille « Mes favoris » ouverte (réorganiser sa Tournée).
  favorisSheet,

  /// 3/6 — onglet Flâner.
  flaner,

  /// 4/6 — Réglages (spotlight de l'avatar profil, sans navigation réelle).
  reglages,

  /// 5/6 — Mon courrier (même avatar profil).
  courrier,

  /// 6/6 — Mode Serein : ouvre la modale réglages et met en surbrillance la
  /// tuile « Mode Serein » (dernière étape « Terminer »).
  serein,

  /// Carte finale « C'est parti » avant de rendre la main aux modales.
  done,
}

extension TourStepDisplay on TourStep {
  /// Numéro affiché sur la pastille « N / 6 » du coach card. [descendsCartes] et
  /// [favorisSheet] partagent le point 2 (cf. proto). [done] n'affiche pas de
  /// pastille (carte de conclusion) → retourne le dernier index par défaut.
  int get displayIndex => switch (this) {
        TourStep.essentielHero => 1,
        TourStep.descendsCartes => 2,
        TourStep.favorisSheet => 2,
        TourStep.flaner => 3,
        TourStep.reglages => 4,
        TourStep.courrier => 5,
        TourStep.serein => 6,
        TourStep.done => 6,
      };

  /// Nombre total de puces de progression (6, le point 2 étant mutualisé).
  static const int totalSteps = 6;
}
