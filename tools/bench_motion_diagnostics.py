#!/usr/bin/env python3
"""Compare closed-inspector motion runtime overhead across two Alicorn refs.

The same headless fixture is copied into archived source snapshots, built with
one Odin compiler/profile, and run in alternating fresh processes. It measures
active motion sampling for 1/100/1000 owners and one-owner target churn. No
inspector runtime is constructed. Diagnostic-counter hook lines are injected
only into the instrumented candidate snapshot.
"""

import argparse
import ctypes
import io
import json
import math
import statistics
import subprocess
import tarfile
import time
from ctypes import wintypes
from pathlib import Path


def run(command, *, cwd=None, **kwargs):
    subprocess.run(command, cwd=cwd, check=True, **kwargs)


def archive_ref(root: Path, ref: str, destination: Path) -> str:
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--verify", f"{ref}^{{commit}}"], text=True
    ).strip()
    destination.mkdir(parents=True, exist_ok=True)
    archive_bytes = subprocess.check_output(["git", "-C", str(root), "archive", commit])
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:") as archive:
        for member in archive.getmembers():
            if member.name.startswith("/") or ".." in Path(member.name).parts:
                raise RuntimeError(f"unsafe archive path: {member.name}")
        archive.extractall(destination)
    return commit


def inject_hooks(source: str, *, diagnostics: bool) -> str:
    if not diagnostics:
        for marker in (
            "\t// MOTION_SAMPLE_DIAGNOSTICS_BEFORE\n",
            "\t// MOTION_SAMPLE_DIAGNOSTICS_AFTER\n",
            "\t// MOTION_CHURN_DIAGNOSTICS_BEFORE\n",
            "\t// MOTION_CHURN_DIAGNOSTICS_AFTER\n",
            "\t// MOTION_SETUP_DIAGNOSTICS_BEFORE\n",
            "\t// MOTION_SETUP_DIAGNOSTICS_AFTER\n",
        ):
            source = source.replace(marker, "")
        return source

    replacements = {
        "\t// MOTION_SETUP_DIAGNOSTICS_BEFORE\n": "\tdiag_before_setup := alicorn.motion_diagnostics_stats(&rt)\n",
        "\t// MOTION_SETUP_DIAGNOSTICS_AFTER\n": (
            "\tdiag_after_setup := alicorn.motion_diagnostics_stats(&rt)\n"
            "\tfmt.printf(\"diagnostics_setup count=%d events=%d retargets=%d requests=%d coalesced=%d evictions=%d\\n\",\n"
            "\t\tcount, alicorn.motion_diagnostics_event_count(&rt),\n"
            "\t\tdiag_after_setup.retargets-diag_before_setup.retargets,\n"
            "\t\tdiag_after_setup.presentation_requests-diag_before_setup.presentation_requests,\n"
            "\t\tdiag_after_setup.presentation_requests_coalesced-diag_before_setup.presentation_requests_coalesced,\n"
            "\t\tdiag_after_setup.trace_evictions-diag_before_setup.trace_evictions)\n"
        ),
        "\t// MOTION_SAMPLE_DIAGNOSTICS_BEFORE\n": "\tdiag_before_sample := alicorn.motion_diagnostics_stats(&rt)\n",
        "\t// MOTION_SAMPLE_DIAGNOSTICS_AFTER\n": (
            "\tdiag_after_sample := alicorn.motion_diagnostics_stats(&rt)\n"
            "\tfmt.printf(\"diagnostics_sample count=%d sample_ticks=%d owner_visits=%d property_samples=%d requests=%d coalesced=%d submissions=%d events=%d evictions=%d\\n\",\n"
            "\t\tcount, diag_after_sample.sample_ticks-diag_before_sample.sample_ticks,\n"
            "\t\tdiag_after_sample.owner_visits-diag_before_sample.owner_visits,\n"
            "\t\tdiag_after_sample.property_samples-diag_before_sample.property_samples,\n"
            "\t\tdiag_after_sample.presentation_requests-diag_before_sample.presentation_requests,\n"
            "\t\tdiag_after_sample.presentation_requests_coalesced-diag_before_sample.presentation_requests_coalesced,\n"
            "\t\tdiag_after_sample.presentation_submissions-diag_before_sample.presentation_submissions,\n"
            "\t\talicorn.motion_diagnostics_event_count(&rt), diag_after_sample.trace_evictions-diag_before_sample.trace_evictions)\n"
        ),
        "\t// MOTION_CHURN_DIAGNOSTICS_BEFORE\n": "\tdiag_before_churn := alicorn.motion_diagnostics_stats(&rt)\n",
        "\t// MOTION_CHURN_DIAGNOSTICS_AFTER\n": (
            "\tdiag_after_churn := alicorn.motion_diagnostics_stats(&rt)\n"
            "\tfmt.printf(\"diagnostics_churn changes=%d retargets=%d requests=%d coalesced=%d submissions=%d events=%d evictions=%d\\n\",\n"
            "\t\tchanges, diag_after_churn.retargets-diag_before_churn.retargets,\n"
            "\t\tdiag_after_churn.presentation_requests-diag_before_churn.presentation_requests,\n"
            "\t\tdiag_after_churn.presentation_requests_coalesced-diag_before_churn.presentation_requests_coalesced,\n"
            "\t\tdiag_after_churn.presentation_submissions-diag_before_churn.presentation_submissions,\n"
            "\t\talicorn.motion_diagnostics_event_count(&rt), diag_after_churn.trace_evictions-diag_before_churn.trace_evictions)\n"
        ),
    }
    for marker, replacement in replacements.items():
        if marker not in source:
            raise RuntimeError(f"benchmark hook missing: {marker.strip()}")
        source = source.replace(marker, replacement, 1)
    return source


