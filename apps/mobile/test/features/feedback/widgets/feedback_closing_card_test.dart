import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feedback/models/feedback_models.dart';
import 'package:facteur/features/feedback/providers/feedback_providers.dart';
import 'package:facteur/features/feedback/repositories/feedback_repository.dart';
import 'package:facteur/features/feedback/widgets/feedback_closing_card.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late MockFeedbackRepository mockRepo;

  setUpAll(() => registerFallbackValue(DateTime(2024, 1, 1)));

  setUp(() {
    mockRepo = MockFeedbackRepository();
    when(() => mockRepo.markInviteShown()).thenAnswer((_) async {});
    when(() => mockRepo.submitSentiment(any(), date: any(named: 'date')))
        .thenAnswer((_) async {});
  });

  Widget createWidget(FeedbackInviteStatus status) {
    return ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(mockRepo),
        inviteStatusProvider.overrideWith((ref) async => status),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: FeedbackClosingCard()),
        ),
      ),
    );
  }

  group('FeedbackClosingCard', () {
    testWidgets('always shows the emoji micro-feedback', (tester) async {
      await tester.pumpWidget(
        createWidget(const FeedbackInviteStatus(shouldShow: false)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('TON AVIS'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
    });

    testWidgets('hides the call CTA when not eligible', (tester) async {
      await tester.pumpWidget(
        createWidget(const FeedbackInviteStatus(shouldShow: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Discuter avec Laurin'), findsNothing);
      verifyNever(() => mockRepo.markInviteShown());
    });

    testWidgets('shows the call CTA and marks shown when eligible',
        (tester) async {
      await tester.pumpWidget(
        createWidget(
          const FeedbackInviteStatus(shouldShow: true, segment: 'active'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Discuter avec Laurin'), findsOneWidget);
      verify(() => mockRepo.markInviteShown()).called(1);
    });
  });
}
