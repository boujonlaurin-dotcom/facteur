#!/bin/bash
echo "Current directory: $(pwd)"
echo "Git status:"
git status
echo "Git remote:"
git remote -v
echo "Current branch:"
git branch --show-current
echo "Attempting to push..."
git push origin main 2>&1
echo "Push attempt finished."
