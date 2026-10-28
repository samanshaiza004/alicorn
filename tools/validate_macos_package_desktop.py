#!/usr/bin/env python3
"""Interactively validate static and shared macOS desktop-fixture bundles."""

from __future__ import annotations

import argparse
import ctypes
import getpass
import json
import os
import pathlib
import plistlib
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
from typing import Any

from package_macos import sha256, validate_smoke_output

REQUIRED_SDL_VERSION = "3.4.18"
PROC_PIDPATHINFO_MAXSIZE = 1024


class BlockedError(RuntimeError):
    """The desktop acceptance could not run in the current session."""


def process_executable(pid: int) -> pathlib.Path:
    if sys.platform != "darwin":
        raise RuntimeError("Desktop bundle validation requires macOS")
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    pidpath = libproc.proc_pidpath
    pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(PROC_PIDPATHINFO_MAXSIZE)
    if pidpath(pid, buffer, len(buffer)) <= 0:
        error = ctypes.get_errno()
        raise OSError(error, f"proc_pidpath failed for process {pid}")
    return pathlib.Path(os.fsdecode(buffer.value)).resolve(strict=True)


def parse_process_list(output: str) -> list[tuple[int, str]]:
    processes: list[tuple[int, str]] = []
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2:
            continue
        try:
            processes.append((int(fields[0]), fields[1]))
        except ValueError:
            continue
    return processes


def app_open_supports_output_redirection(help_output: str) -> bool:
    return "--stdout" in help_output and "--stderr" in help_output


def require_relaunch_host_output(
    mode: str,
    *,
    require_interaction: bool,
    output_available: bool,
) -> None:
    """Require machine-verifiable startup evidence for unattended relaunches."""
    if mode == "open" and not require_interaction and not output_available:
        raise BlockedError(
            "Launch Services cannot verify host startup without --stdout/--stderr; "
            "relaunch is BLOCKED rather than accepted from its shutdown marker alone"
        )


def verify_process_executable(pid: int, expected: pathlib.Path) -> pathlib.Path:
    actual = process_executable(pid)
    if actual != expected:
        raise RuntimeError(f"Launch resolved to {actual}; expected {expected}")
    return actual


