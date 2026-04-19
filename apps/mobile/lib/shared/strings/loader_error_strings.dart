/// Strings centralisées pour les loaders, écrans d'erreur et fallback contact.
///
/// Périmètre strict : uniquement chargements + erreurs + fallback Laurin.
/// Le reste de l'app conserve ses strings actuelles.
library;

class LoaderStrings {
  LoaderStrings._();

  /// Phrases courtes affichées sous le loader pendant un chargement prolongé,
  /// au-dessus de la carte éditoriale. Tirées au hasard.
  static const List<String> longLoadingHints = [
    'Le facteur prend la côte…',
    'Secouage des sacoches…',
    'Attrapage des infos…',
    'Plus que quelques mètres…',
    'Vérification de l\'adresse postale…',
  ];
}

class FriendlyErrorStrings {
  FriendlyErrorStrings._();

  // Réseau / pas de connexion
  static const String networkTitle = 'Pas de connexion.';
  static const String networkSubtitle =
      'Pas de panique : l\'Essentiel arrive bientôt.';

  // Timeout
  static const String timeoutTitle = 'Facteur fatigue on dirait.';
  static const String timeoutSubtitle = 'Allez, un dernier coup de pédale ?';

  // Serveur indisponible (503)
  static const String serverDownTitle = 'Petit souci de serveur !';
  static const String serverDownSubtitle =
      'Il revient dans quelques instants. Promis.';

  // Erreur générique
  static const String genericTitle = 'Petit souci !';
  static const String genericSubtitle =
      'On retente ? La 2ème est souvent la bonne.';

  // Bouton retry
  static const String retryLabel = 'Réessayer';
}

class LaurinFallbackStrings {
  LaurinFallbackStrings._();

  static const String title = 'Quelques pépins — navrés !';
  static const String subtitle =
      'On corrige ça dans l\'heure. Repassez vite, votre Essentiel sera là.';

  static const String retryLabel = 'Réessayer quand même';

  static const String contactSectionTitle = 'Prévenir Laurin';
  static const String contactSectionSubtitle =
      'Si le blocage persiste, écrivez nous un mot rapide ! ✉️';

  static const String mailLabel = 'Mail';
  static const String whatsappLabel = 'WhatsApp';

  static const String clipboardConfirmation =
      'Message copié — envoies-le nous dans ta messagerie préférée. ;)';

  /// Texte pré-rempli copié dans le presse-papier ET passé en body du mail/WA.
  static const String prefilledMessage =
      'Salut Laurin, mon Facteur ne charge pas. Tu peux jeter un œil quand tu peux ? Merci !';

  static const String mailSubject = 'Facteur — petit souci de chargement';
}
