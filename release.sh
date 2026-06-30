#!/usr/bin/env bash
#
# release.sh — trigger a Go toolchain build & release via GitHub Actions.
#
# Usage:
#   ./release.sh [ref] [version]
#
# Defaults:
#   ref     = go4js
#   version = go1.27.0-go4js.1
#
# Examples:
#   ./release.sh                                          # defaults
#   ./release.sh go4js go1.27.0-go4js.2                  # bump patch
#   ./release.sh my-feature-branch go1.27.0-myfork.1     # custom fork
#

set -euo pipefail

REF="${1:-go4js}"
VERSION="${2:-go1.27.0-go4js.1}"

echo "→ Triggering release build..."
echo "  workflow branch: ${REF}"
echo "  ref to build:    ${REF}"
echo "  version tag:     ${VERSION}"
echo

gh workflow run "Build and Release Go Toolchain" \
  --ref "${REF}" \
  -f ref="${REF}" \
  -f version="${VERSION}"

echo
echo "✓ Done. Check progress at:"
echo "  https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/actions"