def capture_screenshot(path: pathlib.Path) -> None:
    if shutil.which("/usr/sbin/screencapture") is None:
        raise BlockedError("macOS screen-capture tool is unavailable")
    try:
        screenshot = subprocess.run(
            ["/usr/sbin/screencapture", "-x", str(path)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired as error:
        raise BlockedError("macOS screen capture timed out") from error
    if screenshot.returncode != 0 or not path.is_file():
        details = screenshot.stderr.strip() or screenshot.stdout.strip() or "no image was written"
        raise BlockedError("Could not capture the confirmed first frame: " + details)


def wait_for_launcher(
    launcher: subprocess.Popen[Any], mode: str, *, timeout: float
) -> None:
    try:
        launcher.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise TimeoutError(f"{mode} launch did not quit within {timeout:g} seconds") from error


def stop_failed_launch(
    launcher: subprocess.Popen[Any],
    pid: int | None,
    expected: pathlib.Path,
    *,
    run_id: str | None = None,
) -> None:
    """Stop only the verified app process; always reap the launcher process."""
    if launcher.poll() is not None:
        return
    if pid is None and run_id is not None:
        try:
            pid = _running_process_for_run(run_id)
        except (OSError, RuntimeError, subprocess.SubprocessError):
            # Cleanup is best-effort if process enumeration itself is unavailable.
            pass
    if pid is not None:
        try:
            if process_executable(pid) == expected:
                os.kill(pid, signal.SIGTERM)
        except (OSError, RuntimeError):
            # The process may already have exited. Never signal an unverified PID.
            pass
    try:
        launcher.wait(timeout=5)
    except subprocess.TimeoutExpired:
        if pid is not None:
            try:
                if process_executable(pid) == expected:
                    os.kill(pid, signal.SIGKILL)
            except (OSError, RuntimeError):
                pass
        try:
            launcher.wait(timeout=5)
        except subprocess.TimeoutExpired:
            launcher.terminate()
            launcher.wait(timeout=5)


def validate_result_file(
    path: pathlib.Path,
    run_id: str,
    *,
    require_interaction: bool,
) -> dict[str, Any]:
    if not path.is_file():
        raise RuntimeError(f"Host did not return and write its shutdown result: {path}")
    result = json.loads(path.read_text(encoding="utf-8"))
    if result.get("runId") != run_id:
        raise RuntimeError("Shutdown result belongs to a different launch")
    for field in ("pointerActivations", "keyboardActivations"):
        if not isinstance(result.get(field), int) or result[field] < 0:
            raise RuntimeError(f"Shutdown result has an invalid {field}")
    if require_interaction and (
        result["pointerActivations"] < 1 or result["keyboardActivations"] < 1
    ):
        raise RuntimeError(
            "Both validation buttons must activate: one by pointer and one by keyboard"
        )
    return result


def audit_app(app: pathlib.Path, linkage: str) -> dict[str, Any]:
    app = app.resolve(strict=True)
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError(f"Expected a .app bundle directory: {app}")
    if not any(character.isspace() for character in str(app)):
        raise ValueError(f"Bundle path must contain whitespace for path handling coverage: {app}")

    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    executable_name = info.get("CFBundleExecutable")
    if not executable_name or pathlib.Path(executable_name).name != executable_name:
        raise RuntimeError("CFBundleExecutable is missing or is not a filename")
    executable = (app / "Contents" / "MacOS" / executable_name).resolve(strict=True)
    try:
        executable.relative_to(app)
    except ValueError as error:
        raise RuntimeError("CFBundleExecutable resolves outside the application bundle") from error
    if not os.access(executable, os.X_OK):
        raise RuntimeError(f"Bundle executable is not executable: {executable}")

    manifest_path = app.parent / "alicorn-package.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    host = manifest.get("host", {})
    if host.get("sdlLinkage") != linkage:
        raise RuntimeError(f"Expected {linkage} SDL, package reports {host.get('sdlLinkage')!r}")
    if host.get("sdlVersion") != REQUIRED_SDL_VERSION:
        raise RuntimeError(f"Package SDL version is not {REQUIRED_SDL_VERSION}")
    if linkage == "shared":
        shared = host.get("sdlRuntime", {})
        if shared.get("detectedVersion") != REQUIRED_SDL_VERSION:
            raise RuntimeError("Shared package manifest lacks a verified SDL runtime version")
        if not shared.get("inputSha256") or not shared.get("inputFilename"):
            raise RuntimeError("Shared package manifest lacks input identity and hash")
    elif not host.get("sdlSource") or not host.get("sdlSourceSha256"):
        raise RuntimeError("Static package manifest lacks pinned SDL source provenance")

    bundled_dependencies = manifest.get("dependencies", {}).get("bundled", [])
    bundled_sdl = [
        dependency
        for dependency in bundled_dependencies
        if pathlib.Path(dependency.get("name", "")).name.casefold() == "sdl3.dylib"
    ]
    if linkage == "shared" and (len(bundled_sdl) != 1 or not bundled_sdl[0].get("sha256")):
        raise RuntimeError("Shared package manifest lacks the bundled SDL dylib hash")
    if linkage == "static" and bundled_sdl:
        raise RuntimeError("Static package manifest unexpectedly lists a shared SDL dylib")

    application = manifest.get("application", {})
    if application.get("bundleIdentifier") != info.get("CFBundleIdentifier"):
        raise RuntimeError("Bundle identifier disagrees with package manifest")
    if application.get("sha256") != sha256(executable):
        raise RuntimeError("Executable hash disagrees with package manifest")

    signature = subprocess.run(
        ["codesign", "--verify", "--strict", "--deep", "--verbose=2", str(app)],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if signature.returncode != 0:
        raise RuntimeError(f"codesign verification failed: {signature.stderr.strip()}")
    details = subprocess.run(
        ["codesign", "-dv", "--verbose=4", str(app)],
        check=False,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if details.returncode != 0:
        raise RuntimeError(f"Could not record code-signature details: {details.stderr.strip()}")
    return {
        "app": str(app),
        "executable": str(executable),
        "bundleIdentifier": info["CFBundleIdentifier"],
        "revision": host.get("alicornRevision", "unknown"),
        "sdlVersion": host["sdlVersion"],
        "linkage": linkage,
        "applicationSha256": application["sha256"],
        "manifestSha256": sha256(manifest_path),
        "sdlRuntime": host.get("sdlRuntime"),
        "bundledDependencies": bundled_dependencies,
        "signatureVerification": (signature.stdout + signature.stderr).strip(),
        "signatureDetails": (details.stdout + details.stderr).strip(),
        "manifest": str(manifest_path),
    }


def _running_process_for_run(run_id: str) -> int | None:
    result = subprocess.run(
        ["/bin/ps", "-ww", "-axo", "pid=,command="],
        check=True,
        capture_output=True,
        text=True,
        timeout=10,
    )
    needle = f"--desktop-validation-run-id={run_id}"
    matches = [pid for pid, command in parse_process_list(result.stdout) if needle in command]
    if len(matches) > 1:
        raise RuntimeError(f"More than one process carries validation run ID {run_id}")
    return matches[0] if matches else None


def _wait_for_process(run_id: str, launcher: subprocess.Popen[Any], timeout: float) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pid = _running_process_for_run(run_id)
        if pid is not None:
            return pid
        if launcher.poll() is not None:
            raise RuntimeError(
                f"Launcher exited before the app process appeared (status {launcher.returncode})"
            )
        time.sleep(0.2)
    raise TimeoutError(f"App process for run {run_id} did not appear")


def _launcher_command(
    mode: str,
    app: pathlib.Path,
    executable: pathlib.Path,
    run_id: str,
    result_path: pathlib.Path,
    idle_seconds: int,
    stdout_path: pathlib.Path,
    stderr_path: pathlib.Path,
    open_redirects_output: bool,
) -> list[str]:
    app_arguments = [
        "--idle-validation-seconds=" + str(idle_seconds),
        "--desktop-validation-result=" + str(result_path),
        "--desktop-validation-run-id=" + run_id,
    ]
    if mode == "direct":
        return [str(executable), *app_arguments]
    command = ["/usr/bin/open", "-n", "-W"]
    if open_redirects_output:
        command.extend(["--stdout", str(stdout_path), "--stderr", str(stderr_path)])
    command.extend(["-a", str(app), "--args", *app_arguments])
    return command


def run_launch(
    app_info: dict[str, Any],
    mode: str,
    results_dir: pathlib.Path,
    *,
    require_interaction: bool,
    open_redirects_output: bool,
) -> dict[str, Any]:
    require_relaunch_host_output(
        mode,
        require_interaction=require_interaction,
        output_available=open_redirects_output,
    )
    app = pathlib.Path(app_info["app"])
    executable = pathlib.Path(app_info["executable"])
    run_id = uuid.uuid4().hex
    run_dir = results_dir / (app_info["linkage"] + "-" + mode + "-" + run_id)
    run_dir.mkdir(parents=True)
    cwd = run_dir / "working directory with spaces"
    cwd.mkdir()
    result_path = run_dir / "shutdown-result.json"
    stdout_path = run_dir / "stdout.log"
    stderr_path = run_dir / "stderr.log"
    screenshot_path = run_dir / "first-frame.png"
    screenshot_captured = False
    command = _launcher_command(
        mode,
        app,
        executable,
        run_id,
        result_path,
        300 if require_interaction else 2,
        stdout_path,
        stderr_path,
        open_redirects_output,
    )

    environment = os.environ.copy()
    for variable in (
        "DYLD_LIBRARY_PATH",
        "DYLD_FRAMEWORK_PATH",
        "DYLD_INSERT_LIBRARIES",
        "DYLD_FALLBACK_LIBRARY_PATH",
        "SDL_VIDEODRIVER",
    ):
        environment.pop(variable, None)
    with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
        "w", encoding="utf-8"
    ) as stderr:
        if mode == "direct":
            launcher = subprocess.Popen(command, cwd=cwd, env=environment, stdout=stdout, stderr=stderr)
        else:
            launcher = subprocess.Popen(command, cwd="/", env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        pid: int | None = None
        actual_executable: pathlib.Path | None = None
        try:
            pid = launcher.pid if mode == "direct" else _wait_for_process(run_id, launcher, 30)
            actual_executable = verify_process_executable(pid, executable)

            if require_interaction:
                print(f"\n{app_info['linkage']} SDL via {mode}; PID {pid}")
                print(f"Verified process executable: {actual_executable}")
                # Capture while the app launched by Launch Services is still
                # foreground; asking for terminal input first would foreground
                # the terminal and capture the wrong window.
                time.sleep(2)
                capture_screenshot(screenshot_path)
                screenshot_captured = True
                if input(
                    f"Review {screenshot_path}; if the app's first frame is visible, type yes: "
                ).strip().lower() != "yes":
                    raise BlockedError("Operator could not confirm the initial window and frame")
                if input(
                    "Physically click Pointer test once, then Tab until Keyboard test is focused and press Space; "
                    "quit normally with Command-Q or the close button. After it closes, type yes: "
                ).strip().lower() != "yes":
                    raise BlockedError("Operator did not confirm pointer, keyboard, and normal quit")
            timeout = 330 if require_interaction else 30
            wait_for_launcher(launcher, mode, timeout=timeout)
        finally:
            stop_failed_launch(launcher, pid, executable, run_id=run_id)

    if launcher.returncode != 0:
        raise RuntimeError(f"{mode} launch exited with status {launcher.returncode}")
    result = validate_result_file(result_path, run_id, require_interaction=require_interaction)
    logs = stdout_path.read_text(encoding="utf-8", errors="replace")
    if open_redirects_output and mode == "open":
        logs += stderr_path.read_text(encoding="utf-8", errors="replace")
    startup_logs_verified = mode == "direct" or open_redirects_output
    if startup_logs_verified:
        validate_smoke_output(logs, REQUIRED_SDL_VERSION)

    return {
        "runId": run_id,
        "mode": mode,
        "pid": pid,
        "executable": str(actual_executable),
        "command": command,
        "workingDirectory": str(cwd if mode == "direct" else pathlib.Path("/")),
        "exitStatus": launcher.returncode,
        "firstFrameVisuallyConfirmed": require_interaction,
        "pointerInputAttested": require_interaction,
        "keyboardInputAttested": require_interaction,
        "normalQuitAttested": require_interaction,
        "startupEvidence": (
            "host logs verified SDL version and frame submission"
            if startup_logs_verified
            else "operator visually confirmed first frame"
        ),
        "interactionEvidence": (
            "operator-attested physical pointer and keyboard actions; activation counts recorded separately"
            if require_interaction
            else "not required for unattended relaunch"
        ),
        "screenshot": str(screenshot_path) if screenshot_captured else None,
        "shutdownResult": str(result_path),
        **result,
        "logs": {"stdout": str(stdout_path), "stderr": str(stderr_path)},
        "appOpenCapturedApplicationOutput": mode != "open" or open_redirects_output,
    }


def run_matrix(static_app: pathlib.Path, shared_app: pathlib.Path, results_dir: pathlib.Path) -> dict[str, Any]:
    results_dir.mkdir(parents=True, exist_ok=True)
    report_path = results_dir / "macos-desktop-validation.json"
    cell_names = ("static-direct", "static-open", "shared-direct", "shared-open")
    results: dict[str, Any] = {
        "host": {
            "macOS": platform.mac_ver()[0],
            "architecture": platform.machine(),
            "user": getpass.getuser(),
        },
        "status": "PENDING",
        "revision": None,
        "openCapturesAppOutput": None,
        "bundles": {},
        "matrix": {
            name: {"status": "BLOCKED", "reason": "Not run"} for name in cell_names
        },
    }

    def save_report() -> None:
        report_path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")

    save_report()
    blockers = []
    if sys.platform != "darwin":
        blockers.append("Desktop bundle validation requires macOS")
    if not sys.stdin.isatty():
        blockers.append("Interactive desktop validation requires a terminal for operator attestations")
    if shutil.which("/usr/bin/open") is None:
        blockers.append("Launch Services command /usr/bin/open is unavailable")
    if sys.platform == "darwin":
        console_user = subprocess.run(
            ["/usr/bin/stat", "-f", "%Su", "/dev/console"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout.strip()
        results["host"]["consoleUser"] = console_user
        results["host"]["activeConsoleSessionMatchesUser"] = console_user == getpass.getuser()
        if console_user != getpass.getuser():
            blockers.append("No active logged-in GUI session belongs to the current user")
    if blockers:
        results["status"] = "BLOCKED"
        for cell in results["matrix"].values():
            cell["reason"] = "; ".join(blockers)
        save_report()
        raise RuntimeError("; ".join(blockers))

    try:
        static = audit_app(static_app, "static")
        shared = audit_app(shared_app, "shared")
        if static["revision"] != shared["revision"]:
            raise RuntimeError("Static and shared bundles were built from different Alicorn revisions")
        if static["revision"] == "unknown":
            raise RuntimeError("Package manifest does not identify its Alicorn revision")
        results["revision"] = static["revision"]
        results["bundles"] = {"static": static, "shared": shared}
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        results["status"] = "FAIL"
        results["failure"] = str(error)
        for cell in results["matrix"].values():
            cell["reason"] = "Bundle audit failed before launch: " + str(error)
        save_report()
        raise

    open_help = subprocess.run(
        ["/usr/bin/open", "--help"], check=False, capture_output=True, text=True, timeout=10
    )
    output_redirection = app_open_supports_output_redirection(open_help.stdout + open_help.stderr)
    results["openCapturesAppOutput"] = output_redirection

    for app_info in (static, shared):
        for mode in ("direct", "open"):
            cell_name = f"{app_info['linkage']}-{mode}"
            results["matrix"][cell_name] = {"status": "RUNNING"}
            save_report()
            print(
                f"\nValidate {app_info['linkage']} SDL via {mode}: visually confirm the window, "
                "test pointer and keyboard activation, then quit normally."
            )
            try:
                interactive = run_launch(
                    app_info,
                    mode,
                    results_dir,
                    require_interaction=True,
                    open_redirects_output=output_redirection,
                )
                relaunch = run_launch(
                    app_info,
                    mode,
                    results_dir,
                    require_interaction=False,
                    open_redirects_output=output_redirection,
                )
                results["matrix"][cell_name] = {
                    "status": "PASS",
                    "interactiveRun": interactive,
                    "relaunch": relaunch,
                }
            except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, TimeoutError) as error:
                blocked = isinstance(error, BlockedError)
                results["status"] = "BLOCKED" if blocked else "FAIL"
                results["failure"] = str(error)
                results["matrix"][cell_name] = {
                    "status": "BLOCKED" if blocked else "FAIL",
                    "reason": str(error),
                }
                if blocked:
                    for name, cell in results["matrix"].items():
                        if name != cell_name and cell["status"] == "BLOCKED":
                            cell["reason"] = "Not run because desktop acceptance was blocked"
                save_report()
                raise
            save_report()

    results["status"] = "PASS"
    save_report()
    print(f"All four desktop launch cells passed. Evidence: {report_path}")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=pathlib.Path, required=True, help="Static-SDL macOS desktop validation fixture .app")
    parser.add_argument("--shared", type=pathlib.Path, required=True, help="Shared-SDL macOS desktop validation fixture .app")
    parser.add_argument("--results-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()
    run_matrix(args.static, args.shared, args.results_dir.resolve())


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, TimeoutError) as error:
        print(f"macOS desktop validation failed: {error}", file=sys.stderr)
        sys.exit(1)
