#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)
OUT_DIR=$REPO_ROOT/out/fixtures/voiceover_gallery

. "$REPO_ROOT/tools/common.sh"
ODIN=$(alicorn_resolve_odin "${ALICORN_ODIN:-}")
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
	build tests/fixtures/voiceover_gallery \
	"-collection:alicorn=$REPO_ROOT" \
	"-out:$OUT_DIR/voiceover_gallery"
exec "$OUT_DIR/voiceover_gallery" "$@"
