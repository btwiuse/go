# js/wasm Compiler Optimization: Arch-Specific Code Exclusion

## Principle

On js/wasm, the Go compiler only ever targets wasm. Every non-wasm architecture's
SSA rewrite rules, SIMD intrinsic tables, and arch-specific config setup
are dead weight — they consume memory in the wasm binary and during compilation
but are never executed.

The optimization: **exclude non-wasm arch-specific code at compile time** using
build tags. With the package layout introduced by master (splitting `ssa/`
into `ssa/`, `ssacompile/`, `ssarewrite/`), the linker can dead-code
eliminate the data because shared code references excluded symbols via
package-qualified names (e.g. `rewriteamd64.RewriteBlock`) rather than
direct cross-package symbols.

## The Pattern

### 1. Add a build constraint

```go
//go:build !wasm
```

Place this at the top of every non-wasm-arch-specific source file. On wasm
hosts (GOARCH=wasm), these files are never compiled or linked. On all other
hosts, they compile as before.

For SIMD intrinsics in `ssagen/`, the build tag is more specific:

```go
//go:build amd64 && goexperiment.simd
//go:build arm64 && goexperiment.simd
```

These files only compile on amd64/arm64 with the SIMD experiment enabled.

### 2. SIMD intrinsics — function-variable registration

For SIMD intrinsics in `ssagen/`, the per-arch generated files (`simdAMD64intrinsics.go`,
`simdARM64intrinsics.go`) need to register themselves at package init time so
the shared `initIntrinsics` in `intrinsics.go` can call them. They use
package-level function variables guarded by nil checks.

**Declaration** (in shared `intrinsics.go`):
```go
// initAMD64SIMDIntrinsics and initARM64SIMDIntrinsics are set by
// arch-specific init() functions in files with build constraints.
// On platforms without SIMD support (e.g., js/wasm), they remain nil
// and the corresponding generated files are not compiled at all.
var initAMD64SIMDIntrinsics func(addF func(pkg, fn string, b intrinsicBuilder, archFamilies ...sys.ArchFamily))
var initARM64SIMDIntrinsics func(addF func(pkg, fn string, b intrinsicBuilder, archFamilies ...sys.ArchFamily))
```

**Registration** (in the build-tagged file):
```go
//go:build amd64 && goexperiment.simd
package ssagen

func init() {
    initAMD64SIMDIntrinsics = simdAMD64Intrinsics
}
```

**Lookup** (in shared `initIntrinsics`):
```go
if buildcfg.Experiment.SIMD {
    // Only enable intrinsics, if SIMD experiment.
    if initAMD64SIMDIntrinsics != nil {
        initAMD64SIMDIntrinsics(addF)
    }
    if initARM64SIMDIntrinsics != nil {
        initARM64SIMDIntrinsics(addF)
    }
    // ...
}
```

The nil-check pattern is necessary because on non-amd64/arm64 platforms (or
without the SIMD experiment), `initAMD64SIMDIntrinsics` stays at its zero
value (nil), and the corresponding build-tagged files are never compiled.

### 3. SSA rewrite rules — direct package references

For SSA rewrite rules, no registration pattern is needed. Each arch-specific
rewrite file lives in its own subpackage under `ssarewrite/` (e.g.
`ssarewrite/rewriteamd64/rewriteAMD64.go`). The shared `ssacompile/config.go`
references these via package-qualified names in a switch statement:

```go
case "amd64":
    c.LowerBlock = rewriteamd64.RewriteBlock
    c.LowerValue = rewriteamd64.RewriteValue
    // ...
case "wasm":
    c.LowerBlock = rewritewasm.RewriteBlock
    // ...
```

When `//go:build !wasm` is applied to `ssarewrite/rewriteamd64/rewriteAMD64.go`,
on wasm that file is not compiled, so `RewriteBlock` is not defined. But
`ssacompile/config.go`'s `case "amd64":` is also never executed on wasm
(since the compiler only targets wasm). The linker's whole-program analysis
sees no reachable reference to `rewriteamd64.RewriteBlock` and dead-code
eliminates the entire `rewriteamd64` package's contents.

This is why the per-arch packages must live in **separate subdirectories**
(e.g. `ssarewrite/rewriteamd64/`) rather than all in one flat directory —
otherwise the linker sees the package as still in use due to other (wasm)
files in the same package.

### 4. File naming trap

**Never name files `*_GOARCH.go` or `*_GOOS.go`** — Go's build system
automatically applies build constraints to files matching these patterns.

Bad:  `config_amd64.go`  → implicit `//go:build amd64`
Good: `amd64_config.go`  → no implicit constraint

This matters when you want a file that has explicit `//go:build !wasm` (or
similar) but is NOT filtered by GOARCH.

## What Was Excluded

| Layer | Files | Source size | Technique |
|-------|-------|-------------|-----------|
| SIMD intrinsics (ssagen) | `simdAMD64intrinsics.go`, `simdARM64intrinsics.go` | 266 KB | `//go:build <arch> && goexperiment.simd` + function variable + nil check |
| SSA rewrite rules (ssarewrite) | 18 `rewrite*.go` files across amd64, 386, arm, arm64, loong64, mips, mips64, ppc64, riscv64, s390x | ~5.8 MB | `//go:build !wasm` + linker DCE of `rewriteamd64`-style package references |

## Testing

- Full `go test cmd/compile/internal/ssa` passes on non-wasm hosts
- `go test cmd/compile/internal/ssagen` passes
- The `generate_test.go` in `ssa/` was updated to tolerate leading build
  constraint lines before generated-file headers when comparing file contents
  (since rewritten files now have `//go:build !wasm` as line 1)

## Checklist for Future Optimizations

When adding more arch-specific code that should be excluded on js/wasm:

1. Can a `//go:build !wasm` tag be added? (Is the file purely arch-specific
   and only used by other arch-specific code?)
2. If it exports symbols referenced from shared code, the references should
   go through a subpackage boundary (so the linker can DCE the package).
3. For per-arch registration from `init()`, use a package-level function
   variable + nil check (no registry map needed for a small, fixed set of
   arches).
4. Avoid `*_GOARCH.go` / `*_GOOS.go` filename patterns.
5. Run the full test suite for the affected package.
6. Update any "generated file is up to date" tests to handle leading build
   constraint lines.