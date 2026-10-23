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
# This validation runner uses existing dependencies and never bootstraps them.
ACCESSKIT_LINK_FLAGS=
case "$(uname -s)" in
    Darwin)
        case "$(uname -m)" in
            arm64|aarch64) ACCESSKIT_ARCH=arm64 ;;
            x86_64) ACCESSKIT_ARCH=x86_64 ;;
            *) echo 'Unsupported macOS architecture for the cached AccessKit library.' >&2; exit 1 ;;
        esac
        ACCESSKIT_DIR=".deps/accesskit/accesskit-c-0.23.1/lib/macos/$ACCESSKIT_ARCH/static"
        if [ ! -f "$ACCESSKIT_DIR/libaccesskit.a" ]; then
            echo "Existing AccessKit static library required: $ACCESSKIT_DIR/libaccesskit.a" >&2
            exit 1
        fi
        ACCESSKIT_LINK_FLAGS="-L$ACCESSKIT_DIR -framework AppKit -framework Foundation -framework CoreFoundation -lobjc -lc++"
        ;;
    Linux) ;;
    *) echo 'Use tools/validate_blending.ps1 on Windows.' >&2; exit 1 ;;
esac
"$ODIN" build native/blend_validation_entry "-extra-linker-flags:$ACCESSKIT_LINK_FLAGS" -out:out/alicorn_blend_validation
exec ./out/alicorn_blend_validation
