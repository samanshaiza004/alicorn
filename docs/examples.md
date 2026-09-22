# Examples

```powershell
odin build examples/hello -out:out/hello.exe
odin build examples/counter -out:out/counter.exe
odin build examples/text_input -out:out/text_input.exe
odin build examples/keyed_list -out:out/keyed_list.exe
odin build examples/advanced_identity -out:out/advanced_identity.exe
odin build examples/identity_torture -out:out/identity_torture.exe
odin build examples/crucible -out:out/crucible.exe
odin build benchmarks -out:out/alicorn_benchmarks.exe
```

`keyed_list` is the compact collection example: it uses
`virtual_list_begin/end`, emits only the visible fixed-row range, and keeps
logical item keys in ordinary Odin code. `identity_torture` is intentionally
headless and runs 5,000 randomized structural operations. `crucible` is the
minimal eight-track state/LOD/invalidation exercise; it prints the inspector
instead of hiding the proof in a large demo. `runa_text <font.ttf>` loads a caller-provided font through the
Runa adapter, lays out the same paragraph twice, and reports the stable cache
entry count. The PowerShell wrapper is
`powershell -File tools/runa.ps1 -Font C:\Windows\Fonts\segoeui.ttf`.

The first application-sized dogfood is maintained in the separate
[Alicorn Monitor repository](https://github.com/samanshaiza004/alicorn-monitor).
Its README documents the pinned Alicorn dependency and native run commands.
