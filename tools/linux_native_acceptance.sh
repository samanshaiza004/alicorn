#!/bin/sh

# Repeatable Linux evidence runner. It records automated results without
# treating a native session as proof of physical interaction or platform UX.
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)

. "$SCRIPT_DIR/common.sh"

ODIN_ARG=
REPORT_DIR="$REPO_ROOT/out/linux-native-acceptance"
HEADLESS_ONLY=no

usage() {
	cat >&2 <<'EOF'
Usage: tools/linux_native_acceptance.sh [options]

Options:
  --odin PATH          Odin executable to use
  --report-dir PATH    Evidence directory (default: out/linux-native-acceptance)
  --headless           Run only checks that do not require a display session
  --help               Show this help

The native portion requires a Wayland session and forces SDL's Wayland/Vulkan
selection. The report contains logs, environment probes, and summary.tsv.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--odin)
			if [ "$#" -lt 2 ]; then usage; exit 2; fi
			ODIN_ARG=$2
			shift 2
			;;
		--report-dir)
			if [ "$#" -lt 2 ]; then usage; exit 2; fi
			REPORT_DIR=$2
			shift 2
			;;
		--headless)
			HEADLESS_ONLY=yes
			shift
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			exit 2
			;;
	esac
done

if [ "$(uname -s)" != Linux ]; then
	echo "This runner is Linux-only." >&2
	exit 2
fi

ODIN=$(alicorn_resolve_odin "$ODIN_ARG") || exit $?

case "$REPORT_DIR" in
	/*) ;;
	*) REPORT_DIR="$REPO_ROOT/$REPORT_DIR" ;;
esac
mkdir -p "$REPORT_DIR/logs"
REPORT_DIR=$(CDPATH='' cd -- "$REPORT_DIR" && pwd -P)
LOG_DIR="$REPORT_DIR/logs"
SUMMARY="$REPORT_DIR/summary.tsv"
COMMANDS="$REPORT_DIR/commands.txt"

if [ "$HEADLESS_ONLY" = no ]; then
	if [ "${XDG_SESSION_TYPE:-}" != wayland ] || [ -z "${WAYLAND_DISPLAY:-}" ] || [ -z "${XDG_RUNTIME_DIR:-}" ]; then
		cat >&2 <<'EOF'
A Wayland session is required for the native portion of this matrix.
Use --headless for compile and contract checks only; that mode does not
validate window-manager, compositor, GPU, or physical interaction behavior.
EOF
		exit 2
	fi
	if [ "${SDL_VIDEO_DRIVER:-wayland}" != wayland ]; then
		echo "SDL_VIDEO_DRIVER must be 'wayland' for this matrix." >&2
		exit 2
	fi
	if [ "${SDL_GPU_DRIVER:-vulkan}" != vulkan ]; then
		echo "SDL_GPU_DRIVER must be 'vulkan' for this matrix." >&2
		exit 2
	fi
	export SDL_VIDEO_DRIVER=wayland
	export SDL_GPU_DRIVER=vulkan
fi

printf 'gate\tstatus\tlog\n' > "$SUMMARY"
: > "$COMMANDS"

record_status() {
	printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$SUMMARY"
}

record_command() {
	name=$1
	shift
	{
		printf '%s:' "$name"
		for argument in "$@"; do printf ' %s' "$argument"; done
		printf '\n'
	} >> "$COMMANDS"
}

run_required() {
	name=$1
	shift
	log="$LOG_DIR/$name.log"
	record_command "$name" "$@"
	if "$@" > "$log" 2>&1; then
		record_status "$name" PASS "$log"
		printf 'PASS %s\n' "$name"
		return 0
	fi
	record_status "$name" FAIL "$log"
	printf 'FAIL %s (see %s)\n' "$name" "$log" >&2
	cat "$log" >&2
	failed=1
	return 1
}

run_probe() {
	name=$1
	shift
	log="$LOG_DIR/$name.log"
	if ! command -v "$1" >/dev/null 2>&1; then
		: > "$log"
		record_status "$name" SKIP "$log"
		printf 'SKIP %s (command unavailable)\n' "$name"
		return 0
	fi
	record_command "$name" "$@"
	if "$@" > "$log" 2>&1; then
		record_status "$name" PASS "$log"
		printf 'PASS %s\n' "$name"
	else
		record_status "$name" WARN "$log"
		printf 'WARN %s (see %s)\n' "$name" "$log"
	fi
}

record_skip() {
	name=$1
	log="$LOG_DIR/$name.log"
	: > "$log"
	record_status "$name" SKIP "$log"
	printf 'SKIP %s\n' "$name"
}

{
	printf 'git_revision=%s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
	printf 'odin_path=%s\n' "$ODIN"
	printf 'odin_version='
	"$ODIN" version 2>&1 || true
	printf 'kernel='
	uname -srvm
	for variable in XDG_SESSION_TYPE WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR XDG_CURRENT_DESKTOP DESKTOP_SESSION SDL_VIDEO_DRIVER SDL_GPU_DRIVER; do
		value=$(printenv "$variable" 2>/dev/null || true)
		printf '%s=%s\n' "$variable" "$value"
	done
	git -C "$REPO_ROOT" status --short
} > "$REPORT_DIR/environment.txt"

failed=0

# These gates are deterministic and do not establish desktop or hardware UX.
run_required headless-check sh "$SCRIPT_DIR/check.sh" --odin "$ODIN"
run_required native-contracts sh "$SCRIPT_DIR/test.sh" --odin "$ODIN"
run_required text-input-contract sh "$SCRIPT_DIR/native_sdl_gpu.sh" --odin "$ODIN" --text-input-contract-test
run_required surface-geometry-contract sh "$SCRIPT_DIR/native_sdl_gpu.sh" --odin "$ODIN" --surface-geometry-test

# Tool output is evidence about the current host, not a portability claim.
run_probe nix-version nix --version
run_probe nixos-version nixos-version
run_probe pkg-config-sdl3 pkg-config --modversion sdl3
run_probe fontconfig-default fc-match --format=%{file} 'DejaVu Sans'
run_probe vulkan-summary vulkaninfo --summary
run_probe wayland-protocols wayland-info
run_probe mango-version mango -v

if [ "$HEADLESS_ONLY" = yes ]; then
	record_skip example-runner-hello
	record_skip example-runner-async-list
	record_skip native-surface-smoke
	record_skip native-surface-stress
	record_skip native-diagnostic-capture
else
	# These runs exercise the real Wayland/Vulkan host, but their output is
	# still not a substitute for a person using a keyboard, pointer, or IME.
	run_required example-runner-hello sh "$SCRIPT_DIR/run_example.sh" --odin "$ODIN" 01_hello --idle-validation-seconds=2
	run_required example-runner-async-list sh "$SCRIPT_DIR/run_example.sh" --odin "$ODIN" 03_async_list --smoke
	run_required native-surface-smoke sh "$SCRIPT_DIR/custom_surface.sh" --odin "$ODIN" --smoke
	run_required native-surface-stress sh "$SCRIPT_DIR/native_sdl_gpu.sh" --odin "$ODIN" --surface-stress
	run_required native-diagnostic-capture "$REPO_ROOT/out/alicorn_custom_surface" \
		--smoke --diagnostics --capture-after=0 --capture-dir="$REPORT_DIR/diagnostics"
fi

printf '\nEvidence directory: %s\n' "$REPORT_DIR"
printf 'Summary: %s\n' "$SUMMARY"
if [ "$failed" -ne 0 ]; then
	printf 'Automated Linux validation: FAIL\n' >&2
	exit 1
fi
printf 'Automated Linux validation: PASS\n'
