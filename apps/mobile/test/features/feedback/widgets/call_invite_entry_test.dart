import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:facteur/features/feedback/feedback_call_copy.dart';
import 'package:facteur/features/feedback/models/feedback_models.dart';
import 'package:facteur/features/feedback/providers/feedback_providers.dart';
import 'package:facteur/features/feedback/repositories/feedback_repository.dart';
import 'package:facteur/features/feedback/widgets/call_invite_entry.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late MockFeedbackRepository mockRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    mockRepo = MockFeedbackRepository();
    when(() => mockRepo.markInviteShown()).thenAnswer((_) async {});
    when(() => mockRepo.submitInviteAction(any())).thenAnswer((_) async {});
  });

  Widget createWidget(FeedbackInviteStatus status) {
    return ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(mockRepo),
        inviteStatusProvider.overrideWith((ref) async => status),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CallInviteEntry()),
      ),
    );
  }

  /// Monte l'entrée et laisse le pipeline aller au bout : `VisibilityDetector`
  /// notifie en post-frame, et l'auto-ouverture attend elle-même une frame
  /// supplémentaire. Un simple `pumpAndSettle` s'arrête avant.
  Future<void> pumpEntry(
    WidgetTester tester,
    FeedbackInviteStatus status,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(createWidget(status));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  // Le bouton de la modale porte le même libellé que le CTA de l'entrée
  // inline (cohérence voulue) : on cible le bouton, pas le texte.
  final sheetBookButton =
      find.widgetWithText(ElevatedButton, FeedbackCallCopy.ctaBook);

  const eligible = FeedbackInviteStatus(shouldShow: true, segment: 'active');

  group('CallInviteEntry', () {
    testWidgets('renders nothing when the user is not eligible',
        (tester) async {
      await pumpEntry(tester, const FeedbackInviteStatus(shouldShow: false));

      expect(find.text(FeedbackCallCopy.entryLine), findsNothing);
      verifyNever(() => mockRepo.markInviteShown());
    });

    testWidgets('shows the slim entry and marks shown once visible',
        (tester) async {
      await pumpEntry(tester, eligible);

      expect(find.text(FeedbackCallCopy.entryLine), findsOneWidget);
      verify(() => mockRepo.markInviteShown()).called(1);
    });

    testWidgets('auto-opens the sheet on the first exposure only',
        (tester) async {
      await pumpEntry(tester, eligible);

      // Auto-déploiement une fois : la modale est là sans aucun tap.
      expect(sheetBookButton, findsOneWidget);

      await tester.tap(find.text(FeedbackCallCopy.ctaLater));
      await tester.pumpAndSettle();
      expect(sheetBookButton, findsNothing);

      // Second passage (nudge `once` déjà consommé) : plus d'auto-ouverture,
      // l'entrée inline reste.
      await pumpEntry(tester, eligible);

      expect(find.text(FeedbackCallCopy.entryLine), findsOneWidget);
      expect(sheetBookButton, findsNothing);
    });

    testWidgets('tapping the entry opens the sheet', (tester) async {
      // Nudge d'auto-ouverture déjà consommé : on isole le tap.
      SharedPreferences.setMockInitialValues({
        'nudge.feedback_call_auto_modal.seen': true,
      });

      await pumpEntry(tester, eligible);
      expect(sheetBookButton, findsNothing);

      await tester.tap(find.text(FeedbackCallCopy.entryLine));
      await tester.pumpAndSettle();

      expect(sheetBookButton, findsOneWidget);
      expect(find.text(FeedbackCallCopy.ctaAlreadyDone), findsOneWidget);
    });
  });
}
