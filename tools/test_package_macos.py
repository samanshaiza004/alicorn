#!/usr/bin/env python3
"""Platform-independent regression tests for macOS package path auditing."""

import pathlib
import unittest
from unittest.mock import patch

from package_macos import (
    is_sdl_runtime_install_name,
    resolve_bundle_dependency,
    validate_bundle_rpath,
)


class PackageDependencyAuditTests(unittest.TestCase):
    contents = pathlib.Path("App.app") / "Contents"
    frameworks = contents / "Frameworks"
    macos = contents / "MacOS"
    image = macos / "App"

    def test_recognizes_versioned_sdl_dylib_names_only(self):
        self.assertTrue(is_sdl_runtime_install_name("@rpath/libSDL3.0.dylib"))
        self.assertTrue(is_sdl_runtime_install_name("/opt/homebrew/lib/libSDL3.dylib"))
        self.assertFalse(is_sdl_runtime_install_name("@rpath/libSDL3_image.dylib"))

    def test_rejects_homebrew_absolute_dependency(self):
        with self.assertRaisesRegex(RuntimeError, "Developer-machine dependency"):
            resolve_bundle_dependency(
                "/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib",
                self.image,
                self.contents,
                self.frameworks,
                self.macos,
            )

    def test_accepts_system_dependency(self):
        self.assertIsNone(
            resolve_bundle_dependency(
                "/System/Library/Frameworks/Cocoa.framework/Versions/A/Cocoa",
                self.image,
                self.contents,
                self.frameworks,
                self.macos,
            )
        )

    def test_resolves_only_existing_bundle_relative_dependency(self):
        dependency = (self.frameworks / "SDL3.dylib").resolve()
        with patch.object(pathlib.Path, "exists", return_value=True):
            self.assertEqual(
                resolve_bundle_dependency(
                    "@rpath/SDL3.dylib",
                    self.image,
                    self.contents,
                    self.frameworks,
                    self.macos,
                ),
                dependency,
            )
        with patch.object(pathlib.Path, "exists", return_value=False):
            with self.assertRaisesRegex(RuntimeError, "Unresolved bundled dependency"):
                resolve_bundle_dependency(
                    "@rpath/missing.dylib",
                    self.image,
                    self.contents,
                    self.frameworks,
                    self.macos,
                )

    def test_rejects_bundle_dependency_that_escapes_contents(self):
        with patch.object(pathlib.Path, "exists", return_value=True):
            with self.assertRaisesRegex(RuntimeError, "escapes application bundle"):
                resolve_bundle_dependency(
                    "@rpath/../../../../outside.dylib",
                    self.image,
                    self.contents,
                    self.frameworks,
                    self.macos,
                )

    def test_rpath_must_resolve_inside_bundle_or_to_system(self):
        validate_bundle_rpath(
            "@executable_path/../Frameworks",
            self.image,
            self.contents,
            self.macos,
        )
        validate_bundle_rpath(
            "/usr/lib",
            self.image,
            self.contents,
            self.macos,
        )
        with self.assertRaisesRegex(RuntimeError, "escapes application bundle"):
            validate_bundle_rpath(
                "@executable_path/../../../../opt/homebrew/lib",
                self.image,
                self.contents,
                self.macos,
            )
        with self.assertRaisesRegex(RuntimeError, "Unsupported/developer-machine"):
            validate_bundle_rpath(
                "/opt/homebrew/lib",
                self.image,
                self.contents,
                self.macos,
            )
        with self.assertRaisesRegex(RuntimeError, "Unsupported/developer-machine"):
            validate_bundle_rpath(
                str(self.contents / "Frameworks"),
                self.image,
                self.contents,
                self.macos,
            )


if __name__ == "__main__":
    unittest.main()
