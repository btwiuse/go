#!/usr/bin/env bash
# 精简 Go distpack：去掉 testdata/*_test.go/test/fuzz 等运行时不需要的文件
# Usage: ./minify-go-distpack.sh <input.tar.gz> [output.tar.gz]

set -euo pipefail
IN="$1"
OUT="${2:-${IN%.tar.gz}.min.tar.gz}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

tar xzf "$IN" -C "$TMP"
rm -rf "$TMP/go/test"
find "$TMP/go/src" -type d -name testdata -exec rm -rf {} + 2>/dev/null || true
find "$TMP/go/src" -name '*_test.go' -delete
find "$TMP/go/src" -name '*.zsparse' -delete
rm "$TMP/go/minify-go-distpack.sh"
rm -r "$TMP/go/api"
tar czf "$OUT" -C "$TMP" go

echo "$(tar tzf "$IN" | grep -vc '/$') → $(tar tzf "$OUT" | grep -vc '/$') 文件"
echo "$(du -h "$IN" | cut -f1) → $(du -h "$OUT" | cut -f1)"
