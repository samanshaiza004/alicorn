#!/usr/bin/env python3
"""Platform-independent tests for the interactive macOS package validator."""

import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import validate_macos_package_desktop
from validate_macos_package_desktop import (
    app_open_supports_output_redirection,
    parse_process_list,
    run_matrix,
    validate_result_file,
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
