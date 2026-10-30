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

# Native callers need the standalone binding collection even when no native
# linker flags are required. Keep each compiler argument separate.
alicorn_odin_with_linker_flags() {
	alicorn_odin_executable=$1
	alicorn_linker_flags=$2
	shift 2
	alicorn_binding_root=$(alicorn_accesskit_binding_root) || return $?
	alicorn_c_library_directory=$(alicorn_accesskit_library_directory) || return $?
	if [ -n "$alicorn_linker_flags" ]; then
		"$alicorn_odin_executable" "$@" "-collection:accesskit=$alicorn_binding_root" "-collection:accesskit_c=$alicorn_c_library_directory" "-extra-linker-flags:$alicorn_linker_flags"
	else
		"$alicorn_odin_executable" "$@" "-collection:accesskit=$alicorn_binding_root" "-collection:accesskit_c=$alicorn_c_library_directory"
	fi
}

. "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE:-$0}")" && pwd -P)/accesskit.sh"
