#!/bin/bash
cd "/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/apps/mobile"
echo "Starting Flutter Widget Test..."
flutter test test/features/auth/router_redirection_test.dart > widget_test_proof_final.txt 2>&1
echo "Test Finished. Result in widget_test_proof_final.txt"
