import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/constants.dart';
import '../../../core/auth/auth_state.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../shared/widgets/buttons/secondary_button.dart';
import 'email_confirmation_screen.dart';

/// Écran de connexion / inscription
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
    });
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || (password.isEmpty && !_isSignUp)) {
      return;
    }

    final authNotifier = ref.read(authStateProvider.notifier);

    if (_isSignUp) {
      await authNotifier.signUpWithEmail(email, password);
    } else {
      await authNotifier.signInWithEmail(email, password,
          rememberMe: _rememberMe);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    final controller = TextEditingController(text: email);
    final colors = context.facteurColors;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mot de passe oublié ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Saisis ton adresse email pour recevoir un lien de réinitialisation.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              final resetEmail = controller.text.trim();
              if (resetEmail.isEmpty) return;

              Navigator.pop(context);

              try {
                await ref
                    .read(authStateProvider.notifier)
                    .sendPasswordResetEmail(resetEmail);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Email de réinitialisation envoyé !'),
                      backgroundColor: colors.success,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: colors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  Future<void> _signInWithApple() async {
    await ref.read(authStateProvider.notifier).signInWithApple();
  }

  Future<void> _signInWithGoogle() async {
    await ref.read(authStateProvider.notifier).signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final colors = context.facteurColors;

    // Naviguer vers l'écran de confirmation email après signup
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.pendingEmailConfirmation != null &&
          previous?.pendingEmailConfirmation == null) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EmailConfirmationScreen(
              email: next.pendingEmailConfirmation!,
            ),
          ),
        );
        // Effacer l'état pour éviter une 2ème navigation
        ref.read(authStateProvider.notifier).clearPendingEmailConfirmation();
      }
    });

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // Logo / Titre
                Column(
                  children: [
                    Icon(
                      PhosphorIcons.envelopeSimple(PhosphorIconsStyle.fill),
                      size: 64,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Facteur',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            color: colors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tes contenus, triés avec soin.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),

                const SizedBox(height: 48),

                // Formulaire
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),

                if (!_isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Mot de passe oublié ?',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() {
                        _rememberMe = value ?? true;
                      });
                    },
                    title: const Text(
                      'Rester connecté',
                      style: TextStyle(fontSize: 14),
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: colors.primary,
                  ),
                ],

                // Erreur
                if (authState.error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: colors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authState.error!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.error),
                              ),
                            ),
                          ],
                        ),
                        // DEBUG: Afficher l'URL Supabase
                        const SizedBox(height: 8),
                        Text(
                          'Supabase URL: ${SupabaseConstants.url}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: colors.textSecondary, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Bouton principal
                PrimaryButton(
                  label: _isSignUp ? 'Créer un compte' : 'Se connecter',
                  onPressed: _submitEmail,
                  isLoading: authState.isLoading,
                ),

                const SizedBox(height: 16),

                // Toggle inscription/connexion amélioré
                if (!_isSignUp) ...[
                  // Mode login : afficher un encart attractif pour l'inscription
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.primary.withOpacity(0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: colors.primary.withOpacity(0.05),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Pas encore de compte ?',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _toggleMode,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: colors.primary,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 24,
                            ),
                          ),
                          child: Text(
                            'Créer un compte gratuitement',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: colors.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Mode signup : simple lien pour revenir au login
                  Center(
                    child: TextButton(
                      onPressed: _toggleMode,
                      child: Text(
                        'Déjà un compte ? Se connecter',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'ou',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),

                // Social login
                SecondaryButton(
                  label: 'Continuer avec Apple',
                  icon: PhosphorIcons.appleLogo(PhosphorIconsStyle.fill),
                  onPressed: _signInWithApple,
                ),

                const SizedBox(height: 12),

                SecondaryButton(
                  label: 'Continuer avec Google',
                  icon: PhosphorIcons.googleLogo(PhosphorIconsStyle.fill),
                  onPressed: _signInWithGoogle,
                ),

                const SizedBox(height: 24),

                // CGV
                Text(
                  'En continuant, tu acceptes nos Conditions d\'utilisation et notre Politique de confidentialité.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
