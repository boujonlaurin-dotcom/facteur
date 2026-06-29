import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feedback/providers/feedback_providers.dart';
import 'package:facteur/features/feedback/repositories/feedback_repository.dart';
import 'package:facteur/features/feedback/widgets/call_invite_sheet.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late MockFeedbackRepository mockRepo;

  setUp(() {
    mockRepo = MockFeedbackRepository();
    when(() => mockRepo.submitInviteAction(any())).thenAnswer((_) async {});
  });

  // Bouton lanceur pour disposer d'un Navigator capable de "pop".
  Widget createLauncher(String? segment) {
    return ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    CallInviteSheet.show(context, segment: segment),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester, String? segment) async {
    await tester.pumpWidget(createLauncher(segment));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('CallInviteSheet', () {
    testWidgets('shows the active-segment copy and three options',
        (tester) async {
      await openSheet(tester, 'active');

      expect(find.textContaining('Merci d\'être là'), findsOneWidget);
      expect(find.text('15 min, je suis curieux'), findsOneWidget);
      expect(find.text('J\'ai un truc précis à te dire'), findsOneWidget);
      expect(find.text('Pas maintenant'), findsOneWidget);
    });

    testWidgets('shows returning-segment copy', (tester) async {
      await openSheet(tester, 'returning');
      expect(find.textContaining('Content de te revoir'), findsOneWidget);
    });

    testWidgets('shows low_active-segment copy', (tester) async {
      await openSheet(tester, 'low_active');
      expect(find.textContaining('On prend 15 min'), findsOneWidget);
    });

    testWidgets('"Pas maintenant" records declined and closes the sheet',
        (tester) async {
      await openSheet(tester, 'active');

      await tester.tap(find.text('Pas maintenant'));
      await tester.pumpAndSettle();

      verify(() => mockRepo.submitInviteAction('declined')).called(1);
      expect(find.text('Pas maintenant'), findsNothing);
    });
  });
}
