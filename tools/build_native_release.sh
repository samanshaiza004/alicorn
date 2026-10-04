#!/bin/bash
set -eu

usage() {
	cat >&2 <<'EOF'
Usage: build_native_release.sh [--odin PATH] [--metadata package.json] \
  [--sdl-linkage static|shared] [--output DIRECTORY] [--skip-smoke-test]
EOF
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
ODIN_ARG=
METADATA=examples/01_hello/package.json
SDL_LINKAGE=static
OUTPUT=out/native-package/macos
SMOKE=1
while [ "$#" -gt 0 ]; do
	case "$1" in
		--odin) ODIN_ARG=$2; shift 2 ;;
		--metadata) METADATA=$2; shift 2 ;;
		--sdl-linkage) SDL_LINKAGE=$2; shift 2 ;;
		--output) OUTPUT=$2; shift 2 ;;
		--skip-smoke-test) SMOKE=0; shift ;;
		*) usage; exit 2 ;;
	esac
done
case "$SDL_LINKAGE" in static|shared) ;; *) usage; exit 2 ;; esac

. "$SCRIPT_DIR/common.sh"
ODIN=$(alicorn_resolve_odin "$ODIN_ARG")
METADATA_PATH="$REPO_ROOT/$METADATA"
[ -f "$METADATA_PATH" ] || { echo "Metadata file not found: $METADATA_PATH" >&2; exit 2; }
APP_PACKAGE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["odinPackage"])' "$METADATA_PATH")
APP_NAME=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["executableName"])' "$METADATA_PATH")
OUT_ROOT="$REPO_ROOT/out/native-package"
SDL_ROOT="$OUT_ROOT/sdl-3.4.16"
ARCHIVE="$SDL_ROOT/SDL3-3.4.16.tar.gz"
SOURCE="$SDL_ROOT/source"
BUILD="$SDL_ROOT/build"
PREFIX="$SDL_ROOT/prefix"
SDL_URL='https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz'
SDL_SHA='7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68'
mkdir -p "$SDL_ROOT"

for tool in cmake tar shasum python3; do
	command -v "$tool" >/dev/null 2>&1 || { echo "Required packaging tool not found: $tool" >&2; exit 127; }
done
if [ ! -f "$ARCHIVE" ]; then curl -fL "$SDL_URL" -o "$ARCHIVE"; fi
ACTUAL_SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
[ "$ACTUAL_SHA" = "$SDL_SHA" ] || { echo "Pinned SDL source checksum mismatch: $ACTUAL_SHA" >&2; exit 1; }
if [ ! -f "$SOURCE/CMakeLists.txt" ]; then
	mkdir -p "$SOURCE"
	tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE"
fi
SDL_LICENSE="$SOURCE/LICENSE.txt"
[ -f "$SDL_LICENSE" ] || { echo 'Pinned SDL source is missing LICENSE.txt.' >&2; exit 1; }

SDL_LINK_FLAGS=
SDL_RUNTIME=
SDL_VERSION=3.4.16
if [ "$SDL_LINKAGE" = static ]; then
	if [ ! -f "$BUILD/CMakeCache.txt" ]; then
		cmake -S "$SOURCE" -B "$BUILD" \
			-DCMAKE_BUILD_TYPE=Release \
			-DCMAKE_INSTALL_PREFIX="$PREFIX" \
			-DSDL_SHARED=OFF -DSDL_STATIC=ON \
			-DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF \
			-DSDL_INSTALL_TESTS=OFF -DSDL_DISABLE_INSTALL_DOCS=ON \
			-DSDL_FRAMEWORK=OFF -DSDL_RPATH=OFF
	fi
	cmake --build "$BUILD" --config Release --target SDL3-static
	cmake --install "$BUILD" --config Release
	command -v pkg-config >/dev/null 2>&1 || { echo 'Static SDL link flags require pkg-config (install pkgconf).'; exit 127; }
	SDL_LINK_FLAGS="-L$PREFIX/lib"
	SDL_LINK_FLAGS="$SDL_LINK_FLAGS $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --static --libs-only-other sdl3)"
else
	command -v brew >/dev/null 2>&1 || { echo 'Shared SDL packaging requires Homebrew SDL3.' >&2; exit 1; }
	SDL_PREFIX=$(brew --prefix sdl3)
	SDL_VERSION=$(PKG_CONFIG_PATH="$SDL_PREFIX/lib/pkgconfig" pkg-config --modversion sdl3)
	SDL_RUNTIME=$(find "$SDL_PREFIX/lib" -maxdepth 1 -type f -name 'libSDL3*.dylib' | sort | head -n 1)
	[ -n "$SDL_RUNTIME" ] || { echo "No SDL3 dylib found under $SDL_PREFIX/lib." >&2; exit 1; }
	SDL_LINK_FLAGS="-L$SDL_PREFIX/lib"
fi

BUILT="$OUT_ROOT/$APP_NAME"
cd "$REPO_ROOT"
if [ -n "$SDL_LINK_FLAGS" ]; then
	"$ODIN" build "$APP_PACKAGE" "-out:$BUILT" -o:speed "-extra-linker-flags:$SDL_LINK_FLAGS"
else
	"$ODIN" build "$APP_PACKAGE" "-out:$BUILT" -o:speed
fi

PACKAGE_ARGS=(
	"$SCRIPT_DIR/package_macos.py"
	--executable "$BUILT"
	--metadata "$METADATA_PATH"
	--linkage "$SDL_LINKAGE"
	--sdl-version "$SDL_VERSION"
	--sdl-license "$SDL_LICENSE"
)
case "$OUTPUT" in
	/*) PACKAGE_ARGS+=(--output "$OUTPUT") ;;
	*) PACKAGE_ARGS+=(--output "$REPO_ROOT/$OUTPUT") ;;
esac
if [ -n "$SDL_RUNTIME" ]; then PACKAGE_ARGS+=(--sdl-runtime "$SDL_RUNTIME"); fi
if [ "$SMOKE" -eq 1 ]; then PACKAGE_ARGS+=(--smoke-test); fi
python3 "${PACKAGE_ARGS[@]}"
