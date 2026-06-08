import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_button.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../services/premium_session_store.dart';
import 'premium_web_view.dart';
import 'source_logo_avatar.dart';

typedef PremiumWebViewBuilder = Widget Function(
    BuildContext context, String url);

class PremiumSourceConnection extends ConsumerStatefulWidget {
  final Source source;
  final Future<void> Function() onConnected;
  final VoidCallback? onFinished;
  final PremiumWebViewBuilder? webViewBuilder;
  final Future<void> Function(String url)? openExternal;

  const PremiumSourceConnection({
    super.key,
    required this.source,
    required this.onConnected,
    this.onFinished,
    this.webViewBuilder,
    this.openExternal,
  });

  @override
  ConsumerState<PremiumSourceConnection> createState() =>
      _PremiumSourceConnectionState();
}

class _PremiumSourceConnectionState
    extends ConsumerState<PremiumSourceConnection> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  PremiumConnection get _connection => widget.source.premiumConnection!;

  PremiumSessionStore get _sessionStore =>
      ref.read(premiumSessionStoreProvider);

  Future<void> _openExternal(String url) async {
    if (widget.openExternal != null) {
      await widget.openExternal!(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Session validée par l'utilisateur : on capture les cookies du média
      // (store partagé, jamais recréé entre login et test) AVANT de persister
      // l'abonnement côté backend.
      final testUri = WebUri(_connection.testUrl);
      await _sessionStore.captureForSource(widget.source, testUri);
      await widget.onConnected();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = 3;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Impossible de connecter cet abonnement.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(), color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.source.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: SafeArea(child: _buildStep(context, colors)),
    );
  }

  Widget _buildStep(BuildContext context, FacteurColors colors) {
    switch (_step) {
      case 1:
        return _WebViewStep(
          key: const ValueKey('premium-webview-login'),
          title: 'Connexion',
          url: _connection.loginUrl,
          source: widget.source,
          sessionStore: _sessionStore,
          actionLabel: 'Continuer vers l\'article test',
          webViewBuilder: widget.webViewBuilder,
          onAction: () => setState(() => _step = 2),
          onOpenExternal: () => _openExternal(_connection.loginUrl),
        );
      case 2:
        return _WebViewStep(
          key: const ValueKey('premium-webview-test'),
          title: 'Article test',
          url: _connection.testUrl,
          source: widget.source,
          sessionStore: _sessionStore,
          actionLabel: 'L\'article s\'affiche correctement',
          webViewBuilder: widget.webViewBuilder,
          onAction: _saving ? null : _confirm,
          onOpenExternal: () => _openExternal(_connection.testUrl),
          isLoading: _saving,
          error: _error,
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 56,
                color: colors.success,
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Abonnement connecté',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                'Les articles de ${widget.source.name} s\'ouvriront dans Facteur tant que la session du média reste active.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space6),
              FacteurButton(
                label: 'Terminer',
                type: FacteurButtonType.primary,
                icon: PhosphorIcons.check(),
                onPressed: () {
                  widget.onFinished?.call();
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: SourceLogoAvatar(source: widget.source, size: 72)),
              const SizedBox(height: FacteurSpacing.space6),
              Text(
                'Connecter votre abonnement',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                _connection.displayHint ??
                    'Connectez-vous dans la WebView du média, puis confirmez qu\'un article abonné s\'affiche correctement.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
              ),
              const Spacer(),
              FacteurButton(
                label: 'Commencer',
                type: FacteurButtonType.primary,
                icon: PhosphorIcons.link(),
                onPressed: () => setState(() => _step = 1),
              ),
            ],
          ),
        );
    }
  }
}

class _WebViewStep extends StatelessWidget {
  final String title;
  final String url;
  final Source source;
  final PremiumSessionStore sessionStore;
  final String actionLabel;
  final PremiumWebViewBuilder? webViewBuilder;
  final VoidCallback? onAction;
  final VoidCallback onOpenExternal;
  final bool isLoading;
  final String? error;

  const _WebViewStep({
    super.key,
    required this.title,
    required this.url,
    required this.source,
    required this.sessionStore,
    required this.actionLabel,
    required this.onAction,
    required this.onOpenExternal,
    this.webViewBuilder,
    this.isLoading = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final webView = webViewBuilder?.call(context, url) ??
        PremiumWebView(
          source: source,
          url: WebUri(url),
          sessionStore: sessionStore,
          enableScrollBridge: false,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FacteurSpacing.space4,
            FacteurSpacing.space2,
            FacteurSpacing.space4,
            FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenExternal,
                icon: Icon(PhosphorIcons.arrowSquareOut(), size: 18),
                label: const Text('Navigateur'),
              ),
            ],
          ),
        ),
        Expanded(child: webView),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          child: FacteurButton(
            label: isLoading ? 'Connexion...' : actionLabel,
            type: FacteurButtonType.primary,
            icon: PhosphorIcons.arrowRight(),
            onPressed: onAction,
          ),
        ),
      ],
    );
  }
}
