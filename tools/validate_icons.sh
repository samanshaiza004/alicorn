#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
. "$SCRIPT_DIR/common.sh"
ODIN_ARG=
if [ "${1-}" = '--odin' ]; then ODIN_ARG=$2; shift 2; fi
if [ "$#" -ne 0 ]; then echo "Usage: $0 [--odin PATH]" >&2; exit 2; fi
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
cd "$REPO_ROOT"
mkdir -p out
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
	build native/icon_validation_entry -out:out/alicorn_icon_validation
exec ./out/alicorn_icon_validation
