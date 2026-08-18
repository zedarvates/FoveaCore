<div align="center">
  <img src="../../../icon.svg" alt="FoveaEngine logo" width="80" />

  <h1>C++ GDExtension build target</h1>
  <p>Build and smoke-test the isolated Windows C++ renderer without replacing the canonical Rust runtime.</p>
  <p><a href="../../../README.md">Project overview</a> · <a href="../../../.github/workflows/ci.yml">CI workflow</a> · <a href="../foveacore.gdextension">Rust descriptor</a></p>
</div>

> [!IMPORTANT]
> Rust remains the canonical packaged GDExtension. The C++ target is an experimental Windows-only alternative with a distinct entry symbol, binary, and opt-in descriptor template.

## Current status

| Contract | Repository state |
| --- | --- |
| Canonical native runtime | Rust: `gdext_rust_init` in `bin/foveacore.dll` |
| Experimental C++ runtime | `foveacore_cpp_init` in `bin/foveacore_cpp.dll` |
| Descriptor | [`foveacore_cpp.gdextension.example`](foveacore_cpp.gdextension.example), loaded only by the explicit smoke harness |
| Supported C++ build | Windows x86_64, `template_release` |
| Ownership contract | 14/14 Godot assertions passed |
| Local compilation | Passed with SCons 4.10.1 and MSVC |
| Export inspection | `dumpbin` found only `foveacore_cpp_init` in the C++ DLL; the Rust DLL retained `gdext_rust_init` |
| Godot load smoke | `FoveaRenderer` registered and instantiated; exit `0` |
| Missing-binary control | Failed closed; exit `1` |
| Release packaging | Rust only; C++ remains a standalone CI artifact |

The source contract rejects every C++ configuration except `windows/template_release/x86_64`. That boundary is intentional until another platform and target are compiled and smoke-tested.

## Prerequisites

- Python with SCons 4;
- Visual Studio Build Tools with the C++ workload;
- the pinned `godot-cpp` submodule.

Initialize the existing submodule instead of cloning another copy:

```bash
git submodule update --init --recursive addons/foveacore/gdextension/godot-cpp
python -m pip install "scons>=4,<5"
```

## Build the isolated C++ artifact

From the repository root:

```bash
cd addons/foveacore/gdextension/godot-cpp
scons platform=windows target=template_release arch=x86_64

cd ..
python -m SCons platform=windows target=template_release arch=x86_64
```

The second command writes `addons/foveacore/gdextension/bin/foveacore_cpp.dll`. It does not modify the tracked Rust `foveacore.dll`, and the generated C++ DLL/import-library files are ignored by Git.

Unsupported configurations fail before compilation:

```text
Unsupported C++ target: only windows/template_release/x86_64 is currently validated.
```

## Run the Godot smoke gate

Use the declared Godot 4.7.dev5 console executable or an equivalent 4.7 build:

```bash
godot --headless --path . \
  --script res://addons/foveacore/gdextension/test_cpp_extension_load.gd
```

Expected marker and exit code:

```text
CPP_EXTENSION_SMOKE: PASS | class_registered=true instance_created=true
process exit code: 0
```

The harness loads the `.gdextension.example` file explicitly through `GDExtensionManager`; the example suffix prevents Godot from activating this experimental runtime during normal project startup.

## Verify the fail-closed path

```bash
godot --headless --path . \
  --script res://addons/foveacore/gdextension/test_cpp_extension_load.gd \
  -- --force-missing-binary
```

Expected result:

```text
Missing C++ extension binary: ...foveacore_cpp.dll.missing
process exit code: 1
```

## Contract map

| File | Ownership |
| --- | --- |
| [`../foveacore.gdextension`](../foveacore.gdextension) | Canonical Rust descriptor |
| [`SConstruct`](SConstruct) | Produces only `foveacore_cpp.dll` |
| [`src/register_types.cpp`](src/register_types.cpp) | Exports only `foveacore_cpp_init` |
| [`foveacore_cpp.gdextension.example`](foveacore_cpp.gdextension.example) | Opt-in C++ descriptor template |
| [`test_cpp_extension_load.gd`](test_cpp_extension_load.gd) | Runtime registration and instantiation gate |
| [`../test/test_native_extension_ownership_contract.gd`](../test/test_native_extension_ownership_contract.gd) | Non-GPU collision regression guard |

## Remaining promotion gates

Before packaging C++ as a supported alternative runtime, require:

1. a successful run of the updated GitHub C++ job;
2. debug-target and additional-platform builds with matching descriptors;
3. representative renderer output and image-quality gates;
4. performance and shutdown-resource measurements;
5. explicit release packaging and installation tests.

The current result resolves artifact ownership and proves one local Windows load. It does not establish feature parity with Rust, cross-platform support, production rendering fidelity, or performance.
