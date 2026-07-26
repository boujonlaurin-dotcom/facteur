import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signal éphémère « on vient d'atterrir sur Flâner via la recherche du header
/// depuis L'Essentiel » (story 30.1 pré-merge).
///
/// Posé par [HeaderSearchButton] juste avant le `go(flaner)`, consommé **une
/// fois** par `flaner_screen` pour afficher un bandeau contextuel éphémère
/// (« Résultats pour « … » ») le temps que l'utilisateur se repère après la
/// bascule d'onglet. Remis à `false` par le consommateur une fois le bandeau
/// programmé — d'où le `StateProvider` (et non un simple événement) : le
/// consommateur doit pouvoir l'éteindre.
///
/// Volontairement **pas** armé quand le filtre change depuis la barre de
/// filtres de Flâner : l'utilisateur y est déjà, le bandeau serait du bruit.
final searchJustNavigatedProvider = StateProvider<bool>((ref) => false);
