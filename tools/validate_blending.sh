#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
. "$SCRIPT_DIR/common.sh"
ODIN_ARG=
if [ "${1-}" = '--odin' ]; then
    if [ "$#" -lt 2 ]; then echo "Usage: $0 [--odin PATH]" >&2; exit 2; fi
    ODIN_ARG=$2; shift 2
fi
if [ "$#" -ne 0 ]; then echo "Usage: $0 [--odin PATH]" >&2; exit 2; fi
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
cd "$REPO_ROOT"
mkdir -p out
case "$(uname -s)" in
    Darwin)
        ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
        ;;
        *) echo 'Use tools/validate_blending.ps1 on Windows or tools/validate_blending.sh on macOS.' >&2; exit 1 ;;
esac
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
	build native/blend_validation_entry -out:out/alicorn_blend_validation
exec ./out/alicorn_blend_validation
