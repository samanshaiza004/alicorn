alicorn_resolve_odin() {
	requested=${1-}
	source='--odin'
	if [ -z "$requested" ]; then
		requested=${ALICORN_ODIN:-}
		source='ALICORN_ODIN'
	fi
	if [ -z "$requested" ]; then
		requested=odin
		source='PATH'
	fi

	case "$requested" in
		*/*)
			resolved=$requested
			if [ ! -f "$resolved" ] || [ ! -x "$resolved" ]; then
				echo "Odin executable not found or not executable: $requested (from $source)" >&2
				return 127
			fi
			;;
		*)
			resolved=$(command -v "$requested" 2>/dev/null || true)
			if [ -z "$resolved" ] || [ ! -f "$resolved" ] || [ ! -x "$resolved" ]; then
				if [ "$source" = 'PATH' ]; then
					cat >&2 <<'EOF'
Odin was not found.

Install Odin: https://odin-lang.org/docs/install/
Then add the Odin directory to PATH, or set ALICORN_ODIN to the compiler executable.
EOF
				else
					echo "Odin executable '$requested' was not found (from $source)." >&2
				fi
				return 127
			fi
			;;
	esac

	case "$resolved" in
		/*) ;;
		*)
			resolved_dir=$(CDPATH='' cd -- "$(dirname -- "$resolved")" && pwd -P) || return 127
			resolved=$resolved_dir/$(basename -- "$resolved")
			;;
	esac

	printf '%s\n' "$resolved"
}

# Odin rejects an empty -extra-linker-flags argument. Linux has no AccessKit
# linker flags, so keep the optional argument out of the process argv entirely.
alicorn_odin_with_linker_flags() {
	alicorn_odin_executable=$1
	alicorn_linker_flags=$2
	shift 2
	if [ -n "$alicorn_linker_flags" ]; then
		"$alicorn_odin_executable" "$@" "-extra-linker-flags:$alicorn_linker_flags"
	else
		"$alicorn_odin_executable" "$@"
	fi
}

. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE:-$0}")" && pwd -P)/accesskit.sh"
