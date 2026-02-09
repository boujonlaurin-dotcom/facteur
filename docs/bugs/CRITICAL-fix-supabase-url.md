# CORRECTION CRITIQUE - Secret SUPABASE_URL incorrect

## 🚨 Problème identifié

Le secret GitHub `SUPABASE_URL` contient l'**URL du dashboard** Supabase :
```
https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve
```

Au lieu de l'**URL API** Supabase :
```
https://ykuadtelnzavrqzbfdve.supabase.co
```

## ❌ Pourquoi ça cause l'erreur

Quand `Supabase.initialize()` est appelé avec l'URL du dashboard :
1. Toutes les requêtes auth vont vers `supabase.com/dashboard` au lieu de `ykuadtelnzavrqzbfdve.supabase.co`
2. Supabase renvoie une erreur "Invalid API key" ou "Session not found"
3. Cette erreur contient le mot "session", donc notre code traduit par "Ta session a expiré"

## ✅ Solution

### Étape 1: Corriger le secret GitHub

Allez sur https://github.com/boujonlaurin-dotcom/facteur/settings/secrets/actions

Modifiez le secret `SUPABASE_URL` :
- **Ancienne valeur (INCORRECTE) :** `https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve`
- **Nouvelle valeur (CORRECTE) :** `https://ykuadtelnzavrqzbfdve.supabase.co`

### Étape 2: Relancer les builds

Une fois le secret corrigé, relancez les builds :

**Pour le web (GitHub Pages) :**
```bash
gh workflow run build-web.yml --ref main
```

**Pour l'APK Android :**
```bash
gh workflow run build-apk.yml --ref main
```

Ou via l'interface GitHub :
- Allez dans l'onglet "Actions"
- Sélectionnez "Build Flutter Web" ou "Build Android APK"
- Cliquez sur "Run workflow" → "Run workflow"

### Étape 3: Tester

1. Attendez que les builds se terminent (~3-5 minutes pour le web, ~15 minutes pour l'APK)
2. Testez la connexion sur https://boujonlaurin-dotcom.github.io/facteur/
3. Téléchargez et testez le nouvel APK

## 🔧 Code - Auto-correction implémentée

J'ai ajouté une validation dans `constants.dart` qui détecte automatiquement l'URL du dashboard et la corrige :

```dart
static String _validateAndCleanSupabaseUrl(String value) {
  String cleaned = _cleanEnvVar(value);
  
  if (cleaned.isEmpty) return cleaned;
  
  // Détecter si c'est l'URL du dashboard au lieu de l'URL API
  if (cleaned.contains('supabase.com/dashboard')) {
    final RegExp projectRefRegex = RegExp(r'project/([a-z0-9]+)');
    final Match? match = projectRefRegex.firstMatch(cleaned);
    if (match != null) {
      final String projectRef = match.group(1)!;
      return 'https://$projectRef.supabase.co';
    }
  }
  
  return cleaned;
}
```

Cette auto-correction permettra à l'application de fonctionner même si le secret n'est pas corrigé immédiatement.

## 📋 Checklist

- [ ] Corriger le secret SUPABASE_URL dans GitHub Settings
- [ ] Relancer le build web
- [ ] Relancer le build APK
- [ ] Tester la connexion sur le web
- [ ] Tester la connexion sur Android

## 🎯 Résultat attendu

Après correction, la connexion doit fonctionner immédiatement sans erreur "Ta session a expiré".
