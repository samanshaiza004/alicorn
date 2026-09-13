# Examples

```powershell
odin build examples/identity_torture -out:out/identity_torture.exe
odin build examples/crucible -out:out/crucible.exe
odin build benchmarks -out:out/alicorn_benchmarks.exe
```

`identity_torture` is intentionally headless and runs 5,000 randomized
structural operations. `crucible` is the minimal eight-track state/LOD/
invalidation exercise; it prints the inspector instead of hiding the proof in
a large demo.

