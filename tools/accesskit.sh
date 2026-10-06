#!/bin/sh

# Shared AccessKit C dependency bootstrap for Alicorn shell build scripts.
alicorn_accesskit_linker_flags() {
	version=0.23.1
	url="https://github.com/AccessKit/accesskit-c/releases/download/$version/accesskit-c-$version.zip"
	sha='35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f'
	cache_root="$REPO_ROOT/.deps/accesskit"
	archive="$cache_root/accesskit-c-$version.zip"
	distribution="$cache_root/accesskit-c-$version"
	case "$(uname -s)" in
		Linux) printf '\n'; return 0 ;; # The native AccessKit bridge is currently Windows/macOS only.
		Darwin) ;;
		*) echo "AccessKit $version static bootstrap does not support this OS in this helper (got $(uname -s))." >&2; return 1 ;;
	esac
	case "$(uname -m)" in
		arm64|aarch64) arch=arm64 ;;
		x86_64) arch=x86_64 ;;
		*) echo "AccessKit $version macOS static library does not support architecture '$(uname -m)'." >&2; return 1 ;;
	esac
	mkdir -p "$cache_root"
	if [ ! -f "$archive" ]; then
		command -v curl >/dev/null 2>&1 || { echo 'AccessKit bootstrap requires curl.' >&2; return 127; }
		curl --fail --location --silent --show-error "$url" -o "$archive" || {
			echo "AccessKit $version download failed: $url" >&2
			return 1
		}
	fi
	actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}') || return 1
	if [ "$actual_sha" != "$sha" ]; then
		echo "AccessKit $version archive SHA-256 mismatch. Expected $sha; got $actual_sha. Cached archive: $archive" >&2
		return 1
	fi

	relative_library="lib/macos/$arch/static/libaccesskit.a"
	library="$distribution/$relative_library"
	if [ ! -f "$library" ]; then
		if [ -d "$distribution" ]; then
			echo "AccessKit $version cache exists but required library is missing: $library. Remove only that versioned cache directory and retry." >&2
			return 1
		fi
		command -v unzip >/dev/null 2>&1 || { echo 'AccessKit bootstrap requires unzip.' >&2; return 127; }
		stage=$(mktemp -d "$cache_root/.extract.XXXXXX") || return 1
		if ! unzip -q "$archive" -d "$stage"; then
			rm -r "$stage"
			echo "AccessKit $version archive extraction failed: $archive" >&2
			return 1
		fi
		staged_distribution="$stage/accesskit-c-$version"
		if [ ! -f "$staged_distribution/$relative_library" ]; then
			rm -r "$stage"
			echo "Verified AccessKit archive does not contain expected macOS $arch static library: $relative_library" >&2
			return 1
		fi
		mv "$staged_distribution" "$distribution"
		rm -r "$stage"
	fi
	library_directory=".deps/accesskit/accesskit-c-$version/lib/macos/$arch/static"
	printf '%s\n' "-L$library_directory -framework AppKit -framework Foundation -framework CoreFoundation -lobjc -lc++"
}
