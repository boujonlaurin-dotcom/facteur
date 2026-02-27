# Maintenance: iOS Build Désactivé

## Contexte

**Date:** 2026-02-27
**Décision:** Abandon du workflow iOS build (AltStore)
**Raison:** Trop de blocages pour une distribution iOS viable à ce stade

---

## Pourquoi

Tentative de mise en place d'un pipeline `flutter build ipa --release --no-codesign` via GitHub Actions (`macos-latest`) pour distribuer l'app via AltStore (sideloading).

### Blocages rencontrés
1. **Pas de Xcode local** — impossible de builder/debugger iOS en local
2. **Pas d'Apple Developer Program** ($99/an) — codesigning impossible, pas de TestFlight
3. **AltStore limitations** — re-signature tous les 7 jours, UX complexe pour testeurs
4. **Erreurs CI** — le build IPA sur GitHub Actions échouait (nom de fichier IPA imprévisible)

### Options évaluées

| Option | Description | Choix |
|--------|-------------|-------|
| 1 | Xcode local + Apple Dev Program + TestFlight | ❌ Pas de Xcode, pas de budget |
| 2 | Codemagic + Apple Dev Program | ❌ Pas de budget Apple Dev |
| 3 | GitHub Actions + AltStore (sans codesign) | ❌ UX testeurs trop complexe + erreurs CI |
| 4 | **Reporter iOS** | ✅ **Choisi** |

---

## Ce qui a été supprimé

| Fichier | Action |
|---------|--------|
| `.github/workflows/build-ipa.yml` | Supprimé |
| PR #129 | Fermée |

---

## Plan de réactivation

### Quand réactiver ?
1. **Apple Developer Program** souscrit ($99/an)
2. **Xcode** disponible (ou CI/CD avec codesigning configuré)

### Étapes
1. Souscrire Apple Developer Program
2. Choisir CI/CD : Codemagic (recommandé pour Flutter) ou GitHub Actions (`macos-latest`)
3. Configurer codesigning (certificat + provisioning profile)
4. Créer le workflow CI avec publication TestFlight
5. Inviter beta testeurs via TestFlight

---

**Status:** iOS reporté, focus Android uniquement
**Dernière mise à jour:** 2026-02-27
