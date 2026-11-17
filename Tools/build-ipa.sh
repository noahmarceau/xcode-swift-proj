#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scheme="Forma Local"
if [[ "${1:-}" == "--health" ]]; then scheme="Forma Health"; fi
if ! command -v xcodebuild >/dev/null; then echo 'Run this on a Mac with full Xcode installed.' >&2; exit 1; fi
xcodebuild -project Forma.xcodeproj -scheme "$scheme" -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  -configuration "$( [[ "$scheme" == 'Forma Health' ]] && echo HealthRelease || echo Release )" \
  CODE_SIGNING_ALLOWED=NO build
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/Payload" build
configuration="Release"
if [[ "$scheme" == 'Forma Health' ]]; then configuration="HealthRelease"; fi
cp -R "build/DerivedData/Build/Products/$configuration-iphoneos/Forma.app" "$stage/Payload/"
output="$PWD/build/Forma-unsigned.ipa"
(cd "$stage" && /usr/bin/zip -qry "$output" Payload)
echo "Created $output. Re-sign/install with Sideloadly. Preserve the Live Activity extension."
