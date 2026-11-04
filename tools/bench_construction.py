#!/usr/bin/env python3
"""Compare initial construction using identical probes and alternating fresh processes.

Timing runs use the ordinary allocator. Use --allocations in a separate capture
for requested allocation traffic/high-water, and --rss for Darwin process RSS.
No construction latency threshold is imposed by this research tool.
"""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import statistics
import subprocess
import tarfile
from pathlib import Path

PHASE_FUNCTIONS = {
    "Reconcile": ["reconcile"],
    "Copy_Description": ["copy_node_description"],
    "Description_Hash": ["description_hash"],
    "Layout_Hash": ["layout_percent_width_pending_hash", "layout_hash_pending", "layout_hash"],
    "Measure_Hash": ["measure_input_hash"],
    "Paint_Hash": ["paint_hash"],
    "Trace": ["record_trace_with_cause", "record_trace"],
    "Tree_Order": ["rebuild_order"],
    "Measurement": ["layout_measure_node"],
    "Text_Prepare": ["prepare_text_run_node"],
    "Layout": ["layout_tree"],
    "Geometry_Finalize": ["layout_finalize_node_geometry"],
    "Adaptive_Semantics": ["adaptive_semantics_sync_descriptions"],
    "Semantic_Commit": ["semantic_commit"],
    "Paint": ["update_paint"],
    "Node_Paint": ["build_node_paint"],
    "Display_Build": ["rebuild_display"],
    "Display_Finalize": ["layout_finalize_display"],
}
COARSE_PHASES = {"Reconcile", "Tree_Order", "Layout", "Geometry_Finalize",
                 "Adaptive_Semantics", "Semantic_Commit", "Paint", "Display_Build", "Display_Finalize"}


def instrument_phases(path, detail):
    """Add entry/deferred-exit clocks in a disposable source snapshot only."""
    files = {file: file.read_text() for file in (path / "runtime").glob("*.odin")}
    instrumented = {}
    for phase, alternatives in PHASE_FUNCTIONS.items():
        if not detail and phase not in COARSE_PHASES:
            continue
        for name in alternatives:
            match_file = next((file for file, text in files.items()
                               if re.search(r"^" + name + r"\s*::\s*proc\s*\(", text, re.M)), None)
            if match_file is None:
                continue
            text = files[match_file]
            match = re.search(r"^" + name + r"\s*::\s*proc\s*\(", text, re.M)
            index, depth, quote, escaped = match.end(), 1, False, False
            while depth:
                char = text[index]
                if quote:
                    if escaped:
                        escaped = False
                    elif char == "\\":
                        escaped = True
                    elif char == '"':
                        quote = False
                elif char == '"':
                    quote = True
                elif char == "(":
                    depth += 1
                elif char == ")":
                    depth -= 1
                index += 1
            body = text.index("{", index) + 1
            insert = f"\n\tconstruction_profile_start := construction_profile_begin()\n\tdefer construction_profile_end(.{phase}, construction_profile_start)\n"
            files[match_file] = text[:body] + insert + text[body:]
            instrumented[phase] = name
            break
    for file, text in files.items():
        file.write_text(text)
    enum = ", ".join(PHASE_FUNCTIONS)
    (path / "runtime" / "construction_profile.odin").write_text(f'''package alicorn
import "core:fmt"
import "core:time"
import "core:c/libc"
Construction_Profile_Phase :: enum {{ {enum} }}
Construction_Profile_Mark :: struct {{ wall: time.Time, cpu: i64 }}
construction_profile_times: [Construction_Profile_Phase]i64
construction_profile_cpu_times: [Construction_Profile_Phase]i64
construction_profile_calls: [Construction_Profile_Phase]u64
construction_profile_cpu_now :: proc() -> i64 {{
    when ODIN_OS == .Windows || {'true' if detail else 'false'} {{ return 0 }}
    else {{ return i64(libc.clock())*(1_000_000_000/i64(libc.CLOCKS_PER_SEC)) }}
}}
construction_profile_begin :: proc() -> Construction_Profile_Mark {{ return {{wall=time.now(), cpu=construction_profile_cpu_now()}} }}
construction_profile_end :: proc(phase: Construction_Profile_Phase, start: Construction_Profile_Mark) {{
    construction_profile_cpu_times[phase] += construction_profile_cpu_now()-start.cpu
    construction_profile_times[phase] += time.duration_nanoseconds(time.since(start.wall))
    construction_profile_calls[phase] += 1
}}
construction_profile_report :: proc() {{
    for phase in Construction_Profile_Phase {{
        fmt.println("cpu_phase", phase, "calls", construction_profile_calls[phase], "inclusive_ns", construction_profile_times[phase], "inclusive_cpu_ns", construction_profile_cpu_times[phase])
    }}
}}
''')
    return instrumented


