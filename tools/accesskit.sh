#!/bin/sh

# Resolve only the immutable commit recorded in Alicorn's dependency pin.
# A subshell keeps bootstrap variables and lock traps out of callers.
alicorn_accesskit_binding_root() (
    pin="$REPO_ROOT/dependencies/odin-accesskit.json"
    repository=$(sed -n 's/^[[:space:]]*"repository":[[:space:]]*"\([^"]*\)".*/\1/p' "$pin") || exit 1
    commit=$(sed -n 's/^[[:space:]]*"commit":[[:space:]]*"\([^"]*\)".*/\1/p' "$pin") || exit 1
    if [ "${#commit}" -ne 40 ]; then
        echo 'dependencies/odin-accesskit.json must pin a full standalone commit SHA; PENDING_STANDALONE_SHA cannot be built.' >&2
        exit 1
    fi
    case "$commit" in *[!0-9a-f]*) echo 'Invalid odin-accesskit commit SHA.' >&2; exit 1 ;; esac
    [ -n "$repository" ] || { echo 'Missing odin-accesskit repository in dependency pin.' >&2; exit 1; }
    checkout="$REPO_ROOT/.deps/odin-accesskit"
    mkdir -p "$REPO_ROOT/.deps" || exit 1
    lock="$REPO_ROOT/.deps/odin-accesskit.checkout-lock"
    attempts=0
    until mkdir "$lock" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 600 ]; then
            echo "Timed out waiting for binding checkout lock: $lock" >&2
            exit 1
        fi
        sleep 1
    done
    trap 'rmdir "$lock"' 0
    trap 'exit 1' HUP INT TERM
    if [ ! -d "$checkout/.git" ]; then
        if [ -d "$checkout" ] && [ -n "$(ls -A "$checkout")" ]; then
            echo "Refusing to initialize a nonempty binding checkout: $checkout" >&2
            exit 1
        fi
        git init --quiet "$checkout" || exit 1
        git -C "$checkout" remote add origin "$repository" || exit 1
    fi
    remote=$(git -C "$checkout" remote get-url origin) || exit 1
    [ "$remote" = "$repository" ] || { echo "Binding checkout origin does not match the pin: $checkout" >&2; exit 1; }
    changes=$(git -C "$checkout" status --porcelain --untracked-files=normal) || exit 1
    [ -z "$changes" ] || { echo "Binding checkout must be clean: $checkout" >&2; exit 1; }
    head=$(git -C "$checkout" rev-parse --verify --quiet HEAD) || head=
    if [ "$head" != "$commit" ]; then
        git -C "$checkout" fetch --quiet --depth 1 origin "$commit" || exit 1
        git -C "$checkout" -c advice.detachedHead=false checkout --quiet --detach "$commit" || exit 1
    fi
    head=$(git -C "$checkout" rev-parse --verify HEAD) || exit 1
    [ "$head" = "$commit" ] || { echo 'Standalone binding HEAD does not match the pin.' >&2; exit 1; }
    (CDPATH='' cd -- "$checkout" && pwd -P)
)

alicorn_accesskit_linker_flags() (
    binding_root=$(alicorn_accesskit_binding_root) || exit 1
    sh "$binding_root/tools/bootstrap.sh" --cache-root "$REPO_ROOT/.deps/accesskit"
)

alicorn_accesskit_library_directory() (
    binding_root=$(alicorn_accesskit_binding_root) || exit 1
    sh "$binding_root/tools/bootstrap.sh" --cache-root "$REPO_ROOT/.deps/accesskit" --library-directory
)
