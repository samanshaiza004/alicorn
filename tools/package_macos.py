#!/usr/bin/env python3
"""Build and verify an unsigned Alicorn macOS .app bundle."""

from __future__ import annotations

import argparse
import atexit
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

SDL_VERSION = "3.4.16"
SDL_SOURCE = "https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz"
SDL_SOURCE_SHA256 = "7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68"


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, capture_output=capture)
    return result.stdout if capture else ""


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def otool_dependencies(path: pathlib.Path) -> list[str]:
    lines = run("otool", "-L", str(path), capture=True).splitlines()[1:]
    return [line.strip().split(" (compatibility version", 1)[0] for line in lines if line.strip()]


def is_sdl_runtime_install_name(dependency: str) -> bool:
    return re.fullmatch(r"(?:lib)?SDL3(?:\.\d+)*\.dylib", pathlib.Path(dependency).name, re.IGNORECASE) is not None


def add_framework_rpath(path: pathlib.Path) -> None:
    load_commands = run("otool", "-l", str(path), capture=True)
    if "@executable_path/../Frameworks" not in load_commands:
        run("install_name_tool", "-add_rpath", "@executable_path/../Frameworks", str(path))


def resolve_bundle_dependency(
    dependency: str,
    image: pathlib.Path,
    contents: pathlib.Path,
    frameworks: pathlib.Path,
    macos: pathlib.Path,
) -> pathlib.Path | None:
    if dependency.startswith(("/System/Library/", "/usr/lib/")):
        return None
    if dependency.startswith("@rpath/"):
        resolved = frameworks / dependency.removeprefix("@rpath/")
    elif dependency.startswith("@executable_path/"):
        resolved = macos / dependency.removeprefix("@executable_path/")
    elif dependency.startswith("@loader_path/"):
        resolved = image.parent / dependency.removeprefix("@loader_path/")
    elif dependency.startswith("/"):
        raise RuntimeError(f"Developer-machine dependency leaks from {image}: {dependency}")
    else:
        raise RuntimeError(f"Unsupported Mach-O dependency in {image}: {dependency}")
    bundle_root = contents.resolve()
    resolved = resolved.resolve()
    try:
        resolved.relative_to(bundle_root)
    except ValueError as error:
        raise RuntimeError(
            f"Bundled dependency escapes application bundle in {image}: {dependency}"
        ) from error
    if not resolved.exists():
        raise RuntimeError(f"Unresolved bundled dependency in {image}: {dependency}")
    return resolved


def validate_bundle_rpath(
    rpath: str,
    image: pathlib.Path,
    contents: pathlib.Path,
    macos: pathlib.Path,
) -> None:
    if rpath in ("/System/Library", "/usr/lib") or rpath.startswith(
        ("/System/Library/", "/usr/lib/")
    ):
        return
    if rpath == "@executable_path":
        resolved = macos
    elif rpath.startswith("@executable_path/"):
        resolved = macos / rpath.removeprefix("@executable_path/")
    elif rpath == "@loader_path":
        resolved = image.parent
    elif rpath.startswith("@loader_path/"):
        resolved = image.parent / rpath.removeprefix("@loader_path/")
    else:
        raise RuntimeError(f"Unsupported/developer-machine LC_RPATH in {image}: {rpath}")

    try:
        resolved.resolve().relative_to(contents.resolve())
    except ValueError as error:
        raise RuntimeError(f"LC_RPATH escapes application bundle in {image}: {rpath}") from error


