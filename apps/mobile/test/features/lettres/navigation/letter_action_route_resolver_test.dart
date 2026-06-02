import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/navigation/letter_action_route_resolver.dart';

LetterAction _action({required String id, String? route}) => LetterAction(
  id: id,
  label: 'Label',
  help: 'Help',
  status: LetterActionStatus.active,
  targetRoute: route,
);

void main() {
  group('resolveLetterActionRoute', () {
    test('maps known action ids to canonical routes', () {
      expect(
        resolveLetterActionRoute(_action(id: 'read_first_essentiel')),
        '/flux-continu/section/essentiel',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'read_first_bonnes_nouvelles')),
        '/flux-continu/section/bonnes',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'recommend_first_article')),
        '/flaner',
      );
    });

    test('normalizes legacy digest and feed routes', () {
      expect(
        resolveLetterActionRoute(
          _action(id: 'unknown', route: '/digest?serein=1'),
        ),
        '/flux-continu/section/bonnes',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'unknown', route: '/digest')),
        '/flux-continu/section/essentiel',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'unknown', route: '/feed')),
        '/flaner',
      );
    });

    test('keeps valid settings routes unchanged', () {
      expect(
        resolveLetterActionRoute(
          _action(id: 'unknown', route: '/settings/interests'),
        ),
        '/settings/interests',
      );
      expect(
        resolveLetterActionRoute(
          _action(id: 'unknown', route: '/settings/sources/add'),
        ),
        '/settings/sources/add',
      );
    });
  });
}
