import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../../config/constants.dart';

/// Point de décision UNIQUE des mises à jour pour le flavor **playstore**.
///
/// Google interdit à une app du Play Store de se mettre à jour en
/// téléchargeant/installant un APK : sur ce flavor, l'updater APK maison
/// (`flutter_downloader` + `open_filex`) est déjà neutralisé
/// (cf. `appUpdateProvider`, gaté par `AppUpdateConstants.isPlayStoreBuild`).
/// Ce service le remplace par les **Google Play In-App Updates** (invite native).
///
/// Sur les flavors beta/dev, [checkAndStart] est un **no-op total** : le chemin
/// APK maison reste seul actif, inchangé.
class PlayStoreUpdateService {
  PlayStoreUpdateService();

  /// Priorité (Play Console, 0-5) à partir de laquelle on force une MàJ
  /// bloquante (immediate). Fixée par release dans la Play Console. En-dessous
  /// du seuil → MàJ flexible (téléchargement en fond, non bloquant).
  static const int kImmediateUpdatePriority = 4;

  /// Anti-ré-entrance : le check est déclenché au cold-start ET au retour
  /// foreground ; on évite de relancer un flux pendant qu'un autre est en cours.
  bool _inFlight = false;

  /// Vérifie la disponibilité d'une MàJ Play et déclenche le flux adéquat.
  ///
  /// Ne lève jamais : un check d'update ne doit jamais bloquer ni casser l'app.
  Future<void> checkAndStart() async {
    // Routage piloté par le flavor, pas par une condition runtime fragile.
    if (kIsWeb || !Platform.isAndroid) return;
    if (!AppUpdateConstants.isPlayStoreBuild) return;
    if (_inFlight) return;

    _inFlight = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return;
      }

      final priority = info.updatePriority;
      if (info.immediateUpdateAllowed && priority >= kImmediateUpdatePriority) {
        // MàJ critique : flux bloquant plein écran géré par le Play Store.
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        // MàJ standard : téléchargement en fond puis install à la complétion.
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (e) {
      // Fail silently — comme appUpdateProvider, le check ne doit jamais
      // bloquer l'app (ex. user qui refuse l'immediate update → exception).
      // ignore: avoid_print
      print('PlayStoreUpdate: check failed: $e');
    } finally {
      _inFlight = false;
    }
  }
}

/// Service singleton de MàJ Play Store (no-op hors flavor playstore).
final playStoreUpdateServiceProvider = Provider<PlayStoreUpdateService>(
  (ref) => PlayStoreUpdateService(),
);
