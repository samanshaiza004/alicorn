#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUT_DIR=$REPO_ROOT/out
. "$SCRIPT_DIR/common.sh"
ODIN_ARG=${1:-}
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
"$ODIN" build examples/durable_restoration "-out:$OUT_DIR/durable-restoration"
SESSION="$OUT_DIR/restoration-session.json"
for MODE in --write --read --narrow --short; do
    "$OUT_DIR/durable-restoration" "$MODE" "$SESSION"
done
MISSING=$(mktemp -d)
trap 'rmdir "$MISSING"' EXIT HUP INT TERM
"$OUT_DIR/durable-restoration" --defaults "$MISSING/missing.json"
for DATA in '{broken' '{"version":999}' '{"version":1,"split_ratio":1e40}'; do
    printf '%s' "$DATA" > "$OUT_DIR/invalid-restoration-session.json"
    "$OUT_DIR/durable-restoration" --defaults "$OUT_DIR/invalid-restoration-session.json"
done
