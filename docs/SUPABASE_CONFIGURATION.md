# Configuration Supabase pour Account Creation

> Guide pour configurer les URL de redirection d'email dans Supabase Dashboard

## 🎯 URLs de Production Actuelles

| Composant | URL | Type |
|-----------|-----|------|
| **API Backend** | `https://facteur-production.up.railway.app/api/` | Production (Railway) |
| **Deep Link (Mobile)** | `io.supabase.facteur://login-callback` | Scheme (Android/iOS) |
| **Web App** | ❌ Non existante actuellement | - |

## ✅ Configuration Recommandée

### Option A: Mobile-Only (Recommandée pour NOW)

Si vous ignorez le web pour le moment et ne supportez que mobile:

**Supabase Dashboard > Auth > URL Configuration**

1. **Site URL** (fallback pour web):
   ```
   https://facteur-production.up.railway.app/api/
   ```
   > Note: Cette URL sera utilisée comme fallback si l'utilisateur accède au lien confirmation sur web/desktop

2. **Redirect URLs** (whitelist):
   ```
   io.supabase.facteur://login-callback
   ```

**Statut**: ✅ Minimal, mobile fonctionnel

---

### Option B: Mobile + Web (Futur)

Si vous déployez une web app (Flutter web, React, etc.):

**Supabase Dashboard > Auth > URL Configuration**

1. **Site URL**:
   ```
   https://facteur.app
   ```
   > Remplacer par votre domaine custom si différent

2. **Redirect URLs**:
   ```
   io.supabase.facteur://login-callback
   https://facteur.app/email-confirmation
   https://facteur.app/
   ```

**Déploiement requis**:
- Web app sur domaine custom ou Railway
- Route `/email-confirmation` (simple landing page ou redirection)
- DNS configuration pour `facteur.app`

---

### Option C: Railway Web Sub-domain

Alternative sans domaine custom (si web app déployée sur Railway):

**Supabase Dashboard > Auth > URL Configuration**

1. **Site URL**:
   ```
   https://facteur-web.up.railway.app
   ```
   > Supposant une deuxième application Rails deployed

2. **Redirect URLs**:
   ```
   io.supabase.facteur://login-callback
   https://facteur-web.up.railway.app/email-confirmation
   https://facteur-web.up.railway.app/
   ```

**Déploiement requis**:
- Web app distincte sur Railway avec domaine auto-généré

---

## 🔧 Configurations Actuelles (Vérification)

### Native Configuration (Already Configured ✅)

**Android** (`apps/mobile/android/app/src/main/AndroidManifest.xml`):
```xml
<data android:scheme="io.supabase.facteur" />
```

**iOS** (`apps/mobile/ios/Runner/Info.plist`):
```plist
<string>io.supabase.facteur</string>
```

### Mobile Code (Already Updated ✅)

`apps/mobile/lib/core/auth/auth_state.dart`:
```dart
final redirectUrl = kIsWeb
    ? '${Uri.base.origin}/email-confirmation'  // Web: current origin
    : 'io.supabase.facteur://login-callback';  // Native: deep link
```

---

## 📋 Step-by-Step: Option A (Recommended Now)

**Pour configurer maintenant (mobile-only)**:

1. Ouvrir [Supabase Dashboard](https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve/auth/url-configuration)
2. Naviguer à: **Auth > URL Configuration**

3. **Site URL**:
   - Trouver le champ "Site URL"
   - Remplacer `http://localhost:3000` par:
     ```
     https://facteur-production.up.railway.app/api/
     ```
   - Cliquer "Save"

4. **Redirect URLs**:
   - Trouver la section "Redirect URLs"
   - Cliquer "Add URL"
   - Ajouter:
     ```
     io.supabase.facteur://login-callback
     ```
   - Cliquer "Save"

5. **Vérification**:
   - Voir "✅ Saved" confirmation
   - Les modifications prennent effet immédiatement

---

## 📧 Email Settings (Issue #1)

**Si les emails ne s'envoient toujours pas**:

1. Naviguer à: **Auth > Email Settings**

2. Vérifier **Email Rate Limits**:
   - Free tier: ~4 emails/heure par adresse
   - Solution: Custom SMTP requis pour plus de volume

3. **Configurer Custom SMTP** (Optional):
   - Naviguer à: **Auth > Providers > Email > Custom SMTP**
   - Ajouter credentials (Resend, Postmark, SendGrid, etc.)
   - Bénéfices:
     - Limites plus élevées
     - Meilleur tracking
     - Custom domain + SPF/DKIM

---

## 🧪 Test Manual

Après configuration:

### Test 1: Mobile Confirmation
```
1. App mobile: Sign up (email)
2. Cliquer lien dans email
3. Devrait:
   - Ouvrir l'app mobile
   - Rediriger à /email-confirmation
   - Session confirmée automatiquement
```

### Test 2: Desktop/Web Link
```
1. Desktop: Click email link
2. Devrait:
   - Charger https://facteur-production.up.railway.app/api/
   - Ou afficher message "Ouvrir dans l'app"
   - Ne PAS aller à localhost:3000
```

### Test 3: Complete Flow
```
1. Sign up
2. Confirm email
3. Complete onboarding
4. EXPECTED: Success, no "Serveur rencontre difficultés" error
```

---

## 🚨 Troubleshooting

| Problème | Cause | Solution |
|----------|-------|----------|
| Redirection vers `localhost:3000` | Site URL mal configurée | Mettre à jour à `facteur-production.up.railway.app/api/` |
| Deep link n'ouvre pas l'app | Deep link scheme pas en whitelist | Ajouter `io.supabase.facteur://login-callback` à Redirect URLs |
| Email ne s'envoie pas | Rate limit Supabase free tier | Configurer Custom SMTP ou attendre 1h+ |
| Email reçu mais link cassé | Redirect URL non whitelisted | Vérifier Redirect URLs match exactement |

---

## 📚 References

- [Supabase Auth URL Config](https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve/auth/url-configuration)
- [Supabase Email Templates](https://supabase.com/dashboard/project/ykuadtelnzavrqzbfdve/auth/templates)
- Story 1.3c: [Account Creation Hardening](docs/stories/evolutions/1.3c.auth-account-creation-hardening.story.md)
- Bug Report: [3 Issues Details](docs/bugs/bug-account-creation-3-issues.md)

---

## ✨ Summary

**Configuration Minimale (Mobile):**
```
Site URL: https://facteur-production.up.railway.app/api/
Redirect URL: io.supabase.facteur://login-callback
```

**Configuration Complète (Mobile + Web):**
```
Site URL: https://facteur.app  (ou votre domaine)
Redirect URLs:
  - io.supabase.facteur://login-callback
  - https://facteur.app/email-confirmation
  - https://facteur.app/
```

**Status**: Ready to configure! 🚀
