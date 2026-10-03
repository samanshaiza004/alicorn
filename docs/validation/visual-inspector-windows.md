# Visual inspector Windows smoke

This records a native host check for the opt-in visual inspector on Windows.
It complements the deterministic runtime and native-host tests; it is not a
platform certification for every GPU driver or window manager.

## Environment

| Item | Environment |
|---|---|
| OS | Windows 10 Home 22H2, build 19045.6466 |
| CPU | AMD Ryzen 5 7600X, 12 logical processors |
| GPU | NVIDIA GeForce RTX 2080 SUPER |
| GPU driver | 32.0.15.9597 |
| SDL | 3.4.2 |
| Odin | `dev-2026-09-nightly:a2fb372` |
| Renderer | Direct3D 12 |

## Results

From the repository root, `.\tools\check.ps1 -Odin C:\Users\saman\Documents\odin\dist\odin.exe`
and `.\tools\test.ps1 -Odin C:\Users\saman\Documents\odin\dist\odin.exe`
passed. This includes 32 runtime tests, 42 native-host tests, foundation tests,
and the generic native text-input contract.

The native smoke commands below completed on Direct3D 12:

```powershell
.\tools\native_sdl_gpu.ps1 -Odin C:\Users\saman\Documents\odin\dist\odin.exe -InspectorOpen -Smoke -Diagnostics -CaptureAfter 0
.\out\alicorn_sdl_gpu.exe --inspector-fixture --inspector-input-smoke
.\out\alicorn_sdl_gpu.exe --inspector-fixture --inspector-input-smoke --inspector-identity-error
.\out\alicorn_sdl_gpu.exe --inspector-fixture --inspector-open --inspector-identity-error --smoke --diagnostics --capture-after=0
```

The visible idle smoke produced two GPU submissions and returned to one event
wait during its three-second run. Both input smokes reported zero application
activations, unchanged application text, restored text-field focus, preserved
semantic focus ownership, and no application text-change dispatch. The
identity-error variant remained inspectable and completed without retrying the
failed application description. The startup screenshot included both the
fixture and the inspector panel.

Run these commands again when changing host input ownership, inspector
composition, window lifecycle, or GPU rendering.
