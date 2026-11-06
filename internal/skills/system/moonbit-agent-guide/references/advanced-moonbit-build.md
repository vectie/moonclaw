# MoonBit build configuration

Preserve the repository's supported targets and dependency structure. Use
`moon.mod` for module metadata/dependencies and `moon.pkg` for package imports
and compiler/link options; do not introduce legacy JSON manifests.

Package imports are explicit, including non-prelude standard-library packages:

```moonbit
import {
  "moonbitlang/core/json",
}
```

Select a backend with the existing command's `--target` argument. A package
that intentionally supports only one backend declares `supported_targets`.
For individual Native-only source files and C stubs, existing packages use:

```moonbit
options(
  "native-stub": ["stub.c"],
  targets: { "ffi.mbt": ["native"] },
)
```

Native FFI belongs in the package that owns the operation. Keep externs private,
follow existing borrow/ownership annotations, and check generated interfaces.
Use the project's installed compiler/linker configuration rather than adding
machine-specific paths to a reusable package.

Build/link flags, warning controls and supported-target expressions depend on
the installed toolchain. Start with nearby `moon.pkg` examples and command help;
use actual compiler diagnostics to validate the selected configuration.
