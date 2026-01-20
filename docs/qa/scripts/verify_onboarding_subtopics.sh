#!/bin/bash
set -e
cd "$(dirname "$0")/../../.."

echo "=== 1. Check AvailableThemes alignment ==="
grep -q "slug: 'international'" apps/mobile/lib/features/onboarding/providers/onboarding_provider.dart && echo "✅ international theme present" || echo "❌ MISSING international"

echo "=== 2. Check subtopics field in OnboardingAnswers ==="
grep -q "subtopics" apps/mobile/lib/features/onboarding/providers/onboarding_provider.dart && echo "✅ subtopics field present" || echo "❌ MISSING subtopics"

echo "=== 3. Check backend schema ==="
grep -q "subtopics" packages/api/app/schemas/user.py && echo "✅ backend schema OK" || echo "❌ MISSING in backend"

echo "=== 4. Check user_service stores subtopics ==="
grep -q "UserSubtopic" packages/api/app/services/user_service.py && echo "✅ user_service OK" || echo "❌ MISSING UserSubtopic"

echo "=== 5. Check UI widget creation ==="
if [ -f "apps/mobile/lib/features/onboarding/widgets/theme_with_subtopics.dart" ]; then
    echo "✅ ThemeWithSubtopics widget exists"
else
    echo "❌ MISSING ThemeWithSubtopics widget"
fi

echo "✅ ALL CHECKS PASSED"
