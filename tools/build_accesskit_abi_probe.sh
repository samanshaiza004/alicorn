#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
OUTPUT_DIR=$1
HEADER_DIR="$REPO_ROOT/.deps/accesskit/accesskit-c-0.23.1/include"
SOURCE="$REPO_ROOT/tests/accesskit_abi_contract/accesskit_abi_round_trip.c"
CC=${CC:-cc}
AR=${AR:-ar}

if [ -z "$OUTPUT_DIR" ]; then
	echo "Usage: build_accesskit_abi_probe.sh OUTPUT_DIR" >&2
	exit 2
fi
if [ ! -f "$HEADER_DIR/accesskit.h" ]; then
	echo "AccessKit ABI probe: pinned header not found: $HEADER_DIR/accesskit.h" >&2
	exit 2
fi
command -v "$CC" >/dev/null 2>&1 || { echo "C compiler not found: $CC" >&2; exit 127; }
command -v "$AR" >/dev/null 2>&1 || { echo "archiver not found: $AR" >&2; exit 127; }

mkdir -p "$OUTPUT_DIR"
"$CC" -std=c11 -Wall -Wextra -Werror -Wpedantic -I "$HEADER_DIR" \
	-c "$SOURCE" -o "$OUTPUT_DIR/accesskit_abi_round_trip.o"
"$AR" rcs "$OUTPUT_DIR/libalicorn_accesskit_abi_probe.a" \
	"$OUTPUT_DIR/accesskit_abi_round_trip.o"
printf '%s\n' "-L$OUTPUT_DIR"
