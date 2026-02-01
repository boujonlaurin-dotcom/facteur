#!/bin/bash
# Verify Fix Essentials via Python Robust Script

echo "🚀 Starting Verification: Daily Briefing Lazy Generation"
cd packages/api
.venv/bin/python3 scripts/verify_lazy_gen.py

if [ $? -eq 0 ]; then
    echo "🎉 SUCCESS: Lazy Generation works!"
    exit 0
else
    echo "💥 FAILURE: Verification failed."
    exit 1
fi