def percentile(values, fraction):
    ordered = sorted(values)
    offset = (len(ordered) - 1) * fraction
    lower = math.floor(offset)
    upper = math.ceil(offset)
    if lower == upper:
        return float(ordered[lower])
    weight = offset - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def parse_run(output: str):
    tick_samples = {1: [], 100: [], 1000: []}
    retarget_samples = []
    summaries = {}
    diagnostics = {}
    owner_setup = {1: [], 100: [], 1000: []}
    for line in output.splitlines():
        fields = line.split()
        if not fields:
            continue
        values = dict(field.split("=", 1) for field in fields[1:] if "=" in field)
        if fields[0] == "tick_sample":
            tick_samples[int(values["count"])].append(int(values["ns"]))
        elif fields[0] == "retarget_sample":
            retarget_samples.append(int(values["ns"]))
        elif fields[0] in ("tick_summary", "retarget_summary"):
            summaries[f"{fields[0]}:{values.get('count', values.get('changes'))}"] = values
        elif fields[0] == "owner_setup":
            owner_setup[int(values["count"])].append(values)
        elif fields[0].startswith("diagnostics_"):
            discriminator = values.get("count", values.get("changes", ""))
            diagnostics[f"{fields[0]}:{discriminator}"] = values
    if any(len(samples) != 180 for samples in tick_samples.values()) or len(retarget_samples) != 1000:
        raise RuntimeError("benchmark output did not contain every expected timing sample")
    return tick_samples, retarget_samples, summaries, diagnostics, owner_setup


