import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deep-link « file droit vers une section » du rituel matinal (EPIC « Lettre
/// du jour »).
///
/// Le rituel pose ici la `sectionKey` de la section à révéler avant de naviguer
/// vers le feed ; `flux_continu_screen` la consomme une fois ses sections
/// mesurées (`_stickyEntryKeys` peuplé), scrolle jusqu'à l'entrée sticky
/// correspondante puis remet le provider à `null`. `null` = ouverture normale
/// (feed en haut), aucun deep-link en attente.
final pendingFeedSectionKeyProvider = StateProvider<String?>((_) => null);
