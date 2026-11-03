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

# The November Apple Silicon archive is the November 1 nightly. The monthly
# release does not publish an Intel macOS binary; Intel hosts build its signed
# source tag with the prerequisites described in Odin's installation guide.
# Digests: https://api.github.com/repos/odin-lang/Odin/releases/tags/dev-2026-11
release=dev-2026-11
expected_archive_version=dev-2026-11-nightly:9a69916
expected_source_commit=e28f5d1
source_build=0
case "$(uname -m)" in
	arm64|aarch64)
		arch=arm64
		sha=fa10eee280c8786758e3ff0b8fdd9355e1c9447b1f0b8c72764e25ee4ebc3e22
		;;
	x86_64)
		source_build=1
		;;
	*) echo "Unsupported macOS architecture: $(uname -m)" >&2; exit 1 ;;
esac

parent=$(dirname -- "$destination")
mkdir -p "$parent"
stage=$(mktemp -d "$parent/.alicorn-odin.XXXXXX")
trap 'rm -r "$stage"' 0
trap 'exit 1' 1 2 15

if [ "$source_build" -eq 1 ]; then
	for tool in git git-lfs make; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Intel macOS Odin bootstrap requires '$tool'. Install Xcode Command Line Tools, Homebrew LLVM 17–22, and Git LFS, then retry." >&2
			exit 1
		fi
	done
	source_root="$stage/source"
	echo "Cloning Odin $release source for macOS Intel"
	git clone --quiet --depth 1 --branch "$release" --single-branch https://github.com/odin-lang/Odin.git "$source_root"
	git -C "$source_root" lfs install --local >/dev/null
	git -C "$source_root" lfs pull
	actual_commit=$(git -C "$source_root" rev-parse --short=7 HEAD)
	if [ "$actual_commit" != "$expected_source_commit" ]; then
		echo "Odin $release source tag changed. Expected $expected_source_commit; got $actual_commit." >&2
		exit 1
	fi
	echo "Building Odin source commit $actual_commit with release-native"
	(cd "$source_root" && make release-native)
	mkdir "$stage/sdk"
	for item in odin base core vendor shared; do
		if [ ! -e "$source_root/$item" ]; then
			echo "Odin source build is missing SDK item: $item" >&2
			exit 1
		fi
		cp -R "$source_root/$item" "$stage/sdk/"
	done
	version=$(ODIN_ROOT="$stage/sdk" "$stage/sdk/odin" version)
	case "$version" in
		*"dev-2026-11"*) ;;
		*) echo "Unexpected source-built Odin compiler version: $version" >&2; exit 1 ;;
	esac
	installed_version=$version
else
	archive=odin-macos-$arch-$release.tar.gz
	url=https://github.com/odin-lang/Odin/releases/download/$release/$archive
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
	version=$(ODIN_ROOT="$stage/sdk" "$stage/sdk/odin" version)
	case "$version" in
		*" version $expected_archive_version") ;;
		*) echo "Unexpected Odin compiler version: $version" >&2; exit 1 ;;
	esac
	installed_version=$expected_archive_version
fi

for directory in base core vendor shared; do
	if [ ! -d "$stage/sdk/$directory" ]; then
		echo "Verified Odin archive is missing SDK directory: $directory" >&2
		exit 1
	fi
done
version=$(ODIN_ROOT="$stage/sdk" "$stage/sdk/odin" version)
case "$version" in
	*"dev-2026-11"*) ;;
	*) echo "Unexpected Odin compiler version: $version" >&2; exit 1 ;;
esac
mv "$stage/sdk" "$destination"
echo "Installed Odin at $destination ($installed_version)"
echo 'Use this directory for PATH and ODIN_ROOT, and its odin executable for ALICORN_ODIN.'
