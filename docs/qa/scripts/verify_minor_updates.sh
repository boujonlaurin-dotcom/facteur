#!/bin/bash

# Verification script for minor UI and logo updates
echo "Verifying UI and Logo updates..."

# 1. Check font size in FeedCard
if grep -q "fontSize: 20" apps/mobile/lib/features/feed/widgets/feed_card.dart; then
    echo "[OK] FeedCard title font size is 20px"
else
    echo "[FAIL] FeedCard title font size is NOT 20px"
    exit 1
fi

# 2. Check FacteurLogo refactoring
if ! grep -q "defaultTargetPlatform == TargetPlatform.android" apps/mobile/lib/widgets/design/facteur_logo.dart; then
    echo "[OK] FacteurLogo no longer has Android-specific override"
else
    echo "[FAIL] FacteurLogo still has Android-specific override"
    exit 1
fi

# 3. Check Android icon de-zoom (inset)
if grep -q "<inset android:drawable=\"@mipmap/launcher_icon\" android:inset=\"18%\" />" apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml; then
    echo "[OK] Android app icon has 18% inset applied"
else
    echo "[FAIL] Android app icon does NOT have 18% inset"
    exit 1
fi

echo "All code verifications PASSED."
