#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
HEADER_DIR="$REPO_ROOT/.deps/accesskit/accesskit-c-0.23.1/include"
SOURCE="$REPO_ROOT/tests/accesskit_abi_contract/accesskit_abi_contract.c"
CC=${CC:-cc}

if ! command -v "$CC" >/dev/null 2>&1; then
	printf 'AccessKit ABI contract: C compiler not found: %s\n' "$CC" >&2
	exit 127
fi

if [ ! -f "$HEADER_DIR/accesskit.h" ]; then
	printf 'AccessKit ABI contract: pinned header not found: %s/accesskit.h\n' "$HEADER_DIR" >&2
	printf 'Run the repository AccessKit dependency bootstrap first; this checker does not download dependencies.\n' >&2
	exit 2
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/alicorn-accesskit-abi.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

"$CC" \
	-std=c11 \
	-Wall -Wextra -Werror -Wpedantic \
	-I "$HEADER_DIR" \
	"$SOURCE" \
	-o "$TEMP_DIR/accesskit_abi_contract"

"$TEMP_DIR/accesskit_abi_contract"
