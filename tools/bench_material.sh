#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT=$ROOT
source "$ROOT/tools/common.sh"
ODIN="$(alicorn_resolve_odin "${1:-}")"
mkdir -p "$ROOT/out"
ACCESSKIT_LINK_FLAGS=$(alicorn_accesskit_linker_flags)
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" build "$ROOT/benchmarks/native_material" -o:speed -out:"$ROOT/out/alicorn_material_benchmark"
"$ROOT/out/alicorn_material_benchmark"
alicorn_odin_with_linker_flags "$ODIN" "$ACCESSKIT_LINK_FLAGS" build "$ROOT/benchmarks/native_material_budget" -o:speed -out:"$ROOT/out/alicorn_material_budget"
"$ROOT/out/alicorn_material_budget"