def command(args, **kwargs):
    result = subprocess.run(args, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"command failed ({result.returncode}): {args!r}\n{result.stdout or ''}{result.stderr or ''}")
    return result


def snapshot(root, output, label, ref, november):
    commit = subprocess.check_output(
        ["git", "rev-parse", "--verify", ref + "^{commit}"], cwd=root, text=True
    ).strip()
    path = output / (label + "-" + commit[:12])
    marker = path / ".construction-benchmark-snapshot"
    if path.exists():
        if path.is_symlink() or not marker.is_file():
            raise RuntimeError("refusing to replace a directory not created by this benchmark: " + str(path))
        shutil.rmtree(path)
    path.mkdir()
    marker.write_text(commit + "\n")
    archive = subprocess.Popen(["git", "archive", commit], cwd=root, stdout=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=archive.stdout, mode="r|") as source:
            source.extractall(path=path, filter="data")
    finally:
        archive.stdout.close()
    if archive.wait():
        raise RuntimeError("could not archive " + commit)
    compatibility = []
    (path / "runtime" / "construction_benchmark.odin").write_text('''package alicorn
import "core:mem"
Construction_Benchmark_New_Runtime :: proc(viewport: Rect, persistent_allocator: mem.Allocator) -> Runtime {
    return new_runtime(viewport, Runtime_Config{persistent_allocator=persistent_allocator})
}
''')
    image = path / "runtime" / "image_assets.odin"
    if november and image.exists():
        source = image.read_text()
        if "decoded.pixels.buf" in source:
            image.write_text(source.replace("decoded.pixels.buf", "decoded.pixels"))
            compatibility.append("runtime/image_assets.odin: decoded.pixels.buf -> decoded.pixels (unused image decoder SDK adaptation)")
    return commit, path, compatibility


