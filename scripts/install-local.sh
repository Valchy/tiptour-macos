#!/bin/bash
# Build TipTour ad-hoc (no Apple Developer identity) and install it to ~/Applications.
#
# Why the explicit designated requirement: an ad-hoc signature's default
# requirement is the binary's cdhash, which changes on every build, so macOS
# treats each build as a new app and the Accessibility / Screen Recording
# switches in System Settings silently stop applying. Pinning the requirement
# to the bundle identifier keeps those grants valid across rebuilds.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bundle_identifier="com.milindsoni.tiptour"
installed_app="$HOME/Applications/TipTour.app"

xcodebuild build -project "$project_dir/tiptour-macos.xcodeproj" -scheme tiptour-macos \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$project_dir/build/DerivedData" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
  > "$project_dir/build/xcodebuild.log" 2>&1 || { tail -30 "$project_dir/build/xcodebuild.log"; exit 1; }

osascript -e 'tell application "TipTour" to quit' 2>/dev/null || true
rm -rf "$installed_app"
ditto "$project_dir/build/DerivedData/Build/Products/Release/TipTour.app" "$installed_app"
codesign --force --sign - --preserve-metadata=entitlements,flags \
  -r="designated => identifier \"$bundle_identifier\"" "$installed_app"
codesign --verify --deep --strict "$installed_app"
defaults write "$bundle_identifier" SUEnableAutomaticChecks -bool NO
open "$installed_app"
echo "Installed and launched $installed_app"
