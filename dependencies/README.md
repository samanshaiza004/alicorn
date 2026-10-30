# Standalone AccessKit binding

[`odin-accesskit.json`](odin-accesskit.json) records the repository and full
commit SHA of [odin-accesskit](https://github.com/samanshaiza004/odin-accesskit).
The helpers reject incomplete pins and never resolve a branch or fetch a latest
revision.

Alicorn prepares a clean detached checkout at `.deps/odin-accesskit`. A pin
change fetches only that commit. A dirty checkout or mismatched origin is
rejected. The standalone `tools/bootstrap.ps1` or `tools/bootstrap.sh` owns the
AccessKit C download and checksums. Alicorn passes `.deps/accesskit` as its
cache root, preserving the existing native cache layout.

The standalone repository also owns binding tests, C-header ABI probes, and
the independent binding consumer. `tools/test.ps1`, `tools/check.sh`, and
`tools/test.sh` delegate to its check script. Alicorn retains its semantic
projection and native host integration tests.

## External native applications

An application importing `alicorn:ui` or `alicorn:native/sdl_gpu` also needs the
transitive `accesskit` and `accesskit_c` collections, even if it does not import that package
directly. For Windows static builds, use the
[native-link recipe](../docs/native-link-recipe.md) and forward every entry in
`recipe.odin.compilerArguments`. That array supplies both collections and system linker flags. AccessKit
archives resolve through `accesskit_c`, so spaced library paths require no
nested quotes in `-extra-linker-flags`. Keep your own `-collection:alicorn=...` argument.

For a shared-SDL Windows build from another working directory:

```powershell
$Alicorn = 'C:\src\alicorn'
. "$Alicorn\tools\common.ps1"
$Odin = Resolve-AlicornOdin
$AccessKit = Get-AlicornAccessKit
& $Odin build C:\src\my-app "-collection:alicorn=$Alicorn" @($AccessKit.CompilerArguments) -out:C:\src\my-app\app.exe
```

Stage the matching SDK `vendor/sdl3/SDL3.dll` beside the executable as usual.
`Get-AlicornAccessKit` retains `Root`, `Archive`, `Library`, `LibraryDirectory`,
and system-only `LinkerFlags` from the standalone bootstrap. It adds
`BindingRoot`, `BindingRepository`, and `BindingCommit`, and prepends the
binding collection to the native bootstrap's `CompilerArguments` array.

For a shell build, set `REPO_ROOT` to Alicorn's absolute path before sourcing
its helper; the application can remain in a different working directory:

```sh
REPO_ROOT=/src/alicorn
. "$REPO_ROOT/tools/accesskit.sh"
binding=$(alicorn_accesskit_binding_root)
native=$(alicorn_accesskit_library_directory)
flags=$(alicorn_accesskit_linker_flags)
set -- "-collection:alicorn=$REPO_ROOT" "-collection:accesskit=$binding" \
  "-collection:accesskit_c=$native"
if [ -n "$flags" ]; then set -- "$@" "-extra-linker-flags:$flags"; fi
odin build /src/my-app "$@" -out:/src/my-app/app
```

The standalone shell bootstrap's `--library-directory` mode returns an
absolute library directory; its default output contains only system flags. SDL3 and other
platform prerequisites still follow Alicorn's normal native build contract.
