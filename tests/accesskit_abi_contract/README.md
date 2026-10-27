# AccessKit C ABI contract probe

This probe compiles against the repository cache for AccessKit C 0.23.1:

```text
.deps/accesskit/accesskit-c-0.23.1/include/accesskit.h
```

It verifies the C layout mirrored by the standalone Odin binding in
`accesskit/accesskit.odin`: rectangle and text-selection
fields, action request and payload sizes/offsets, integer widths, plus every
role, action, and action-data tag currently used by the bridge. It also passes
`accesskit_rect` and `accesskit_text_selection` through C functions by value.
The probe does not link AccessKit, SDL, or open a window; it checks the pinned
header contract without requiring a native accessibility session.

The role assertions mirror the named role constants in the Odin package. The
first run against the cached 0.23.1 header found two preexisting mismatches:
`LIST_BOX` was 85 instead of 87, and `STATUS` was 114 instead of 116. Both
package constants now match the pinned header, and this contract check guards
against drift.

Run on macOS with Clang:

```sh
sh tools/check_accesskit_abi_contract.sh
```

`CC` may select another C11 compiler executable. The script uses only the
already-cached header and does not fetch or install dependencies.

Run on Windows from a Visual Studio Developer PowerShell:

```powershell
./tools/check_accesskit_abi_contract.ps1
```

Or pass an explicit compiler path with `-Compiler`. The checker uses MSVC's
C11 mode and removes its temporary executable and object files on exit.

The repository checks run this after bootstrapping the pinned dependency:
`tools/check.sh` on macOS and `tools/test.ps1` on Windows. Neither path
downloads dependencies from this checker itself.
