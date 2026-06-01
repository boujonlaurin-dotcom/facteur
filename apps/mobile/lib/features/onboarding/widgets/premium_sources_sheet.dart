import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/premium_source_connection.dart';
import '../../../widgets/design/facteur_image.dart';
import '../onboarding_strings.dart';

/// Bottom sheet for indicating press subscriptions during onboarding.
///
/// Shows all curated sources so the user can mark which ones they have
/// a paid subscription to. Returns the set of subscribed source IDs via [onDone].
class PremiumSourcesSheet extends ConsumerStatefulWidget {
  final List<Source> allSources;
  final ValueChanged<Set<String>>? onDone;

  const PremiumSourcesSheet({
    super.key,
    required this.allSources,
    this.onDone,
  });

  @override
  ConsumerState<PremiumSourcesSheet> createState() =>
      _PremiumSourcesSheetState();
}

class _PremiumSourcesSheetState extends ConsumerState<PremiumSourcesSheet> {
  late Set<String> _subscribed;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Only pre-toggle sources the user already marked as subscribed
    _subscribed = widget.allSources
        .where((s) => s.isCurated && s.hasSubscription)
        .map((s) => s.id)
        .toSet();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Source> get _filteredSources {
    var sources = widget.allSources
        .where((s) =>
            s.isCurated &&
            (s.premiumConnection != null || _subscribed.contains(s.id)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      sources =
          sources.where((s) => s.name.toLowerCase().contains(query)).toList();
    }

    return sources;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sources = _filteredSources;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: FacteurSpacing.space3),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: FacteurSpacing.space4),

          // Title
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
            child: Column(
              children: [
                Text(
                  OnboardingStrings.premiumSheetTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FacteurSpacing.space2),
                Text(
                  OnboardingStrings.premiumSheetSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: FacteurSpacing.space3),

          // Search bar
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: OnboardingStrings.q9SearchHint,
                prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FacteurSpacing.space4,
                  vertical: FacteurSpacing.space3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FacteurRadius.full),
                  borderSide: BorderSide.none,
                ),
                hintStyle: TextStyle(color: colors.textSecondary),
              ),
              style: TextStyle(color: colors.textPrimary),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          const SizedBox(height: FacteurSpacing.space3),

          Flexible(
            child: sources.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space6,
                      vertical: FacteurSpacing.space4,
                    ),
                    child: Center(
                      child: Text(
                        'Aucun média premium connectable pour le moment.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space6,
                    ),
                    itemCount: sources.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FacteurSpacing.space2),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      final isSubscribed = _subscribed.contains(source.id);
                      return _buildSourceTile(context, source, isSubscribed);
                    },
                  ),
          ),

          // Done button
          Padding(
            padding: const EdgeInsets.all(FacteurSpacing.space6),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onDone?.call(_subscribed);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(OnboardingStrings.premiumSheetDone),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildLogoFallback(FacteurColors colors, String name) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSourceTile(
      BuildContext context, Source source, bool isSubscribed) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space1),
      child: Row(
        children: [
          // Logo (36x36)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 36,
              height: 36,
              child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                  ? FacteurImage(
                      imageUrl: source.logoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_) =>
                          _buildLogoFallback(colors, source.name),
                    )
                  : _buildLogoFallback(colors, source.name),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space3),
          // Name
          Expanded(
            child: Text(
              source.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => isSubscribed
                ? _disconnectSource(source)
                : _connectSource(context, source),
            child: Text(isSubscribed ? 'Dissocier' : 'Connecter'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectSource(BuildContext context, Source source) async {
    if (source.premiumConnection == null) return;
    final navigator = Navigator.of(context);
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          onConnected: () async {
            await ref
                .read(userSourcesProvider.notifier)
                .connectSubscription(source.id);
            if (mounted) {
              setState(() => _subscribed.add(source.id));
            }
          },
        ),
      ),
    );
  }

  Future<void> _disconnectSource(Source source) async {
    await HapticFeedback.lightImpact();
    await ref
        .read(userSourcesProvider.notifier)
        .disconnectSubscription(source.id);
    if (mounted) {
      setState(() => _subscribed.remove(source.id));
    }
  }
}