def child_process_cpu(process: subprocess.Popen) -> tuple[int | None, int | None]:
    """Read exited Windows child CPU time and cycle count from its handle."""
    if process.poll() is None:
        raise RuntimeError("CPU time queried before child exit")
    if not hasattr(ctypes, "windll"):
        return None, None
    kernel32 = ctypes.windll.kernel32
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.OpenProcess.restype = wintypes.HANDLE
    handle = kernel32.OpenProcess(0x1000, False, process.pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return None, None
    created, exited, kernel, user = (wintypes.FILETIME() for _ in range(4))
    try:
        cpu_ns = None
        if kernel32.GetProcessTimes(handle, ctypes.byref(created), ctypes.byref(exited),
                                    ctypes.byref(kernel), ctypes.byref(user)):
            ticks = (kernel.dwHighDateTime << 32 | kernel.dwLowDateTime) + \
                    (user.dwHighDateTime << 32 | user.dwLowDateTime)
            cpu_ns = ticks * 100  # FILETIME units are 100 ns.
        cycles = ctypes.c_ulonglong()
        kernel32.QueryProcessCycleTime.argtypes = [wintypes.HANDLE, ctypes.POINTER(ctypes.c_ulonglong)]
        kernel32.QueryProcessCycleTime.restype = wintypes.BOOL
        cpu_cycles = None
        if kernel32.QueryProcessCycleTime(handle, ctypes.byref(cycles)):
            cpu_cycles = cycles.value
        return cpu_ns, cpu_cycles
    finally:
        kernel32.CloseHandle(handle)


def run_child(executable: Path):
    started = time.perf_counter_ns()
    process = subprocess.Popen([str(executable)], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True)
    output, _ = process.communicate()
    wall_ns = time.perf_counter_ns() - started
    if process.returncode != 0:
        raise RuntimeError(f"benchmark exited {process.returncode}:\n{output[-4000:]}")
    cpu_ns, cpu_cycles = child_process_cpu(process)
    return output, wall_ns, cpu_ns, cpu_cycles


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--odin", required=True, help="Path to the Odin compiler")
parser.add_argument("--baseline", default="9690333ea5dbe335737d59a1c0bfb331edd3ee44")
parser.add_argument("--candidate", default="82e415d39d1b265024bc366c2df9563a06e70241")
parser.add_argument("--runs", type=int, default=5)
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be at least 1")

root = Path(__file__).resolve().parents[1]
work = root / "out" / "motion-diagnostics-comparison"
work.mkdir(parents=True, exist_ok=True)
benchmark_source = (root / "benchmarks" / "motion_diagnostics" / "main.odin").read_text(encoding="utf-8")
odin = str(Path(args.odin).resolve())
refs = {"baseline": args.baseline, "candidate": args.candidate}
executables = {}

for name, ref in refs.items():
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "--verify", f"{ref}^{{commit}}"], text=True
    ).strip()
    destination = work / f"{name}-{commit[:12]}"
    if not destination.exists() or not (destination / "runtime" / "motion_retained.odin").exists():
        if destination.exists():
            raise RuntimeError(f"incomplete snapshot already exists: {destination}; remove it and retry")
        commit = archive_ref(root, ref, destination)
    bench_dir = destination / "benchmarks" / "motion_diagnostics"
    bench_dir.mkdir(parents=True, exist_ok=True)
    supports_diagnostics = name == "candidate"
    (bench_dir / "main.odin").write_text(
        inject_hooks(benchmark_source, diagnostics=supports_diagnostics), encoding="utf-8"
    )
    executable = work / f"{name}-{commit[:12]}-speed.exe"
    print(f"BUILD {name} {commit}", flush=True)
    run([odin, "build", str(bench_dir), "-o:speed", f"-out:{executable}"], cwd=destination)
    executables[name] = (commit, executable)

order = ["baseline", "candidate"] * args.runs
records = []
with (work / "raw-runs.txt").open("w", encoding="utf-8") as raw:
    for index, name in enumerate(order, 1):
        commit, executable = executables[name]
        output, wall_ns, process_cpu_ns, process_cpu_cycles = run_child(executable)
        raw.write(f"RUN {index} {name} {commit} wall_ns={wall_ns} process_cpu_ns={process_cpu_ns} process_cpu_cycles={process_cpu_cycles}\n{output}\n")
        ticks, churn, summaries, diagnostics, owner_setup = parse_run(output)
        records.append({
            "name": name,
            "commit": commit,
            "ticks": ticks,
            "churn": churn,
            "summaries": summaries,
            "diagnostics": diagnostics,
            "owner_setup": owner_setup,
            "wall_ns": wall_ns,
            "process_cpu_ns": process_cpu_ns,
            "process_cpu_cycles": process_cpu_cycles,
        })

