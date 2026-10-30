#!/usr/bin/env python3
"""Platform-independent regression tests for macOS package path auditing."""

import pathlib
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

import package_macos

from package_macos import (
    SDL_SOURCE,
    SDL_SOURCE_SHA256,
    SDL_VERSION,
    detect_sdl_runtime_version,
    is_sdl_runtime_install_name,
    resolve_bundle_dependency,
    sdl_source_provenance,
    sign_local_bundle,
    sdl_runtime_provenance,
    validate_bundle_rpath,
    validate_smoke_output,
    validate_sdl_runtime_version,
)


class PackageDependencyAuditTests(unittest.TestCase):
    def test_accesskit_notices_include_wrapper_and_all_upstream_texts_with_spaces(self):
        with tempfile.TemporaryDirectory(prefix="Alicorn notices with spaces ") as directory:
            root = pathlib.Path(directory)
            sources = {
                "accesskit_license_apache": "LICENSE-APACHE",
                "accesskit_license_mit": "LICENSE-MIT",
                "accesskit_license_chromium": "LICENSE.chromium",
                "accesskit_authors": "AUTHORS",
                "accesskit_binding_license": "wrapper LICENSE",
            }
            for name in sources.values():
                (root / name).write_text(name, encoding="utf-8")
            inputs = package_macos.accesskit_notice_inputs(SimpleNamespace(**{
                field: root / name for field, name in sources.items()
            }))
            self.assertEqual(list(inputs), [
                "AccessKit-LICENSE-APACHE.txt", "AccessKit-LICENSE-MIT.txt",
                "AccessKit-LICENSE.chromium.txt", "AccessKit-AUTHORS.txt", "odin-accesskit-LICENSE.txt",
            ])
            self.assertEqual(inputs["odin-accesskit-LICENSE.txt"].read_text(), "wrapper LICENSE")
            self.assertTrue(all(source.is_absolute() for source in inputs.values()))
            (root / "AUTHORS").unlink()
            with self.assertRaises(FileNotFoundError):
                package_macos.accesskit_notice_inputs(SimpleNamespace(**{
                    field: root / name for field, name in sources.items()
                }))

    def test_accesskit_supplemental_notices_require_core_license_inputs(self):
        with self.assertRaisesRegex(ValueError, "require the Apache and MIT"):
            package_macos.accesskit_notice_inputs(SimpleNamespace(
                accesskit_license_apache=None, accesskit_license_mit=None,
                accesskit_binding_license=pathlib.Path("wrapper LICENSE"),
            ))

    contents = pathlib.Path("App.app") / "Contents"
    frameworks = contents / "Frameworks"
    macos = contents / "MacOS"
    image = macos / "App"

    def test_local_bundle_signing_covers_nested_images_before_the_bundle(self):
        images = [self.image, self.frameworks / "SDL3.dylib"]
        with patch("package_macos.run") as run:
            sign_local_bundle(self.contents.parent, images)

        self.assertEqual(
            run.call_args_list,
            [
                unittest.mock.call("codesign", "--force", "--sign", "-", "--timestamp=none", str(image))
                for image in images
            ]
            + [
                unittest.mock.call("codesign", "--force", "--sign", "-", "--timestamp=none", str(self.contents.parent)),
                unittest.mock.call("codesign", "--verify", "--strict", "--deep", str(self.contents.parent)),
            ],
        )

    def test_sdl_source_pin_matches_release(self):
        self.assertEqual(SDL_VERSION, "3.4.18")
        self.assertEqual(
            SDL_SOURCE,
            "https://github.com/libsdl-org/SDL/releases/download/release-3.4.18/SDL3-3.4.18.tar.gz",
        )
        self.assertEqual(
            SDL_SOURCE_SHA256,
            "9c75cf16330322c217dedd2e0609f1124f1b54b8633e763467b4684d0f4334a3",
        )
        self.assertEqual(
            sdl_source_provenance(),
            {
                "sdlSource": SDL_SOURCE,
                "sdlSourceSha256": SDL_SOURCE_SHA256,
            },
        )

    def test_shared_provenance_hashes_the_actual_input_and_does_not_claim_source_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = pathlib.Path(directory) / "libSDL3.0.dylib"
            runtime.write_bytes(b"test SDL dylib")

            provenance = sdl_runtime_provenance(runtime, "3.4.18", "homebrew")

        self.assertEqual(
            provenance["sdlRuntime"],
            {
                "inputFilename": "libSDL3.0.dylib",
                "inputSha256": "27c0d2d7ee75d88c6fa8beedf05a9d8f3c6bed434d1527f38ad90b186485e942",
                "detectedVersion": "3.4.18",
                "provenance": {"provider": "homebrew", "formula": "sdl3"},
            },
        )
        self.assertNotIn("sdlSource", provenance)

    def test_shared_version_is_read_from_the_supplied_library(self):
        get_version = Mock(return_value=3_004_018)
        library = SimpleNamespace(SDL_GetVersion=get_version)
        with tempfile.TemporaryDirectory() as directory:
            runtime = pathlib.Path(directory) / "libSDL3.dylib"
            runtime.touch()
            with patch("package_macos.ctypes.CDLL", return_value=library):
                self.assertEqual(detect_sdl_runtime_version(runtime), "3.4.18")
        self.assertEqual(get_version.argtypes, [])
        self.assertEqual(get_version.restype, package_macos.ctypes.c_int)

    def test_shared_runtime_must_match_host_exact_version(self):
        validate_sdl_runtime_version("3.4.18", "3.4.18")
        with self.assertRaisesRegex(RuntimeError, "package expects 3.4.18"):
            validate_sdl_runtime_version("3.4.19", "3.4.18")
        with self.assertRaisesRegex(RuntimeError, "macOS Alicorn requires SDL 3.4.18"):
            validate_sdl_runtime_version("3.4.19", "3.4.19")

    def test_launch_smoke_requires_expected_runtime_and_gpu_submission(self):
        validate_smoke_output(
            "sdl3_version 3 4 18\nSDL application PASS submissions 2 retired 2\n",
            "3.4.18",
        )
        with self.assertRaisesRegex(RuntimeError, "SDL 3.4.19; expected 3.4.18"):
            validate_smoke_output(
                "sdl3_version 3 4 19\nSDL application PASS submissions 2\n",
                "3.4.18",
            )
        with self.assertRaisesRegex(RuntimeError, "GPU frame submission"):
            validate_smoke_output(
                "sdl3_version 3 4 18\nSDL application PASS submissions 0\n",
                "3.4.18",
            )

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
