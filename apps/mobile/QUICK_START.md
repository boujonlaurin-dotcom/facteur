# 🚀 Guide de démarrage rapide - Facteur

## 📋 Prérequis

✅ **Flutter installé** (fait !)
✅ **Dépendances installées** (fait !)
✅ **Erreurs corrigées** (fait !)

## 🔧 Configuration Supabase (OBLIGATOIRE)

L'app nécessite Supabase pour fonctionner. Tu as 2 options :

### Option 1 : Utiliser un projet Supabase existant

Si tu as déjà un projet Supabase :

1. Va sur https://supabase.com/dashboard
2. Sélectionne ton projet
3. Va dans Settings → API
4. Copie :
   - **Project URL** (ex: `https://xxxxx.supabase.co`)
   - **anon public key** (ex: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`)

5. Lance l'app avec les variables d'environnement :

```bash
cd apps/mobile
flutter run -d chrome --dart-define=SUPABASE_URL=https://xxxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Option 2 : Créer un nouveau projet Supabase (recommandé pour tester)

1. Va sur https://supabase.com
2. Crée un compte gratuit
3. Crée un nouveau projet
4. Attends 2-3 minutes que le projet soit prêt
5. Va dans Settings → API
6. Copie l'URL et la clé anon
7. Lance avec les variables (voir Option 1)

## 🧪 Tester l'app SANS Supabase (mode dégradé)

Pour tester juste l'UI sans l'auth, on peut temporairement désactiver Supabase :

**⚠️ ATTENTION :** L'auth ne fonctionnera pas, mais tu pourras voir les écrans.

## 🎯 Lancer l'app

### Sur Chrome (web) - Recommandé pour tester rapidement

```bash
cd apps/mobile
flutter run -d chrome
```

### Sur macOS (desktop)

```bash
cd apps/mobile
flutter run -d macos
```

### Sur iOS (nécessite Xcode)

```bash
# D'abord installer Xcode depuis l'App Store
# Puis :
cd apps/mobile
flutter run -d ios
```

## 🐛 Problèmes courants

### "Supabase URL is empty"
→ Configure SUPABASE_URL (voir Option 1 ou 2 ci-dessus)

### "No devices found"
→ Vérifie que Chrome est ouvert, ou lance `flutter devices`

### "CocoaPods not installed" (pour iOS)
→ Installe CocoaPods : `sudo gem install cocoapods`

## 📝 Prochaines étapes

Une fois l'app lancée :
1. ✅ Tester le flow d'onboarding complet
2. ✅ Vérifier la navigation
3. ✅ Tester la sauvegarde (nécessite API backend)
4. ✅ Commit les changements

---

**Besoin d'aide ?** Vérifie les logs dans le terminal ou consulte la documentation Flutter.

