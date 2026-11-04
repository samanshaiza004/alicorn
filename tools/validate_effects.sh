#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
. "$SCRIPT_DIR/common.sh"
ODIN_ARG=
if [ "${1-}" = '--odin' ]; then
    if [ "$#" -lt 2 ]; then echo "Usage: $0 [--odin PATH] [--driver=metal|vulkan|direct3d12]" >&2; exit 2; fi
    ODIN_ARG=$2
    shift 2
fi
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
cd "$REPO_ROOT"
mkdir -p out/retained-effects
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
    test native/sdl_gpu -define:ALICORN_RETAINED_EFFECTS_EXPERIMENT=true -out:out/alicorn_effects_tests
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
    build native/effects_validation_entry -o:speed -define:ALICORN_RETAINED_EFFECTS_EXPERIMENT=true -out:out/alicorn_effects_validation
exec ./out/alicorn_effects_validation "$@"
