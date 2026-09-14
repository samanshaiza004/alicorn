#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
OUT_DIR=$REPO_ROOT/out

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"

if [ -n "${ALICORN_ODIN:-}" ]; then
    case "$ALICORN_ODIN" in
        */*)
            if [ ! -x "$ALICORN_ODIN" ]; then
                echo "Odin executable not found or not executable: $ALICORN_ODIN (from ALICORN_ODIN)" >&2
                exit 127
            fi
            ODIN=$ALICORN_ODIN
            ;;
        *)
            ODIN=$(command -v "$ALICORN_ODIN" 2>/dev/null || true)
            if [ -z "$ODIN" ] || [ ! -x "$ODIN" ]; then
                echo "Odin executable not found in PATH: $ALICORN_ODIN (from ALICORN_ODIN)" >&2
                exit 127
            fi
            ;;
    esac
else
    ODIN=$(command -v odin 2>/dev/null || true)
    if [ -z "$ODIN" ] || [ ! -x "$ODIN" ]; then
        echo "Odin executable not found in PATH. Install Odin or set ALICORN_ODIN." >&2
        exit 127
    fi
fi

"$ODIN" build tests "-out:$OUT_DIR/alicorn_tests"
"$OUT_DIR/alicorn_tests"
