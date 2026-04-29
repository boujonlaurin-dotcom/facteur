# Facteur — CLI tools for local development and Claude Code hooks.
# Run once: brew bundle
tap "supabase/tap"
tap "getsentry/tools"
tap "railwayapp/railway"

brew "pyenv"
brew "supabase"
brew "sentry-cli"
brew "railway"
brew "gitleaks"
# CocoaPods entre en conflit avec le binaire `xcodeproj` standalone (déjà installé
# par certains setups Ruby) — on force le link pour exposer `pod` dans /usr/local/bin.
brew "cocoapods", postinstall: "brew link --overwrite cocoapods"
cask "flutter"
