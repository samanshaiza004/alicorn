#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
OUT_DIR=$REPO_ROOT/out
. "$SCRIPT_DIR/common.sh"

ODIN_ARG=
if [ "${1-}" = '--odin' ]; then
	if [ "$#" -lt 2 ]; then echo "Usage: $0 [--odin PATH]" >&2; exit 2; fi
	ODIN_ARG=$2
	shift 2
fi
SMOKE=no
if [ "${1-}" = '--smoke' ]; then SMOKE=yes; shift; fi
if [ "$#" -ne 0 ]; then echo "Usage: $0 [--odin PATH] [--smoke]" >&2; exit 2; fi
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
"$ODIN" build examples/04_custom_surface "-extra-linker-flags:$ACCESSKIT_LINK_FLAGS" "-out:$OUT_DIR/alicorn_custom_surface"
if [ "$SMOKE" = yes ]; then
	exec "$OUT_DIR/alicorn_custom_surface" --smoke
fi
exec "$OUT_DIR/alicorn_custom_surface"
