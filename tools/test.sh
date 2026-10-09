#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
OUT_DIR=$REPO_ROOT/out

. "$SCRIPT_DIR/common.sh"
ODIN_ARG=
if [ "${1-}" = '--odin' ]; then
    if [ "$#" -lt 2 ]; then
        echo "Usage: $0 [--odin PATH]" >&2
        exit 2
    fi
    ODIN_ARG=$2
    shift 2
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--odin PATH]" >&2
    exit 2
fi
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)

"$ODIN" build tests "-out:$OUT_DIR/alicorn_tests"
"$OUT_DIR/alicorn_tests"
"$ODIN" build native/sdl_gpu_entry "-extra-linker-flags:$ACCESSKIT_LINK_FLAGS" "-out:$OUT_DIR/alicorn_sdl_gpu"
"$ODIN" test runtime
"$ODIN" test theme
"$ODIN" build tools/theme "-out:$OUT_DIR/alicorn_theme"
"$OUT_DIR/alicorn_theme" check theme/testdata/minimal.json
"$OUT_DIR/alicorn_theme" check theme/testdata/extends_base.json
mkdir -p "$OUT_DIR/theme_codegen_smoke"
"$OUT_DIR/alicorn_theme" compile theme/testdata/minimal.json \
    --output "$OUT_DIR/theme_codegen_smoke/generated.odin" \
    --symbol TEST_THEME --runtime-import ../../runtime
"$ODIN" check "$OUT_DIR/theme_codegen_smoke" -no-entry-point
"$OUT_DIR/alicorn_theme" explain theme/testdata/minimal.json color.primary
if "$OUT_DIR/alicorn_theme" check theme/testdata/invalid.json; then
    echo 'theme CLI accepted an unsupported length unit' >&2
    exit 1
fi
"$ODIN" test native/sdl_gpu "-extra-linker-flags:$ACCESSKIT_LINK_FLAGS" "-out:$OUT_DIR/alicorn_native_tests"
"$OUT_DIR/alicorn_sdl_gpu" --text-input-contract-test
