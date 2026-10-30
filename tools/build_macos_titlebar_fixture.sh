#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)
if [ "$(uname -s)" != 'Darwin' ]; then
	echo 'The macOS titlebar fixture can only be built on macOS.' >&2
	exit 2
fi

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

SDL3_PREFIX=${SDL3_PREFIX:-}
if [ -z "$SDL3_PREFIX" ]; then
	echo 'Set SDL3_PREFIX to an SDL 3.4.18 installation.' >&2
	exit 2
fi
SDL3_LIBRARY=${SDL3_LIBRARY:-}
if [ -z "$SDL3_LIBRARY" ]; then
	for candidate in \
		"$SDL3_PREFIX/lib/libSDL3.0.dylib" \
		"$SDL3_PREFIX/lib/libSDL3.dylib" \
		"$SDL3_PREFIX/lib/SDL3.dylib"; do
		if [ -f "$candidate" ]; then
			SDL3_LIBRARY=$candidate
			break
		fi
	done
fi
if [ -z "$SDL3_LIBRARY" ] || [ ! -f "$SDL3_LIBRARY" ]; then
	echo "SDL3 dylib not found under SDL3_PREFIX=$SDL3_PREFIX (set SDL3_LIBRARY to override)." >&2
	exit 2
fi
if command -v pkg-config >/dev/null 2>&1 && [ -f "$SDL3_PREFIX/lib/pkgconfig/sdl3.pc" ]; then
	SDL3_VERSION=$(PKG_CONFIG_PATH="$SDL3_PREFIX/lib/pkgconfig" pkg-config --modversion sdl3)
	if [ "$SDL3_VERSION" != '3.4.18' ]; then
		echo "The fixture requires SDL 3.4.18; SDL3_PREFIX provides $SDL3_VERSION." >&2
		exit 2
	fi
fi

ACCESSKIT_LINK_FLAGS=${ALICORN_ACCESSKIT_LINK_FLAGS:-}
if [ -z "$ACCESSKIT_LINK_FLAGS" ]; then
	ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
fi
OUT_ROOT="$REPO_ROOT/out/native-titlebar-fixture"
APP_BUNDLE="$OUT_ROOT/AlicornTitlebarFixture.app"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/AlicornTitlebarFixture"
FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$FRAMEWORKS"
cp "$REPO_ROOT/native/macos_titlebar_fixture_entry/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

cd "$REPO_ROOT"
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS -L$SDL3_PREFIX/lib -Wl,-rpath,@executable_path/../Frameworks" \
	build native/macos_titlebar_fixture_entry \
	"-out:$EXECUTABLE"
cp -L "$SDL3_LIBRARY" "$FRAMEWORKS/SDL3.dylib"
install_name_tool -id @rpath/SDL3.dylib "$FRAMEWORKS/SDL3.dylib"
SDL3_DEPENDENCY=$(otool -L "$EXECUTABLE" | awk '$1 ~ /libSDL3.*dylib/ { print $1; exit }')
if [ -z "$SDL3_DEPENDENCY" ]; then
	echo 'The fixture executable does not link against an SDL3 dylib.' >&2
	exit 1
fi
if [ "$SDL3_DEPENDENCY" != '@rpath/SDL3.dylib' ]; then
	install_name_tool -change "$SDL3_DEPENDENCY" @rpath/SDL3.dylib "$EXECUTABLE"
fi
/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
echo "Built $APP_BUNDLE using $SDL3_LIBRARY"