def tokens(line):
    values = line.split()
    result = {}
    for key, value in zip(values[1::2], values[2::2]):
        try:
            result[key] = int(value)
        except ValueError:
            try:
                result[key] = float(value)
            except ValueError:
                result[key] = value
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--odin", required=True)
    parser.add_argument("--ref", action="append", required=True, metavar="LABEL=REF")
    parser.add_argument("--patch", action="append", default=[], metavar="LABEL=PATCH", help="Apply a recorded experimental patch to one disposable snapshot")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--speed", action="store_true")
    parser.add_argument("--allocations", action="store_true")
    parser.add_argument("--phases", action="store_true", help="Instrument disposable runtime snapshots; keep separate from ordinary timing runs")
    parser.add_argument("--phase-detail", action="store_true", help="Add per-node clocks; higher overhead, used only for attribution")
    parser.add_argument("--rss", action="store_true", help="Capture Darwin process peak RSS with /usr/bin/time -l")
    parser.add_argument("--workloads", default="containers:10000,short:10000,wrapped:10000,panel:100")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    if args.rss and platform.system() != "Darwin":
        parser.error("--rss currently requires Darwin /usr/bin/time -l")
    if args.allocations and args.phases:
        parser.error("capture allocation attribution and CPU phases separately")
    if args.phase_detail and not args.phases:
        parser.error("--phase-detail requires --phases")
    root = Path(__file__).resolve().parents[1]
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    odin = str(Path(args.odin).resolve())
    version = subprocess.check_output([odin, "version"], text=True).strip()
    fixture = root / "benchmarks" / "diagnostics" / "construction_cpu_probe.odin"
    probe = output / "probe"
    probe.mkdir(exist_ok=True)
    probe_bytes = fixture.read_bytes()
    probe_source = probe_bytes.decode()
    if args.phases:
        body, closing = probe_source.rsplit("\n}", 1)
        probe_source = body + "\n\talicorn.construction_profile_report()\n}" + closing
    (probe / "main.odin").write_text(probe_source)
    refs = {}
    patches = {}
    labels = {definition.split("=", 1)[0] for definition in args.ref}
    for definition in args.patch:
        label, file = definition.split("=", 1)
        if label not in labels or label in patches:
            parser.error("each patch must name one unique ref label")
        patches[label] = Path(file).resolve()
    for definition in args.ref:
        label, ref = definition.split("=", 1)
        if not re.fullmatch(r"[A-Za-z0-9_-]+", label) or label in refs:
            parser.error("each ref needs a unique simple label")
        commit, path, compatibility = snapshot(root, output, label, ref, "dev-2026-11" in version)
        patch_sha256 = None
        if label in patches:
            patch = patches[label]
            patch_sha256 = hashlib.sha256(patch.read_bytes()).hexdigest()
            # Keep git's discovery from reaching the caller's parent worktree.
            patch_env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(path.parent))
            command(["git", "apply", "--no-index", str(patch)], cwd=path, env=patch_env)
        instrumented = instrument_phases(path, args.phase_detail) if args.phases else {}
        executable = output / (label + (".exe" if os.name == "nt" else ""))
        build = [odin, "build", str(probe), "-collection:alicorn=" + str(path), "-out:" + str(executable)]
        if args.speed:
            build.append("-o:speed")
        print("BUILD", label, commit, flush=True)
        command(build)
        refs[label] = {"commit": commit, "executable": str(executable), "compatibility": compatibility,
                       "instrumented_functions": instrumented, "patch_sha256": patch_sha256}
    workloads = [definition.split(":", 1) for definition in args.workloads.split(",")]
    for workload, count in workloads:
        if workload not in ("containers", "short", "wrapped", "panel") or int(count) < 1:
            parser.error("invalid workload")
    samples = []
    with (output / "raw.txt").open("w") as raw:
        for workload, count in workloads:
            for run in range(args.runs):
                # Reverse alternate rounds so both variants take each order position.
                order = list(refs)
                if run % 2:
                    order.reverse()
                for label in order:
                    invoke = [refs[label]["executable"], workload, count, "1", str(int(args.allocations)), "0"]
                    if args.rss:
                        invoke = ["/usr/bin/time", "-l"] + invoke
                    result = command(invoke, capture_output=True)
                    raw.write(f"PROCESS {label} {refs[label]['commit']} {workload} {count} {run+1}\n{result.stdout}{result.stderr}\n")
                    construction = next(line for line in result.stdout.splitlines() if line.startswith("construction "))
                    sample = {"label": label, "workload": workload, "run": run+1, **tokens(construction)}
                    sample["record_sizes"] = tokens(next(line for line in result.stdout.splitlines() if line.startswith("record_sizes ")))
                    sample["allocations"] = [line for line in result.stdout.splitlines() if line.startswith("allocations ")]
                    sample["cpu_phases"] = {line.split()[1]: tokens(" ".join(line.split()[1:]))
                                            for line in result.stdout.splitlines() if line.startswith("cpu_phase ")}
                    memory = next((line for line in result.stdout.splitlines() if line.startswith("requested_memory ")), None)
                    if memory:
                        sample["requested_memory"] = tokens(memory)
                    if args.rss:
                        match = re.search(r"(\d+)\s+maximum resident set size", result.stderr)
                        if match is None:
                            raise RuntimeError("Darwin peak RSS missing")
                        sample["peak_rss_bytes"] = int(match.group(1))
                    samples.append(sample)
    metrics = ["init_ns", "description_ns", "end_frame_ns", "total_ns", "destroy_ns"]
    if samples and samples[0]["cpu_supported"] == "true":
        metrics += ["init_cpu_ns", "description_cpu_ns", "end_frame_cpu_ns", "total_cpu_ns", "destroy_cpu_ns"]
    if args.rss:
        metrics.append("peak_rss_bytes")
    summary = []
    for workload, _ in workloads:
        for label in refs:
            matching = [sample for sample in samples if sample["label"] == label and sample["workload"] == workload]
            row = {"label": label, "workload": workload}
            for metric in metrics:
                values = [sample[metric] for sample in matching]
                row[metric] = {"median": statistics.median(values), "min": min(values), "max": max(values)}
            summary.append(row)
    report = {
        "compiler": version, "profile": "speed" if args.speed else "default",
        "allocation_tracking": args.allocations, "phase_instrumentation": args.phases,
        "phase_detail": args.phase_detail, "rss": args.rss,
        "probe_sha256": hashlib.sha256(probe_bytes).hexdigest(),
        "refs": refs, "samples": samples, "summary": summary,
    }
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    for row in summary:
        times = " ".join(f"{metric}={row[metric]['median']/1e6:.3f}ms" for metric in ("description_ns", "end_frame_ns", "total_ns"))
        print(row["label"], row["workload"], times)
    print("Results:", output / "results.json")


if __name__ == "__main__":
    main()
