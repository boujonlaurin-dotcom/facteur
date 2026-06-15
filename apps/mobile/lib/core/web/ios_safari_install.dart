import 'ios_safari_install_stub.dart'
    if (dart.library.js_interop) 'ios_safari_install_web.dart';

/// Vrai si l'utilisateur ouvre Facteur via iOS Safari **sans** l'avoir
/// déjà ajouté à l'écran d'accueil (mode standalone). Faux ailleurs :
/// app native, Android, Chrome iOS, mode standalone, etc.
///
/// Utilisé par `iosAddToHomeShouldShowProvider` pour gater la modal
/// pédagogique "Ajouter à l'écran d'accueil".
bool isIosSafariNonStandalone() => checkIosSafariNonStandalone();
