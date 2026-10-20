#!/bin/sh

# Install the complete, supported Odin SDK into a fresh caller-owned directory.
set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: sh tools/setup_macos_odin.sh /absolute/path/to/new/odin-directory" >&2
	exit 2
fi
destination=$1
case "$destination" in
	/*) ;;
	*) echo 'Odin destination must be an absolute path.' >&2; exit 2 ;;
esac
if [ -e "$destination" ] || [ -L "$destination" ]; then
	echo "Odin destination already exists: $destination. Choose a fresh directory." >&2
	exit 1
fi
if [ "$(uname -s)" != Darwin ]; then
	echo 'This Odin bootstrap supports macOS only.' >&2
	exit 1
fi

# Official dev-2026-09 assets contain the September 1 nightly (a2fb372).
# Digests: https://api.github.com/repos/odin-lang/Odin/releases/tags/dev-2026-09
release=dev-2026-09
expected_version=dev-2026-09-nightly:a2fb372
case "$(uname -m)" in
	arm64|aarch64)
		arch=arm64
		sha=3e6cbc1f247d8d14fe02c3151272d0a5b8d6d77acb7219f5b62914e4d95d97f7
		;;
	x86_64)
		arch=amd64
		sha=c1f6d6320218ec7e511093a87bdd599b72a8417a9d2a00de2c9691103562165b
		;;
	*) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac
archive=odin-macos-$arch-$release.tar.gz
url=https://github.com/odin-lang/Odin/releases/download/$release/$archive

parent=$(dirname -- "$destination")
mkdir -p "$parent"
stage=$(mktemp -d "$parent/.alicorn-odin.XXXXXX")
trap 'rm -r "$stage"' 0
trap 'exit 1' 1 2 15

echo "Downloading $url"
curl --fail --location --silent --show-error --retry 3 "$url" -o "$stage/$archive"
actual_sha=$(shasum -a 256 "$stage/$archive" | awk '{print $1}')
if [ "$actual_sha" != "$sha" ]; then
	echo "Odin $release SHA-256 mismatch. Expected $sha; got $actual_sha." >&2
	exit 1
fi
echo "Verified SHA-256: $sha"
mkdir "$stage/sdk"
tar -xzf "$stage/$archive" --strip-components=1 -C "$stage/sdk"
for directory in base core vendor shared; do
	if [ ! -d "$stage/sdk/$directory" ]; then
		echo "Verified Odin archive is missing SDK directory: $directory" >&2
		exit 1
	fi
done
version=$(ODIN_ROOT="$stage/sdk" "$stage/sdk/odin" version)
case "$version" in
	*" version $expected_version") ;;
	*) echo "Unexpected Odin compiler version: $version" >&2; exit 1 ;;
esac
mv "$stage/sdk" "$destination"
echo "Installed Odin at $destination ($expected_version)"
echo 'Use this directory for PATH and ODIN_ROOT, and its odin executable for ALICORN_ODIN.'