def package(args: argparse.Namespace) -> None:
    if sys.platform != "darwin":
        raise RuntimeError("macOS app packaging must run on macOS")
    for tool in ("otool", "install_name_tool", "plutil", "lipo"):
        if shutil.which(tool) is None:
            raise RuntimeError(f"Required macOS packaging tool not found: {tool}")

    executable = args.executable.resolve(strict=True)
    metadata_path = args.metadata.resolve(strict=True)
    license_path = args.sdl_license.resolve(strict=True)
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    for field in ("name", "version", "bundleIdentifier", "executableName"):
        if not metadata.get(field):
            raise ValueError(f"Package metadata is missing {field!r}")
    if any(character in metadata["name"] for character in ("/", "\\", ":", "\0")):
        raise ValueError("name must be a bundle display name, not a path")
    executable_name = metadata["executableName"]
    if any(character in executable_name for character in ("/", "\\", ":", "\0")):
        raise ValueError("executableName must be a filename, not a path")
    sdl_version = args.sdl_version or SDL_VERSION
    if args.linkage == "shared" and args.sdl_version is None:
        raise ValueError("Shared SDL packaging requires --sdl-version from the runtime package metadata")
    if len(sdl_version.split(".")) != 3 or not all(part.isdecimal() for part in sdl_version.split(".")):
        raise ValueError(f"SDL version must use major.minor.patch form: {sdl_version!r}")

    final_output = args.output.absolute()
    if final_output.exists() and any(final_output.iterdir()):
        raise FileExistsError(f"Refusing to overwrite non-empty package path: {final_output}")
    final_output.parent.mkdir(parents=True, exist_ok=True)
    staging = pathlib.Path(tempfile.mkdtemp(prefix=final_output.name + ".staging-", dir=final_output.parent))
    atexit.register(lambda path=staging: shutil.rmtree(path) if path.exists() else None)
    app = staging / f"{metadata['name']}.app"
    contents = app / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    frameworks = contents / "Frameworks"
    for directory in (macos, resources, frameworks):
        directory.mkdir(parents=True, exist_ok=True)
    app_executable = macos / executable_name
    shutil.copy2(executable, app_executable)
    shutil.copy2(license_path, resources / "SDL-LICENSE.txt")

    source_dir = metadata_path.parent
    resource_names: set[str] = {"sdl-license.txt"}

    def copy_resource(relative: str) -> None:
        source = (source_dir / relative).resolve(strict=True)
        if not source.is_file():
            raise ValueError(f"Resource is not a file: {source}")
        resource_key = source.name.casefold()
        if resource_key in resource_names:
            raise ValueError(f"Duplicate resource basename: {source.name}")
        resource_names.add(resource_key)
        shutil.copy2(source, resources / source.name)

    if metadata.get("icon"):
        copy_resource(metadata["icon"])
    for resource in metadata.get("resources", []):
        copy_resource(resource)

    private_libraries: dict[str, pathlib.Path] = {}
    for relative in metadata.get("privateLibraries", []):
        source = (source_dir / relative).resolve(strict=True)
        if source.suffix != ".dylib":
            raise ValueError(f"macOS privateLibraries entries must be .dylib files: {relative}")
        destination = frameworks / source.name
        if destination.name.casefold() in private_libraries:
            raise ValueError(f"Duplicate private library basename: {destination.name}")
        shutil.copy2(source, destination)
        private_libraries[destination.name.casefold()] = destination

    if args.linkage == "shared":
        if args.sdl_runtime is None:
            raise ValueError("Shared SDL packaging requires --sdl-runtime")
        runtime = args.sdl_runtime.resolve(strict=True)
        if "Mach-O" not in run("file", str(runtime), capture=True):
            raise ValueError(f"SDL runtime is not a Mach-O library: {runtime}")
        destination = frameworks / "SDL3.dylib"
        if destination.name.casefold() in private_libraries:
            raise ValueError("privateLibraries must not supply SDL3.dylib when SDL linkage is shared")
        shutil.copy2(runtime, destination)
        run("install_name_tool", "-id", "@rpath/SDL3.dylib", str(destination))
        private_libraries[destination.name.casefold()] = destination

    # Give packaged dylibs stable bundle-relative install names and rewrite
    # build-machine absolute paths only when they refer to a dylib we copied.
    for library in private_libraries.values():
        run("install_name_tool", "-id", f"@rpath/{library.name}", str(library))

    images = [app_executable, *private_libraries.values()]
    for image in images:
        run("lipo", "-verify_arch", os.uname().machine, str(image))
        for dependency in otool_dependencies(image):
            basename = pathlib.Path(dependency).name
            bundled = frameworks / basename
            if bundled.is_file():
                run("install_name_tool", "-change", dependency, f"@rpath/{basename}", str(image))
            elif args.linkage == "shared" and is_sdl_runtime_install_name(dependency):
                run("install_name_tool", "-change", dependency, "@rpath/SDL3.dylib", str(image))
            elif args.linkage == "static" and is_sdl_runtime_install_name(dependency):
                raise RuntimeError(f"Static app still links SDL dynamically: {dependency}")
        add_framework_rpath(image)

    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": executable_name,
        "CFBundleIdentifier": metadata["bundleIdentifier"],
        "CFBundleName": metadata["name"],
        "CFBundleDisplayName": metadata["name"],
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": str(metadata["version"]),
        "CFBundleVersion": str(metadata["version"]),
        "LSMinimumSystemVersion": str(metadata.get("minimumMacOSVersion") or "13.0"),
        "NSHighResolutionCapable": True,
    }
    if metadata.get("icon"):
        info["CFBundleIconFile"] = pathlib.Path(metadata["icon"]).name
    with (contents / "Info.plist").open("wb") as plist:
        plistlib.dump(info, plist, fmt=plistlib.FMT_XML, sort_keys=False)
    run("plutil", "-lint", str(contents / "Info.plist"))

    system_dependencies: set[str] = set()
    bundled_dependencies: set[str] = set()

    def resolve(image: pathlib.Path, dependency: str) -> None:
        resolved = resolve_bundle_dependency(dependency, image, contents, frameworks, macos)
        if resolved is None:
            system_dependencies.add(dependency)
            return
        bundled_dependencies.add(dependency)

    for image in images:
        for dependency in otool_dependencies(image):
            if args.linkage == "static" and is_sdl_runtime_install_name(dependency):
                raise RuntimeError(f"Static app unexpectedly depends on SDL: {dependency}")
            resolve(image, dependency)
        commands = run("otool", "-l", str(image), capture=True)
        lines = commands.splitlines()
        for index, line in enumerate(lines):
            if line.strip() == "cmd LC_RPATH":
                for path_line in lines[index + 1 : index + 4]:
                    if path_line.strip().startswith("path "):
                        rpath = path_line.strip().split(" (offset", 1)[0][5:]
                        validate_bundle_rpath(rpath, image, contents, macos)

    if args.linkage == "shared" and "@rpath/SDL3.dylib" not in bundled_dependencies:
        raise RuntimeError("Shared SDL package does not resolve its bundled SDL3.dylib")

    git_revision = subprocess.run(
        ["git", "-C", str(pathlib.Path(__file__).resolve().parents[1]), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    ).stdout.strip() or "unknown"
    manifest = {
        "schema": 1,
        "application": {
            "name": metadata["name"],
            "version": str(metadata["version"]),
            "bundleIdentifier": metadata["bundleIdentifier"],
            "executable": str(app_executable.relative_to(app)),
            "sha256": sha256(app_executable),
            "resources": [
                {"name": str(path.relative_to(app)), "sha256": sha256(path)}
                for path in sorted(resources.iterdir())
                if path.is_file() and path.name != "SDL-LICENSE.txt"
            ],
        },
        "target": f"macos-{os.uname().machine}",
        "host": {
            "alicornRevision": git_revision,
            "sdlVersion": sdl_version,
            "sdlLinkage": args.linkage,
            "sdlSource": SDL_SOURCE if args.linkage == "static" else None,
            "sdlSourceSha256": SDL_SOURCE_SHA256 if args.linkage == "static" else None,
            "license": {
                "path": "Contents/Resources/SDL-LICENSE.txt",
                "sha256": sha256(resources / "SDL-LICENSE.txt"),
            },
        },
        "dependencies": {
            "system": sorted(system_dependencies),
            "bundled": [
                {"name": str(path.relative_to(app)), "sha256": sha256(path)}
                for path in sorted(private_libraries.values())
            ],
        },
    }
    (staging / "alicorn-package.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    if args.smoke_test:
        with tempfile.TemporaryDirectory(prefix="alicorn-package-smoke-") as empty:
            subprocess.run(
                [str(app_executable), "--idle-validation-seconds=2"],
                cwd=empty,
                check=True,
                timeout=30,
            )
        print("Empty-directory launch smoke passed.")
    if final_output.exists():
        final_output.rmdir()
    staging.rename(final_output)
    print(f"Verified app bundle: {final_output / app.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=pathlib.Path, required=True)
    parser.add_argument("--metadata", type=pathlib.Path, required=True)
    parser.add_argument("--linkage", choices=("static", "shared"), required=True)
    parser.add_argument("--sdl-version", help="SDL major.minor.patch version (required for shared linkage)")
    parser.add_argument("--sdl-license", type=pathlib.Path, required=True)
    parser.add_argument("--sdl-runtime", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--smoke-test", action="store_true")
    args = parser.parse_args()
    package(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"package_app: {error}", file=sys.stderr)
        sys.exit(1)
