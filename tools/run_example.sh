#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
OUT_DIR=$REPO_ROOT/out/examples

. "$SCRIPT_DIR/common.sh"
ODIN_ARG=
SPEED=no
while [ "$#" -gt 0 ]; do
	case "$1" in
		--odin)
			if [ "$#" -lt 2 ]; then echo "Usage: $0 [--odin PATH] [--speed] EXAMPLE [APP_ARGUMENT ...]" >&2; exit 2; fi
			ODIN_ARG=$2
			shift 2
			;;
		--speed) SPEED=yes; shift ;;
		*) break ;;
	esac
done
if [ "$#" -lt 1 ]; then
	echo "Usage: $0 [--odin PATH] [--speed] EXAMPLE [APP_ARGUMENT ...]" >&2
	exit 2
fi

EXAMPLE=$1
shift
case "$EXAMPLE" in
	01_hello|02_form|03_async_list|04_custom_surface|05_inspector|06_secondary_windows|07_simple_appearance) ;;
	*) echo "Unknown numbered example: $EXAMPLE" >&2; exit 2 ;;
esac

ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
EXECUTABLE=$OUT_DIR/$EXAMPLE

cd "$REPO_ROOT"
mkdir -p "$OUT_DIR"
if [ "$SPEED" = yes ]; then
	alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
		build "examples/$EXAMPLE" "-collection:alicorn=$REPO_ROOT" -o:speed "-out:$EXECUTABLE"
else
	alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" \
		build "examples/$EXAMPLE" "-collection:alicorn=$REPO_ROOT" "-out:$EXECUTABLE"
fi
exec "$EXECUTABLE" "$@"
