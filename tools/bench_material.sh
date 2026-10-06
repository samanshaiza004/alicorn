#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tools/common.sh"
ODIN="$(alicorn_resolve_odin "${1:-}")"
mkdir -p "$ROOT/out"
"$ODIN" build "$ROOT/benchmarks/native_material" -o:speed -out:"$ROOT/out/alicorn_material_benchmark"
"$ROOT/out/alicorn_material_benchmark"
