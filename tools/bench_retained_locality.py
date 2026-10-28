#!/usr/bin/env python3
"""Compare retained-region locality using Alicorn's real benchmark helpers.

The candidate is archived from the selected Git ref, built with the same Odin
compiler and profile as the comparison snapshots, and run in alternating fresh
processes. Results are written below out/retained-locality-comparison.
"""

import argparse
import json
import os
import re
import statistics
import subprocess
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--odin", required=True, help="Path to the Odin compiler")
parser.add_argument("--baseline", default="96461223cdbf43080acb957276c045ad704f4606")
parser.add_argument("--regressed", default="3e31c743298f758b4cafd4f425e296a59cd95e34")
parser.add_argument("--candidate", default="HEAD")
parser.add_argument("--speed", action="store_true", help="Build all snapshots with -o:speed")
parser.add_argument("--runs", type=int, default=3, help="Fresh-process samples per snapshot (default: 3)")
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be at least 1")

root = Path(__file__).resolve().parents[1]
profile = "speed" if args.speed else "default"
work = root / "out" / "retained-locality-comparison" / profile
work.mkdir(parents=True, exist_ok=True)
odin = str(Path(args.odin).resolve())
refs = {"baseline": args.baseline, "regressed": args.regressed, "fixed": args.candidate}

main = '''main :: proc() {
    allocator_state := Bench_Allocator_State{backing = context.allocator}
    context.allocator = bench_allocator(&allocator_state)
    measure_regions(&allocator_state)
    measure_tree(10_000, &allocator_state)
    context.allocator = allocator_state.backing
}
'''


def run(command, **kwargs):
    subprocess.run(command, check=True, **kwargs)


executables = {}
for name, ref in refs.items():
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--verify", f"{ref}^{{commit}}"], text=True
    ).strip()
    dest = work / f"{name}-{commit[:12]}"
    if not dest.exists():
        dest.mkdir(parents=True)
        archive = subprocess.Popen(
            ["git", "-C", str(root), "archive", commit], stdout=subprocess.PIPE
        )
        try:
            run(["tar", "-xf", "-", "-C", str(dest)], stdin=archive.stdout)
        finally:
            archive.stdout.close()
        if archive.wait():
            raise RuntimeError(f"could not extract {name} snapshot {commit}")
    probe = dest / "probe"
    probe.mkdir(exist_ok=True)
    source = (dest / "benchmarks" / "main.odin").read_text()
    marker = "main :: proc()"
    if marker not in source:
        raise RuntimeError(f"benchmark entry point missing in {name} snapshot")
    (probe / "main.odin").write_text(source.rsplit(marker, 1)[0] + main)
    executable_suffix = ".exe" if os.name == "nt" else ""
    executable = work / f"{name}-{commit[:12]}-probe{executable_suffix}"
    print(f"BUILD {name} {commit}", flush=True)
    command = [odin, "build", str(probe)]
    if args.speed:
        command.append("-o:speed")
    command.append(f"-out:{executable}")
    run(command)
    executables[name] = (commit, executable)


order = ["baseline", "regressed", "fixed"] * args.runs
records = []
log = work / "matched.txt"
with log.open("w") as output:
    for index, name in enumerate(order, start=1):
        commit, executable = executables[name]
        result = subprocess.run([str(executable)], capture_output=True, text=True, check=True)
        output.write(f"PROCESS {index} {name} {commit}\n{result.stdout}\n")
        reuse_match = re.search(r"reused_for_unrelated_sibling wall_ns (\d+)", result.stdout)
        tree_match = re.search(
            r"tree 10000\n\s+initial wall_ns (\d+).*?\n\s+root_invalidated_unchanged wall_ns (\d+)",
            result.stdout,
            re.S,
        )
        if reuse_match is None or tree_match is None:
            raise RuntimeError(f"could not parse benchmark results for {name}")
        reuse_line = next(line for line in result.stdout.splitlines() if "reused_for_unrelated_sibling wall_ns" in line)

        def optional_counter(key):
            match = re.search(rf"(?:^|\s){re.escape(key)} (\d+)(?:\s|$)", reuse_line)
            return int(match.group(1)) if match else None

        records.append({
            "name": name,
            "commit": commit,
            "region_reuse_ns": int(reuse_match.group(1)),
            "initial_10k_ns": int(tree_match.group(1)),
            "unchanged_10k_ns": int(tree_match.group(2)),
            "measure_examined": optional_counter("measure_examined"),
            "measure_executed": optional_counter("measure_executed"),
            "display_finalized": optional_counter("display_finalized"),
            "display_full_passes": optional_counter("display_full_passes"),
            "semantic_order_examined": optional_counter("semantic_order_examined"),
            "global_fallbacks": optional_counter("global_fallbacks"),
            "display_fallbacks": optional_counter("display_fallbacks"),
        })

metrics = ["region_reuse_ns", "initial_10k_ns", "unchanged_10k_ns"]
medians = {
    name: {
        metric: statistics.median(record[metric] for record in records if record["name"] == name)
        for metric in metrics
    }
    for name in refs
}
ratio = medians["fixed"]["region_reuse_ns"] / medians["baseline"]["region_reuse_ns"]
summary = {
    "profile": profile,
    "refs": {name: commit for name, (commit, _) in executables.items()},
    "samples": records,
    "medians": medians,
    "fixed_to_baseline_region_ratio": ratio,
    "failed": ratio > 1.5 and medians["fixed"]["region_reuse_ns"] > 1_000_000,
}
(work / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2), flush=True)
print(f"Raw output: {log}", flush=True)
print("RETAINED LOCALITY " + ("FAIL" if summary["failed"] else "PASS"), flush=True)
raise SystemExit(int(summary["failed"]))
