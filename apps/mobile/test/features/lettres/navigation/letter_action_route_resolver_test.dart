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

    test('maps letter 3 and 4 action ids (Story 26.2)', () {
      expect(
        resolveLetterActionRoute(_action(id: 'create_first_veille')),
        '/veille/config',
      );
      expect(resolveLetterActionRoute(_action(id: 'save_5_articles')), '/flaner');
      expect(resolveLetterActionRoute(_action(id: 'write_first_note')), '/saved');
      expect(resolveLetterActionRoute(_action(id: 'mute_3_sources')), '/flaner');
      expect(
        resolveLetterActionRoute(_action(id: 'add_5_youtube_channels')),
        '/settings/sources/add',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'read_50_articles')),
        '/flaner',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'recommend_10_articles')),
        '/flaner',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'open_10_perspectives')),
        '/flaner',
      );
      expect(
        resolveLetterActionRoute(_action(id: 'give_app_feedback')),
        '/settings',
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
