#!/usr/bin/env python3
"""Platform-independent tests for the interactive macOS package validator."""

import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import validate_macos_package_desktop
from validate_macos_package_desktop import (
    app_open_supports_output_redirection,
    capture_screenshot,
    parse_process_list,
    require_relaunch_host_output,
    run_matrix,
    stop_failed_launch,
    validate_result_file,
    verify_process_executable,
    wait_for_launcher,
    _wait_for_process,
)


class DesktopValidationHelperTests(unittest.TestCase):
    def test_process_list_parser_keeps_full_command(self):
        self.assertEqual(
            parse_process_list("  123 /Applications/Alicorn Hello.app/Contents/MacOS/App --arg x\n"),
            [(123, "/Applications/Alicorn Hello.app/Contents/MacOS/App --arg x")],
        )

    def test_open_output_capture_requires_both_stream_options(self):
        self.assertTrue(app_open_supports_output_redirection("--stdout file --stderr file"))
        self.assertFalse(app_open_supports_output_redirection("--stdout file"))

    def test_result_file_requires_matching_run_and_both_interactions(self):
        with tempfile.TemporaryDirectory() as directory:
            result_path = pathlib.Path(directory) / "result.json"
            result_path.write_text(
                json.dumps({"runId": "run-1", "pointerActivations": 1, "keyboardActivations": 1}),
                encoding="utf-8",
            )
            self.assertEqual(
                validate_result_file(result_path, "run-1", require_interaction=True)["pointerActivations"],
                1,
            )
            with self.assertRaisesRegex(RuntimeError, "different launch"):
                validate_result_file(result_path, "run-2", require_interaction=False)

            result_path.write_text(
                json.dumps({"runId": "run-1", "pointerActivations": 1, "keyboardActivations": 0}),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "Both validation buttons"):
                validate_result_file(result_path, "run-1", require_interaction=True)

    def test_missing_host_return_marker_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "did not return"):
                validate_result_file(
                    pathlib.Path(directory) / "missing.json",
                    "run-1",
                    require_interaction=False,
                )

    def test_open_relaunch_without_host_logs_is_blocked(self):
        with self.assertRaisesRegex(RuntimeError, "cannot verify host startup"):
            require_relaunch_host_output("open", require_interaction=False, output_available=False)
        require_relaunch_host_output("open", require_interaction=True, output_available=False)
        require_relaunch_host_output("open", require_interaction=False, output_available=True)

    def test_unverifiable_open_relaunch_is_rejected_before_starting(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
            validate_macos_package_desktop.subprocess, "Popen"
        ) as popen:
            with self.assertRaisesRegex(RuntimeError, "relaunch is BLOCKED"):
                validate_macos_package_desktop.run_launch(
                    {
                        "app": "/Applications/Alicorn.app",
                        "executable": "/Applications/Alicorn.app/Contents/MacOS/Alicorn",
                        "linkage": "shared",
                    },
                    "open",
                    pathlib.Path(directory),
                    require_interaction=False,
                    open_redirects_output=False,
                )
            popen.assert_not_called()

    def test_process_identity_mismatch_fails(self):
        expected = pathlib.Path("/Applications/Alicorn.app/Contents/MacOS/Alicorn")
        actual = pathlib.Path("/Applications/Other.app/Contents/MacOS/Alicorn")
        with patch.object(validate_macos_package_desktop, "process_executable", return_value=actual):
            with self.assertRaisesRegex(RuntimeError, "Launch resolved to"):
                verify_process_executable(123, expected)

    def test_open_exiting_before_app_process_appears_fails(self):
        launcher = Mock()
        launcher.poll.return_value = 1
        with patch.object(validate_macos_package_desktop, "_running_process_for_run", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "before the app process appeared"):
                _wait_for_process("run-1", launcher, timeout=1)

    def test_screen_capture_failure_is_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / "frame.png"
            failed = subprocess.CompletedProcess(["screencapture"], 1, "", "permission denied")
            with patch("validate_macos_package_desktop.shutil.which", return_value="/usr/sbin/screencapture"), patch(
                "validate_macos_package_desktop.subprocess.run", return_value=failed
            ):
                with self.assertRaisesRegex(RuntimeError, "Could not capture"):
                    capture_screenshot(target)

    def test_application_timeout_is_reported(self):
        launcher = Mock()
        launcher.wait.side_effect = subprocess.TimeoutExpired("app", 30)
        with self.assertRaisesRegex(TimeoutError, "did not quit within 30 seconds"):
            wait_for_launcher(launcher, "direct", timeout=30)

    def test_interrupted_launch_cleanup_terminates_only_verified_process(self):
        expected = pathlib.Path("/Applications/Alicorn.app/Contents/MacOS/Alicorn")
        launcher = Mock()
        launcher.poll.return_value = None
        launcher.wait.return_value = 0
        with patch.object(validate_macos_package_desktop, "process_executable", return_value=expected), patch(
            "validate_macos_package_desktop.os.kill"
        ) as kill:
            stop_failed_launch(launcher, 123, expected)
        kill.assert_called_once()
        launcher.wait.assert_called_once_with(timeout=5)

        launcher = Mock()
        launcher.poll.return_value = None
        launcher.wait.return_value = 0
        other = pathlib.Path("/Applications/Other.app/Contents/MacOS/Alicorn")
        with patch.object(validate_macos_package_desktop, "process_executable", return_value=other), patch(
            "validate_macos_package_desktop.os.kill"
        ) as kill:
            stop_failed_launch(launcher, 123, expected)
        kill.assert_not_called()

    def test_interrupted_launch_cleanup_escalates_if_graceful_stop_times_out(self):
        expected = pathlib.Path("/Applications/Alicorn.app/Contents/MacOS/Alicorn")
        launcher = Mock()
        launcher.poll.return_value = None
        launcher.wait.side_effect = [subprocess.TimeoutExpired("open", 5), 0]
        with patch.object(validate_macos_package_desktop, "process_executable", return_value=expected), patch(
            "validate_macos_package_desktop.os.kill"
        ) as kill:
            stop_failed_launch(launcher, 123, expected)
        self.assertEqual(
            [entry.args for entry in kill.call_args_list],
            [
                (123, validate_macos_package_desktop.signal.SIGTERM),
                (123, validate_macos_package_desktop.signal.SIGKILL),
            ],
        )
        launcher.terminate.assert_not_called()

    def test_interrupted_launch_cleanup_discovers_run_id_process(self):
        expected = pathlib.Path("/Applications/Alicorn.app/Contents/MacOS/Alicorn")
        launcher = Mock()
        launcher.poll.return_value = None
        launcher.wait.return_value = 0
        with patch.object(validate_macos_package_desktop, "_running_process_for_run", return_value=456), patch.object(
            validate_macos_package_desktop, "process_executable", return_value=expected
        ), patch("validate_macos_package_desktop.os.kill") as kill:
            stop_failed_launch(launcher, None, expected, run_id="run-1")
        kill.assert_called_once_with(456, validate_macos_package_desktop.signal.SIGTERM)

    def test_unavailable_desktop_environment_writes_blocked_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(validate_macos_package_desktop.sys, "platform", "linux"), patch.object(
                validate_macos_package_desktop.sys.stdin, "isatty", return_value=True
            ):
                with self.assertRaisesRegex(RuntimeError, "requires macOS"):
                    run_matrix(pathlib.Path("static.app"), pathlib.Path("shared.app"), pathlib.Path(directory))

            report = json.loads(
                (pathlib.Path(directory) / "macos-desktop-validation.json").read_text(encoding="utf-8")
            )
            self.assertEqual(report["status"], "BLOCKED")
            self.assertEqual(
                {cell["status"] for cell in report["matrix"].values()},
                {"BLOCKED"},
            )


if __name__ == "__main__":
    unittest.main()