summary = {"odin": odin, "profile": "speed", "runs": args.runs, "refs": {}, "results": {}}
for name, (commit, _executable) in executables.items():
    summary["refs"][name] = commit
    run_records = [record for record in records if record["name"] == name]
    tick_result = {}
    for count in (1, 100, 1000):
        per_run = [
            {"p50_ns": percentile(record["ticks"][count], .50),
             "p95_ns": percentile(record["ticks"][count], .95),
             "p99_ns": percentile(record["ticks"][count], .99)}
            for record in run_records
        ]
        tick_result[str(count)] = {
            key: statistics.median(item[key] for item in per_run)
            for key in ("p50_ns", "p95_ns", "p99_ns")
        }
    churn_per_run = [
        {"p50_ns": percentile(record["churn"], .50),
         "p95_ns": percentile(record["churn"], .95),
         "p99_ns": percentile(record["churn"], .99)}
        for record in run_records
    ]
    setup_latency = {}
    for count in (1, 100, 1000):
        setup_latency[str(count)] = {
            "median_ns": statistics.median(
                int(setup["ns"])
                for record in run_records
                for setup in record["owner_setup"][count]
            ),
            "median_allocations": statistics.median(
                int(setup["allocations"])
                for record in run_records
                for setup in record["owner_setup"][count]
            ),
            "median_allocated_bytes": statistics.median(
                int(setup["allocated_bytes"])
                for record in run_records
                for setup in record["owner_setup"][count]
            ),
        }
    cpu_times = [record["process_cpu_ns"] for record in run_records]
    cpu_cycles = [record["process_cpu_cycles"] for record in run_records]
    wall_times = [record["wall_ns"] for record in run_records]
    summary["results"][name] = {
        "owner_setup": setup_latency,
        "tick_latency": tick_result,
        "retarget_latency": {
            key: statistics.median(item[key] for item in churn_per_run)
            for key in ("p50_ns", "p95_ns", "p99_ns")
        },
        "last_run_summaries": run_records[-1]["summaries"],
        "last_run_diagnostics": run_records[-1]["diagnostics"],
        "process_cpu_ns_median": statistics.median(cpu_times) if all(v is not None for v in cpu_times) else None,
        "process_cpu_cycles_median": statistics.median(cpu_cycles) if all(v is not None for v in cpu_cycles) else None,
        "wall_ns_median": statistics.median(wall_times),
    }

baseline = summary["results"]["baseline"]
candidate = summary["results"]["candidate"]
summary["overhead"] = {
    "tick_p50_ratio": {
        count: candidate["tick_latency"][count]["p50_ns"] / baseline["tick_latency"][count]["p50_ns"]
        for count in ("1", "100", "1000")
    },
    "tick_p95_ratio": {
        count: candidate["tick_latency"][count]["p95_ns"] / baseline["tick_latency"][count]["p95_ns"]
        for count in ("1", "100", "1000")
    },
    "retarget_p50_ratio": candidate["retarget_latency"]["p50_ns"] / baseline["retarget_latency"]["p50_ns"],
    "retarget_p95_ratio": candidate["retarget_latency"]["p95_ns"] / baseline["retarget_latency"]["p95_ns"],
    "process_cpu_cycles_ratio": candidate["process_cpu_cycles_median"] / baseline["process_cpu_cycles_median"]
        if candidate["process_cpu_cycles_median"] and baseline["process_cpu_cycles_median"] else None,
}
(work / "comparison.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2), flush=True)
print(f"Raw runs: {work / 'raw-runs.txt'}", flush=True)
print(f"Summary: {work / 'comparison.json'}", flush=True)
