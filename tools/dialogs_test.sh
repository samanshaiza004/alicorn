#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
. "$script_dir/common.sh"
odin_arg=
if [ "${1-}" = '--odin' ]; then
	if [ "$#" -lt 2 ]; then
		echo "Usage: $0 [--odin PATH]" >&2
		exit 2
	fi
	odin_arg=$2
	shift 2
fi
if [ "$#" -ne 0 ]; then
	echo "Usage: $0 [--odin PATH]" >&2
	exit 2
fi
odin_command=$(alicorn_resolve_odin "$odin_arg")
cd "$repo_root"

mkdir -p out
"$odin_command" build native/dialogs_fake_test -out:out/alicorn_dialogs_fake_test
exec ./out/alicorn_dialogs_fake_test
