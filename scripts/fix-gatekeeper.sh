#!/usr/bin/env bash
# Helper builds from GitHub aren't notarized yet. If macOS says the app is
# "damaged" or from an unidentified developer, run this once after copying
# Helper.app to /Applications.
set -euo pipefail
APP="${1:-/Applications/Helper.app}"
xattr -dr com.apple.quarantine "$APP"
echo "✓ Cleared the quarantine flag on $APP — open it normally now."
