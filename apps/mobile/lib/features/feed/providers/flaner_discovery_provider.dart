import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/content_model.dart';
import '../widgets/favorite_topic_tabs.dart' show FavoriteTabKind;
import 'feed_provider.dart';

/// Filtre de découverte actif d'un onglet Flâner : un couple (kind, slug).
/// Seuls les onglets sujet / thème / entité alimentent le bloc « Explorer » ;
/// les onglets Source et les mots-clés n'en ont pas besoin.
class FlanerDiscoveryArg {
  final FavoriteTabKind kind;
  final String slug;

  const FlanerDiscoveryArg({required this.kind, required this.slug});

  @override
  bool operator ==(Object other) =>
      other is FlanerDiscoveryArg &&
      other.kind == kind &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(kind, slug);
}

/// Récupère les articles du sujet/thème/entité **toutes sources confondues**
/// (sources suivies incluses), pour alimenter le bloc « Explorer de nouvelles
/// sources » en bas des onglets Flâner.
///
/// Le bloc principal (`feedProvider`) ne charge que les sources suivies
/// (`followed_only`) → rapide ; ce provider charge le reste **en parallèle**,
/// sans bloquer le rendu. Comme [themeDiscoveryProvider], le filtrage
/// `isFollowedSource == false` et la déduplication contre le bloc principal se
/// font dans la couche UI, ce qui garde le provider stateless et trivial à
/// tester.
final flanerDiscoveryProvider =
    FutureProvider.family.autoDispose<List<Content>, FlanerDiscoveryArg>(
  (ref, arg) async {
    final repo = ref.watch(feedRepositoryProvider);
    final resp = await repo.getFeed(
      topic: arg.kind == FavoriteTabKind.subjectTopic ? arg.slug : null,
      theme: arg.kind == FavoriteTabKind.theme ? arg.slug : null,
      entity: arg.kind == FavoriteTabKind.subjectEntity ? arg.slug : null,
      includeUnfollowed: true,
      page: 1,
      limit: 20,
    );
    return resp.items;
  },
);
