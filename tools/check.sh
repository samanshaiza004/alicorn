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

git diff --check

"$ODIN" build tests "-out:$OUT_DIR/alicorn_tests"
"$ODIN" build benchmarks "-out:$OUT_DIR/alicorn_benchmarks"
"$ODIN" build examples/identity_torture "-out:$OUT_DIR/identity_torture"
"$ODIN" build examples/crucible "-out:$OUT_DIR/crucible"
"$ODIN" build examples/runa_text "-out:$OUT_DIR/runa_text"

"$OUT_DIR/alicorn_tests"
"$ODIN" test runtime
