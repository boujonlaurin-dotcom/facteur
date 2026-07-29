import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feedback/feedback_call_copy.dart';
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

  // Viewport téléphone (390x844, la cible QA du projet) : le viewport de test
  // par défaut (800x600) est plus court que n'importe quel mobile réel et
  // pousserait les sorties de la modale hors écran.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

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
    usePhoneViewport(tester);
    await tester.pumpWidget(createLauncher(segment));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('CallInviteSheet', () {
    testWidgets('shows the founders, the ask and the three exits',
        (tester) async {
      await openSheet(tester, 'active');

      expect(find.text('DJANGO'), findsOneWidget);
      expect(find.text('LAURIN'), findsOneWidget);
      expect(find.text(FeedbackCallCopy.stamp), findsOneWidget);
      expect(find.text(FeedbackCallCopy.title), findsOneWidget);
      expect(find.text(FeedbackCallCopy.ask), findsOneWidget);
      expect(find.text(FeedbackCallCopy.signature), findsOneWidget);
      expect(find.text(FeedbackCallCopy.ctaBook), findsOneWidget);
      expect(find.text(FeedbackCallCopy.ctaLater), findsOneWidget);
      expect(find.text(FeedbackCallCopy.ctaAlreadyDone), findsOneWidget);
    });

    testWidgets('uses the regular-reader copy for the active segment',
        (tester) async {
      await openSheet(tester, 'active');
      expect(find.text(FeedbackCallCopy.bodyActive), findsOneWidget);
    });

    testWidgets('uses the occasional copy for low_active and returning',
        (tester) async {
      await openSheet(tester, 'low_active');
      expect(find.text(FeedbackCallCopy.bodyOccasional), findsOneWidget);

      await openSheet(tester, 'returning');
      expect(find.text(FeedbackCallCopy.bodyOccasional), findsOneWidget);
    });

    testWidgets('"Plus tard" records declined and closes the sheet',
        (tester) async {
      await openSheet(tester, 'active');

      await tester.tap(find.text(FeedbackCallCopy.ctaLater));
      await tester.pumpAndSettle();

      verify(() => mockRepo.submitInviteAction('declined')).called(1);
      expect(find.text(FeedbackCallCopy.ctaLater), findsNothing);
    });

    testWidgets('"On l\'a déjà fait" records already_done and closes the sheet',
        (tester) async {
      await openSheet(tester, 'active');

      await tester.tap(find.text(FeedbackCallCopy.ctaAlreadyDone));
      await tester.pumpAndSettle();

      verify(() => mockRepo.submitInviteAction('already_done')).called(1);
      expect(find.text(FeedbackCallCopy.ctaAlreadyDone), findsNothing);
    });
  });
}
