# FoveaEngine Validation Matrix

## Automated surfaces

| Surface | Command or entry point | Evidence requirement |
| --- | --- | --- |
| Local validation tools | `python addons/tools/test_validation_tools.py` | Exit 0 and test count/output |
| `.fovea` structural validation | `res://addons/foveacore/test/test_fovea_format_validation.gd` | Canonical header loads; malformed header, version, payload, section, and saver inputs are rejected |
| GDScript parse | `gdparse` over project scripts | No parse failures |
| Godot compile | `godot --headless --path . -s res://addons/foveacore/test/test_compile_all_scripts.gd` | Exit 0, no script errors |
| Non-GPU suites | `godot --headless --path . -s res://addons/foveacore/test/run_all_tests.gd -- --group=nogpu` | All executed suites pass |
| GPU suites | same runner with `-- --group=gpu` | Real GPU, renderer and driver recorded |
| Startup smoke | `addons/foveacore/test/smoke_startup.gd` | No crash/error across supported rendering methods |
| C# | `dotnet build FoveaEngine.csproj --configuration Release` | Exit 0; a separate test project is required before claiming C# unit-test coverage |
| Rust | `cargo test` and `cargo clippy -- -D warnings` | Exit 0 for workspace crates |
| C++ GDExtension | SCons Windows release build plus `test_cpp_extension_load.gd` | Distinct binary created, exported symbol inspected, `FoveaRenderer` registered and instantiated |
| Visual | `capture_render.gd` against a committed golden | Threshold and renderer recorded |

## Runtime evidence record — 2026-08-08

Environment: Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti, Windows desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| `demo_bonsai.ply` auto-framed capture | 12,473 splats loaded; PNG written; no script, parse, or load errors | VALIDATED |
| Default visual fixture capture | 8,000 splats loaded; PNG written; no script, parse, or load errors | VALIDATED |
| GPU sort permutation gate | GPU result was incomplete; exact CPU fallback retained the source splat count | EXPERIMENTAL |
| `demo_bonsai.fovea` historical auto-framed capture | Zero splats loaded; capture gate failed before the 2026-08-11 fallback | FAILED (HISTORICAL) |
| Transparency blend scene | Historical 627-error baseline is superseded by a clean numeric framebuffer oracle; production splat-layout parity remains open | EXPERIMENTAL |
| C++ GDExtension runtime contract | Rust and C++ now have distinct symbols, binaries, and descriptors; local Windows build/load passes | EXPERIMENTAL |

The PLY images are compatibility evidence, not FPS, VR, or image-quality benchmarks. The transparency harness now captures pixels, applies a bounded alpha gate, and exits non-zero on failure; it still does not validate the five layouts through the production splat shader.

## Quick-win format contract record — 2026-08-11

Environment: Godot 4.7.dev5 Mono, headless desktop fallback, Windows.

| Check | Result | Evidence state |
| --- | --- | --- |
| `.splat` deterministic round-trip | 256 records loaded; position, color, opacity, scale, rotation, and AABB assertions passed | VALIDATED |
| `.splat` negative inputs | Corrupt size, missing file, and unsupported extension returned empty without a crash | VALIDATED |
| Public `.spz` contract | `is_supported("a.spz")` is false; the public node and editor picker no longer advertise the planned decoder | VALIDATED |

The focused script completed with 14 passed assertions and zero failed assertions. Its three `ERROR:` lines are the deliberately exercised corrupt, missing, and unsupported inputs; the isolated log contains no `SCRIPT ERROR` or parse error.

## Native runtime triage record — 2026-08-11

Environment: Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti, Windows desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| Live `.fovea` path assignment | Instanced renderer created after `FoveaSplat3D` was already ready, retained the assigned path, and was released after node removal; 4/4 assertions passed | VALIDATED |
| PLY capture control | 12,473 ready splats, foreground pixels detected, PNG written, zero `ERROR:`, zero `SCRIPT ERROR`, and zero parse errors | VALIDATED |
| Local `.fovea` load | 12,473 splats reached the MultiMesh, proving the header/payload path progressed beyond zero | IMPLEMENTED_UNVALIDATED |
| Local `.fovea` visual gate | Frame remained background-only and the log contained compute texture, uniform, push-constant, submission, and RID errors | FAILED |
| Instanced `.fovea` visual gate | Renderer registration succeeded, but the instanced compute path still produced zero ready splats and binding/push-constant errors | FAILED |
| Capture false-positive protection | Zero ready splats or a background-only image now exits non-zero; the failing `.fovea` run wrote no PNG | VALIDATED |

This historical triage did not upgrade native rendering: a populated MultiMesh was transport evidence, while the then-untouched visual gate remained the rendering oracle. The later record below supersedes the blank-frame result without claiming visual fidelity.

## Format conformance gaps

**P1 / remaining scope:** the following evidence now exists:

1. GDScript writer → GDScript loader: covered by the structural test.
2. Rust writer → GDScript loader: covered by `rust_v2_fixture.fovea` and the structural test.
3. GDScript writer → Rust loader: covered by the Rust golden-fixture test.
4. Corrupt magic, unsupported version, truncated header, oversized count, invalid offsets, and malformed saver input: covered by the structural test.

The GDScript writer test now asserts every field: quantized position, signed
normal, palette/covariance indices, opacity, layer, dither seed, and brush
type. Rust and the Rust fixture use `GaussianSplat.BrushType.GAUSSIAN = 2`.
Remaining P1 scope: observe these semantic assertions on the Godot 4.7+ CI
baseline.

## VR and performance

Automated headless success does not validate VR. A headset run must record:

- headset and runtime;
- GPU/CPU, driver, renderer, and resolution;
- refresh target and achieved average/P95/P99 frame time;
- asset count, splat count, and compression format;
- peak RAM and VRAM;
- eye-tracking or fallback mode;
- thermal and throttling observations.

## Documentation-only gate

For changes confined to `docs/autowiki/` and documentation links:

- validate internal Markdown links;
- run `python addons/tools/test_validation_tools.py`;
- run the repository-local checkup and distinguish new failures from pre-existing drift;
- confirm Git diff contains no runtime changes.

## Execution record — 2026-07-16

Environment: Windows workspace, documentation-only change.

| Check | Result | Evidence state |
| --- | --- | --- |
| Internal Markdown link scan | 13 files checked; all referenced local targets exist | VALIDATED |
| `python addons/tools/test_validation_tools.py` | Exit 0; UTF-8 and cp1252 console support passed | VALIDATED |
| Repository-local checkup | Exit 0; directives 90/100, infrastructure 72/100, 0 duplicate Python function groups | VALIDATED |
| Godot, GPU, XR, native builds | Not run because no runtime file changed | SKIPPED |

The checkup reported pre-existing directive drift: `CLAUDE.md` is estimated at approximately 2,534 tokens, above the 2,000-token policy target. This initial Wiki task did not modify that unrelated instruction file.

## `.fovea` v2 hardening record — 2026-07-16

Environment: Windows workspace; Godot CLI and `gdparse` are not installed on `PATH`.

| Check | Result | Evidence state |
| --- | --- | --- |
| Rust unit tests | `cargo test`: 5 tests passed, including the GDScript golden fixture and Rust fixture generator | VALIDATED |
| Rust lint | `cargo clippy -- -D warnings`: exit 0 | VALIDATED |
| Python validation utilities | Exit 0; UTF-8 and cp1252 console support passed | VALIDATED |
| Repository-local checkup | Exit 0; directives 90/100, infrastructure 72/100, 2 pre-existing duplicate Python function groups | VALIDATED |
| GDScript structural test | Godot 4.5 headless: 15 assertions passed, including canonical/corrupt input and the Rust-generated fixture. Repeat on the Godot 4.7+ project baseline before release. | VALIDATED_WITH_VERSION_GAP |
| Godot parse/compile, GPU, XR | Not run; required executables are absent | BLOCKED_ENVIRONMENT |

The checkup also reports pre-existing oversized `CLAUDE.md`, 21 suspicious-code patterns, and two low-confidence security findings outside this change. The runtime change introduces canonical v2 layout checks in both GDScript and Rust. The versioned GDScript golden fixture, including its 96-byte metadata section, is now accepted by the Rust reader. A deterministic Rust v2 fixture generator is available; consuming its output in Godot remains a P1 environment-blocked acceptance step.

## Cross-language fixture record — 2026-08-08

| Check | Result | Evidence state |
| --- | --- | --- |
| Rust fixture generation | Versioned `test/fixtures/rust_v2_fixture.fovea`, 208 bytes, canonical v2 header and metadata | VALIDATED |
| Godot structural test | Godot 4.7-dev5 Mono headless: 28 assertions passed, including every packed record field and Rust fixture loading | VALIDATED |
| CI reachability | `run_all_tests.gd --group=nogpu` discovers every `test_*.gd` without `REQUIRES_GPU`; the structural test is included automatically | IMPLEMENTED_UNVALIDATED |

The structural format contract has now been observed on the declared Godot 4.7-dev5 baseline. This does not validate GPU execution, XR, or native visual output.

## Packed-record semantics record — 2026-08-08

| Check | Result | Evidence state |
| --- | --- | --- |
| GDScript writer semantics | Godot 4.7-dev5 Mono headless: all 16-byte packed record fields asserted | VALIDATED |
| Rust brush mapping | Rust converter and fixture encode Gaussian brush type as `2`, matching `GaussianSplat.BrushType` | VALIDATED |

The prior Rust mapping of `0` to Gaussian conflicted with the canonical
GDScript enum, where `0` is Stone. It is corrected in both the Rust converter
and the versioned Rust fixture.

## Instanced layout source contract — 2026-08-11

| Check | Result | Evidence state |
| --- | --- | --- |
| Non-GPU layout suite | Godot 4.7-dev5 Mono headless: 29 assertions passed for layout constants, CPU passthrough, and culler/publisher source contracts | VALIDATED |
| CI reachability | The suite has no `REQUIRES_GPU` marker and is included by the CI `nogpu` runner; remote execution is blocked before job start by GitHub billing | IMPLEMENTED_UNVALIDATED |
| GPU readback | Two-instance `{0,1}` metadata assertion is present but skipped without a local RenderingDevice | BLOCKED_ENVIRONMENT |

The source contract prevents CPU/GDScript or GLSL layout drift in no-GPU CI. It
does not establish compute execution or published-texture parity; the local
headless 4.7-dev5 runtime has no RenderingDevice.

## Non-GPU runner isolation — 2026-08-13

`test_multiplayer_enet_integration.gd` launches separate ENet server/client
processes and has a 30-second network deadline. It is marked
`REQUIRES_INTEGRATION`, so `run_all_tests.gd --group=nogpu` skips it instead of
allowing a network-dependent process test to stall deterministic CI coverage.

`test_auto_roi.gd` also carries `REQUIRES_INTEGRATION`: it launches a
user-configured Python interpreter and its result depends on optional
`rembg`, OpenCV, or Pillow packages. The synthetic input makes it a useful
local integration gate, but not a reproducible non-GPU CI unit suite.

`test_live_link_receiver.gd` is likewise an integration suite: it binds UDP
port 5006 and sends a loopback mocap packet through a live receiver. Keeping
it out of `nogpu` prevents port contention with an editor or external Live
Link sender from producing a nondeterministic CI result.

`test_indirect_draw.gd` and `test_splat_animate_pass.gd` carry
`REQUIRES_GPU`. Their former headless bypasses only proved that a missing
`RenderingDevice` was handled; they did not validate compute pipelines or GPU
dispatch. They now execute only in the explicit GPU group.

`test_shader_compilation.gd` is also GPU-only. It now requires a local
`RenderingDevice`, imports every GLSL resource as `RDShaderFile`, and rejects
any SPIR-V stage compilation error; merely counting source files is no longer
reported as shader validation.

`test_splat_animate_pass.gd` validates the instantiated `delta_animation`
compute pipeline. The separate `splat_animate` and advanced shader resources
are not initialized or dispatched by `GPUCullerPipeline` yet, so they remain
an explicit implementation gap rather than claimed GPU coverage.

The gap is currently intentional: `splat_animate.glsl` interprets `data0` as
two half-floats, but canonical `.fovea` v2 stores quantized position components
there. It must be redesigned around the canonical AABB quantization contract
before it can enter the culling path; enabling it now would corrupt positions.

`test_benchmark.gd` is a timer smoke test only: it neither loads nor renders
splats, so its samples are not reported as FoveaEngine performance evidence.
Representative FPS claims remain assigned to the windowed `fps_benchmark.gd`
workflow on documented hardware.

`rasterizer_performance_benchmark.gd` is GPU-only and fail-closed: all nine
dispatch cases must complete before it writes a `user://` report. Dummy
output buffers use the canonical PackedSplat stride of 16 bytes per splat
(tile_rasterizer.glsl data0..data3 and GPUCullerPipeline.SPLAT_BYTE_SIZE).
Its MultiMesh column is an estimate, while only the synchronized tile dispatch
time is measured; it cannot support a measured renderer-speedup claim.

`test_memory_leak.gd` is a lifecycle smoke gate, not a leak certification: it
now loads and releases the one-splat Rust v2 fixture 100 times. Native and
VRAM leak claims remain out of scope until a runner supplies explicit resource
instrumentation.

Godot 4.7-dev5 compiled the complete script surface after this classification:
242 passed, 0 failed.

## Godot 4.7 baseline promotion — 2026-08-11

Environment: Windows workspace, CI-pinned Godot 4.7-dev5 Mono, headless with
OpenXR disabled for the targeted contracts. Expected invalid-input errors and
headless GPU/OpenXR fallback warnings were retained in the logs.

| Check | Result | Evidence state |
| --- | --- | --- |
| `.fovea` structural suite | 28 passed, 0 failed; canonical writer, every 16-byte packed field, corrupt inputs, and the Rust fixture | VALIDATED |
| Local CLI contract | 23 passed, 0 failed; bounded status, validation, unsaved add, path confinement, and one-splat load | VALIDATED |
| Instanced output layout | 29 passed, 0 failed; canonical 16-byte record, separate 24-byte runtime metadata, CPU passthrough, and fail-closed malformed-input contract | VALIDATED |
| Delta serialization | Direct delta suite exited 0; wrapped morph test reported all mathematical, FP16, and serialization checks passed | VALIDATED |
| Rust implementation | `cargo test --all-targets`: 5 passed; Clippy with warnings denied: no issues | VALIDATED |
| Rust fixture reproducibility | Generator output and versioned fixture were both 208 bytes with SHA-256 `F34C116064852AFE6509CEB1653EA10E8D9ACF20647AA243F150A60B52CA9B6D` | VALIDATED |

The earlier Godot 4.5 records above remain as historical evidence. This run
closes their baseline-version gap for structural format and source-layout
claims. Native `.fovea` visual fidelity and real GPU readback remained separate
failed gates at that point; the 2026-08-13 fidelity record below supersedes the
gross color/scale failure, while compute readback remains failed.

## Native `.fovea` desktop fallback — 2026-08-11

Environment: Windows desktop, Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti.

| Check | Result | Evidence state |
| --- | --- | --- |
| Canonical payload boundary | Header count limited the payload to exactly 12,473 × 16-byte records; trailing metadata was excluded | VALIDATED |
| Runtime record fallback | 29/29 assertions passed for canonical preservation, `local_idx`, `instance_id`, and malformed-input rejection | VALIDATED |
| D3D12 foreground gate | 12,473 records entered the fallback, cleaning retained 11,808 splats, foreground pixels were detected, and an 800×600 PNG was written | VALIDATED |
| Representative visual fidelity | The capture is non-blank but visibly blue, oversized, and does not reproduce the PLY bonsai appearance | FAILED |
| Instanced compute culling | The opt-in compute path still reports a zero atomic output count on the same D3D12 system | FAILED |
| Shutdown resource hygiene | The successful capture log contains no `ERROR:`, `SCRIPT ERROR`, parse error, or invalid RID, but reports six pre-existing RenderingDevice leak warnings outside the instanced fallback | EXPERIMENTAL |

The default native path now proves asset-to-viewport continuity, not image parity, performance, VR readiness, or compute acceleration. Compute culling stays disabled by default until its counter/readback contract passes.

## Native `.fovea` section fidelity — 2026-08-13

Environment: Windows desktop, Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti.

| Check | Result | Evidence state |
| --- | --- | --- |
| Native section contract | 51/51 assertions passed for canonical payload preservation, palette fallback, real AABB, 32-byte covariance stride, linear-scale handling, Godot 4.7 shader compatibility, malformed-input rejection, and GPU cleanup ownership/order | VALIDATED |
| D3D12 native capture | 12,473 records loaded, cleaning retained 11,808 splats, and a framed green/brown 800×600 bonsai image was written without shader, script, parse, or load errors | VALIDATED |
| PLY regression control | The canonical 12,473-splat PLY fixture still loaded and produced a framed green/brown 800×600 capture after the shared shader change | VALIDATED |
| Representative image parity | The native result is recognizable and no longer blue or oversized, but it remains visibly stylized and has no quantitative reference-image threshold | EXPERIMENTAL |
| Instanced compute culling | The last opt-in D3D12 counter/readback gate still returned zero output and was not promoted by this CPU-path result | FAILED |
| Shutdown resource hygiene | Both successful capture logs retained six RenderingDevice RID leak warnings outside the instanced CPU fallback; the 2026-08-15 record below supersedes this result | EXPERIMENTAL |

Root cause: Rust fast-path methods received `res://` paths that `std::fs::File`
could not open, so the renderer lost the canonical palette, AABB, and covariance
sections. The fallback now loads the Godot resource, reads the 1×N palette with
nearest filtering, consumes 32-byte covariance entries, and avoids exponentiating
scales that are already linear. This closes the blank/blue/oversized quick win;
it does not certify visual parity, GPU compute acceleration, VR, or cleanup.

## Local RenderingDevice shutdown hygiene — 2026-08-15

Environment: Windows desktop, Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti.

| Check | Result | Evidence state |
| --- | --- | --- |
| Baseline | The 2026-08-13 `.fovea` capture completed with zero errors but six RID leak warnings across the renderer and compositor GPU pipelines | VALIDATED |
| Cleanup ownership contract | 51/51 assertions passed; cache cleanup owns `dynamic_output`, releases uniform sets before bound resources, and submits before the shutdown synchronization | VALIDATED |
| Native `.fovea` shutdown | 11,808 ready splats and an 800×600 PNG; zero `ERROR:`, script/shader/parse errors, invalid IDs, or RID leak warnings | VALIDATED |
| PLY regression shutdown | 12,473 ready splats and an 800×600 PNG; zero `ERROR:`, script/shader/parse errors, invalid IDs, or RID leak warnings | VALIDATED |

The fix centralizes cache destruction, releases dependent uniform sets before
textures and buffers, includes the previously omitted dynamic output buffer,
and uses `submit → sync` only at local-device shutdown. This closes the scoped
RID hygiene failure; it does not change the separate image-parity, representative
compute-acceleration, XR, or cross-device performance gates.

## Isolated public-index validation — 2026-08-13

The prepared Git index was exported into a disposable directory, with the
native manifest moved out of Godot's scan path and editor plugins disabled as
in CI. Godot 4.7-dev5 registered 197 global classes and the exhaustive script
loader exited successfully.

The non-GPU runner initially revealed that CI's legacy argument placement was
silently selecting `group=all`. The runner now accepts both Godot argument
forms and CI uses the canonical `-- --group=...` separator.

| Check | Result | Evidence state |
| --- | --- | --- |
| Non-GPU routing | `group=nogpu`; 57 suites passed, 0 failed, 6 GPU/integration suites explicitly skipped | VALIDATED |
| Public documentation snapshot | 86 Markdown files, 122 local links, and all 9 required release files passed from the isolated index | VALIDATED |
| First clean import | Exit 0; initial UID-cache/editor bootstrap emitted transient editor errors | EXPERIMENTAL |
| Second import | Exit 0 with no `ERROR:`, script error, parse error, or unknown UID in the filtered log | VALIDATED |

This validates the prepared GDScript-only snapshot and test-group boundary. It
does not replace native packaging, representative GPU, XR, or real-service
acceptance gates.

## Isolated C# and Rust validation — 2026-08-13

The prepared index was exported again into a disposable directory so newer
unstaged worktree changes could not affect the result.

| Check | Result | Evidence state |
| --- | --- | --- |
| C# Release build | One `net9.0` project built with 0 errors and 7 Godot API deprecation warnings | VALIDATED |
| C# test discovery | `FoveaEngine.csproj` declares no test SDK/framework and `dotnet test` only completes the MSBuild target without discovering tests | UNAVAILABLE |
| Rust workspace tests | 5 tests passed across 3 suites | VALIDATED |
| Rust Clippy | Workspace/all-targets run with warnings denied; no issues | VALIDATED |
| Rust Release build | 32 crates compiled in the optimized profile | VALIDATED |

CI still treats the Godot C# assembly as a compile gate. A separate
`tests/FoveaEngine.Tests` project now owns `dotnet test` coverage for the
Godot-free Morton encoder; the Godot project excludes that test tree so the
editor assembly does not pull xUnit.

## Prepared-index GPU, visual, and Python validation — 2026-08-13

Environment: isolated export of the prepared Git index, Godot 4.7-dev5 Mono,
Forward+, D3D12, and NVIDIA RTX 5060 Ti. The checks below ran outside the dirty
worktree so unstaged files could not influence their result.

| Check | Result | Evidence state |
| --- | --- | --- |
| Tile rasterizer dispatch | 10 passed, 0 failed; the compute pipeline submitted and changed an initialized transparent 64×64 RGBA target to an opaque background | VALIDATED |
| Instanced GPU layout/readback | 32 passed, 0 failed, 0 skipped; two records retained canonical metadata, separate local indices, and instance IDs `{0,1}` | VALIDATED |
| PLY visual capture | The auto-framed 12,473-splat bonsai produced a recognizable 800×600 PNG with foreground signal and no script error | VALIDATED |
| GPU depth sort guard | The padded GPU result was incomplete, was rejected, and the capture used an exact 12,473-splat CPU ordering; HLOD inputs remained 12,473 with levels 444/30/8 | EXPERIMENTAL |
| Python repository syntax | `compileall` passed over `addons`, `tools`, and `test` | VALIDATED |
| Offset-field baker | Four Python tests passed; a generated two-cell-axis resource loaded in Godot with exact bounds, eight vectors, and x-fastest ordering | VALIDATED |
| Public documentation | 86 Markdown files, 122 prepared-index local links, and all 9 required files passed after this record was added | VALIDATED |

These results close the synthetic instanced counter/readback failure recorded
above and establish a real tile dispatch. They do not certify tile equivalence
or speedup, representative native `.fovea` GPU acceleration, GPU depth-sort
correctness, XR behavior, or cross-hardware portability.

## Transparency framebuffer quick win — 2026-08-15

Environment: Windows desktop, Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti.

| Check | Result | Evidence state |
| --- | --- | --- |
| Reproduced baseline | 627 `ERROR:` entries, 208 failed driver initializations, and one script error; repeated `FoveaCoreSplatRenderer` fixtures exhausted local rendering-device creation | FAILED (HISTORICAL) |
| Bounded scene load | VR-rig and invalid-light dependencies removed; five deterministic layouts used shared shader material and batched MultiMesh arrays | VALIDATED |
| Numeric framebuffer oracle | One 50% red layer measured 0.498 versus 0.500 expected; two layers measured 0.749 versus 0.750 expected; all gates passed within ±0.080 | VALIDATED |
| Positive process contract | Exit `0`, PNG written, zero `ERROR:`, script errors, parse errors, failed driver initializations, or RID leak warnings | VALIDATED |
| Negative process contract | `--force-oracle-failure` printed `TRANSPARENCY_ORACLE: FAIL` and exited `1` | VALIDATED |
| Five splat-like layouts | Construction is deterministic and reported as `constructed`; no layout pixel is compared with production packed-data output | EXPERIMENTAL |

The quick win validates alpha composition and fail-closed process behavior on
the recorded D3D12 system. It deliberately uses a bounded test shader and does
not certify production Gaussian transparency, depth ordering, palette fidelity,
golden-image parity, performance, XR, or portability.

## Native artifact ownership quick win — 2026-08-15

Environment: Windows, Godot 4.7.dev5 Mono headless, SCons 4.10.1, MSVC 14.50.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical ownership contract | C++ exported `foveacore_init` into the same `foveacore.dll` path owned by the active Rust `gdext_rust_init` descriptor | CONFLICT (HISTORICAL) |
| Artifact ownership guard | 14/14 assertions passed for distinct descriptors, entry symbols, output paths, supported target, and CI upload path | VALIDATED |
| Non-GPU runner reachability | `group=nogpu` executed 52 suites, including the new ownership guard; 52 passed, 0 failed, 12 GPU/integration suites skipped | VALIDATED |
| C++ Windows release build | `windows/template_release/x86_64` produced `foveacore_cpp.dll`; the tracked Rust DLL remained unchanged | VALIDATED |
| Unsupported build control | `template_debug` failed before compilation with exit `1` and the declared supported-target message | VALIDATED |
| PE export identity | `dumpbin` found `foveacore_cpp_init` in C++ and `gdext_rust_init` in Rust | VALIDATED |
| Godot C++ load smoke | Explicit descriptor load registered and instantiated `FoveaRenderer`; `CPP_EXTENSION_SMOKE: PASS`, exit `0` | VALIDATED |
| Missing-binary control | `--force-missing-binary` rejected the absent path and exited `1` | VALIDATED |
| Remote and portable adoption | Updated GitHub job, debug builds, non-Windows targets, representative rendering, and packaging are not reproduced here | EXPERIMENTAL |

The entry-symbol/output-name conflict is resolved without changing the canonical
Rust descriptor. This proves a bounded local C++ load, not Rust/C++ feature
parity, representative image output, cross-platform support, or release readiness.

## Developer API reference conflict quick win — 2026-08-15

Environment: Windows, Godot 4.7.dev5 Mono headless, repository worktree.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical reference state | Manager and reconstruction names, signals, and methods disagreed with the active GDScript sources | CONFLICT (HISTORICAL) |
| Source-extracted API guard | 35/35 assertions passed for stable-node, autoload/class ownership, public methods/signals, session migration, and obsolete-signature rejection | VALIDATED |
| Non-GPU runner reachability | `group=nogpu` executed 51 suites, including the new reference guard; 51 passed, 0 failed, 14 GPU/integration suites skipped | VALIDATED |
| Public documentation | 86 Markdown files, 184 local links, and all 9 required release files passed | VALIDATED |
| Validation utilities | UTF-8 and cp1252 console support passed | VALIDATED |
| Repository-local checkup | Exit `0`; directives 85/100, infrastructure 72/100, and 0 duplicate Python function groups | VALIDATED_WITH_DRIFT |

The conflict is closed for the guarded stable-node, autoload-facade, and
reconstruction sources. The check is source-level documentation evidence: it
does not install or execute reconstruction dependencies, validate GPU/XR, or
replace the broader P3 generated-reference goal. Headless execution retained
expected OpenXR/GPU fallback warnings and an unrelated resource-at-exit
diagnostic in another suite. The checkup also retained pre-existing oversized
directive drift (`CLAUDE.md` approximately 2,534 tokens).

## FoveaCoreManager facade quick win — 2026-08-15

Environment: Windows, Godot 4.7.dev5 Mono headless desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical subsystem status | Manager and decoupled subsystems were implemented but had no explicit facade-level acceptance record | IMPLEMENTED_UNVALIDATED (HISTORICAL) |
| Facade orchestration and controls | 30/30 assertions passed for subsystem ownership/injection, parameter clamping, animation/foveation/hybrid controls, desktop fallback, and detached-refresh rejection | VALIDATED |
| Dynamic native lifecycle | 4/4 assertions passed for autoload discovery, live `.fovea` renderer creation/path retention, and unused-renderer cleanup | VALIDATED |
| Non-GPU runner reachability | `group=nogpu` discovered 66 suites; 51 non-GPU suites passed, 0 failed, and 15 GPU/integration suites were skipped | VALIDATED |
| Public documentation | 86 Markdown files, 184 local links, and all 9 required release files passed | VALIDATED |
| Validation utilities | UTF-8 and cp1252 console support passed | VALIDATED |
| Repository-local checkup | Exit `0`; directives 85/100, infrastructure 72/100, and 0 duplicate Python function groups | VALIDATED_WITH_DRIFT |

This promotes only the headless manager facade and lifecycle contract. The run
used the explicit CPU fallback and retained expected missing-RenderingDevice and
OpenXR-unavailable warnings. It does not validate compute execution, headset
tracking, foveated image quality, performance, or cross-platform portability.
The checkup retained the pre-existing oversized-directive findings.

## Public node / advanced delegate quick win — 2026-08-15

Environment: Windows, Godot 4.7.dev5 Mono headless desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical delegate status | The advanced delegate existed and was used by captures, but its public-node propagation boundary had no focused acceptance record | IMPLEMENTED_UNVALIDATED (HISTORICAL) |
| Historical `AUTO` transition | Returning from an explicit preset was a no-op, conflicting with the documented global/default behavior and retaining cinematic local values | CONFLICT (HISTORICAL) |
| Public node / delegate contract | 26/26 assertions passed for runtime-only ownership, real PLY loading, source signal, properties, live controls, all quality presets, and duplicate-source suppression | VALIDATED |
| Local automation regression | The existing CLI bridge passed 23/23, including bounded input rejection, public-node creation, one-splat loading, status, and validation | VALIDATED |
| Non-GPU runner reachability | `group=nogpu` discovered 67 suites; 52 non-GPU suites passed, 0 failed, and 15 GPU/integration suites were skipped | VALIDATED |
| Public documentation | 86 Markdown files, 184 local links, and all 9 required release files passed | VALIDATED |
| Validation utilities | UTF-8 and cp1252 console support passed | VALIDATED |
| Repository-local checkup | Exit `0`; directives 95/100, infrastructure 72/100, 0 duplicate Python function groups, and no reported drift | VALIDATED |

`AUTO` now restores density `1.0` and culling priority `5`, leaving global
manager controls authoritative after a preset change. This closes the scoped
public/delegate lifecycle gap; it does not certify representative rendering,
collision geometry, export fidelity, GPU acceleration, XR, or performance.

## Rust fast-path format quick win — 2026-08-16

Environment: Windows, Rust locked workspace, Godot 4.7.dev5 Mono headless.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical fast-path status | The Rust path was implemented, but the FoveaCore surface table still classified the whole path as unreproduced | IMPLEMENTED_UNVALIDATED (HISTORICAL) |
| Locked Rust workspace tests | `cargo test --workspace --locked`: 5 passed across 4 suites | VALIDATED |
| Local release build | `cargo build --release --locked`: optimized `cdylib` target completed successfully | VALIDATED |
| Rust lint gate | `cargo clippy --workspace --all-targets --locked -- -D warnings`: no issues | VALIDATED |
| Fixture reproducibility | Generated and tracked files were both 208 bytes with SHA-256 `F34C116064852AFE6509CEB1653EA10E8D9ACF20647AA243F150A60B52CA9B6D` | VALIDATED |
| Rust to Godot compatibility | Godot loaded the generated fixture and completed the canonical/corrupt-input structural suite: 28 passed, 0 failed | VALIDATED |
| Non-GPU regression | `group=nogpu` discovered 67 suites; 52 passed, 0 failed, and 15 GPU/integration suites were skipped | VALIDATED |
| Repository-local checkup | Exit `0`; directives 100/100, infrastructure 72/100, one duplicate Python function group, and no reported drift | VALIDATED |

This promotes only the Rust format contract and local Windows buildability.
Native performance, representative renderer output, GPU acceleration, XR,
remote CI, packaging, and non-Windows artifacts remain separate gates.

## Core specification and fail-closed runner quick win — 2026-08-16

Environment: Windows, Godot 4.7.dev5 Mono headless desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical specification state | `FoveaSplat3D`, `FoveaCoreManager`, and the decoupled subsystems still carried stale `IMPLEMENTED_UNVALIDATED` labels despite their focused acceptance records | CONFLICT (HISTORICAL) |
| Specification drift guard | The source/reference contract now checks the three scoped evidence boundaries and rejects any remaining `IMPLEMENTED_UNVALIDATED` state in `spec.md`: 40 passed, 0 failed | VALIDATED |
| Historical lifecycle run | The 100-cycle fixture smoke called `free()` on a `RefCounted`, emitted a `SCRIPT ERROR`, and was incorrectly counted as a runner success | FAILED (HISTORICAL) |
| Asset lifecycle smoke | Automatic reference release completed 100/100 canonical one-splat fixture loads; 1 assertion passed, 0 failed, with no script error | VALIDATED |
| Runner semantic negative control | The isolated classifier accepted `[FAIL]`, `FAIL:`, `SCRIPT ERROR`, and `Parse Error` as failures and accepted clean output: 5 passed, 0 failed | VALIDATED |
| Non-GPU regression | The runner discovered 68 suites; 52 passed, 0 failed, and 16 GPU/integration suites were skipped | VALIDATED |
| Public documentation gate | 86 Markdown files, 184 local links, and 9 required files passed validation | VALIDATED |
| Validation-tool encoding regression | UTF-8 and cp1252 console handling passed | VALIDATED |
| Botte Secrète checkup | Directives 100/100, infrastructure 72/100, policy satisfied, and no drift detected | VALIDATED |

The specification promotions cover only the recorded headless lifecycle,
delegation, ownership, injection, control routing, desktop fallback, and cleanup
contracts. RenderingDevice execution, representative visual output, collision
geometry, export fidelity, XR, performance, remote CI, and portability remain
separate experimental or external gates.

## Video-asset GPU depth-sort quick win — 2026-08-16

Environment: Windows desktop, Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical GPU sorter | The padded bitonic shader returned incomplete permutations and the runtime correctly fell back to CPU | FAILED_CLOSED (HISTORICAL) |
| Bitonic pass synchronization | One compare-exchange pass is dispatched per `(sequence_length, compare_distance)` pair with a RenderingDevice compute barrier between passes | VALIDATED |
| Focused GPU permutation gate | 30/30 assertions passed at 3, 8, 256, 257, 1,024, and 17,013 splats; every result was unique, in range, complete, and strictly back-to-front | VALIDATED |
| Representative asset-sized timing | The 17,013-splat case padded to 32,768 and completed in 1 ms in the recorded focused Forward+ run | VALIDATED_ON_RECORDED_HARDWARE |
| Static-scene reuse | 7/7 assertions passed for reuse plus camera, transform, and per-frame-effect invalidation | VALIDATED |
| Integrated video-derived PLY capture | `FoveaSplat3D` loaded all 17,013 splats and wrote a 1,152×648 Forward+ capture reporting 60 settled FPS | VALIDATED_ON_RECORDED_HARDWARE |
| Runtime proof manifest | Hash/provenance verifier passed: 60 real views → 18,774 trained splats → 17,013 runtime splats → 6 captures | VALIDATED |
| Non-GPU regression | The complete `group=nogpu` runner exited `0`; expected unavailable-OpenXR warnings remained | VALIDATED |

This closes the scoped GPU depth-sort defect on the recorded D3D12 hardware and
keeps a fail-closed CPU fallback. It does not certify instanced compute culling,
the native `.fovea` visual path, other GPUs or rendering APIs, OpenXR, headset
performance, media redistribution rights, or production scan quality.

## Native CI surfaces and duplicate-function cleanup — 2026-08-18

Environment: Windows checkout `codex-release-prep-stabilization`, .NET 10/9,
Rust 1.97.0, Godot 4.7.dev5 Mono, local SCons 4.10.1.

| Check | Result | Evidence state |
| --- | --- | --- |
| Historical C# test discovery | `dotnet test FoveaEngine.csproj` completed MSBuild without discovering tests | UNAVAILABLE (HISTORICAL) |
| C# Release build | `dotnet build FoveaEngine.csproj --configuration Release --nologo`: 0 errors, 0 warnings | VALIDATED |
| C# unit tests | `dotnet test tests/FoveaEngine.Tests/FoveaEngine.Tests.csproj --configuration Release --nologo`: 3 passed, 0 failed | VALIDATED |
| Rust crate tests | `cargo test --all-targets` on `addons/foveacore/rust`: 5 passed | VALIDATED |
| Rust Clippy | `cargo clippy --all-targets -- -D warnings -A clippy::result_large_err` on both crates: no issues | VALIDATED |
| C++ GDExtension rebuild | `python -m SCons platform=windows target=template_release arch=x86_64`: already up to date | VALIDATED |
| C++ load smoke | Godot 4.7-dev5 loaded `FoveaRenderer` from `foveacore_cpp.dll` | VALIDATED |
| C++ missing-binary control | `--force-missing-binary` exited `1` before load | VALIDATED |
| Production Python duplicate groups | Scoped AST audit excluding `godot-cpp`/`scratch`/`test`/`tests`: 0 groups | VALIDATED |
| Always-on Claude guide | `CLAUDE.md` remains a 267-byte pointer to `AGENTS.md` | VALIDATED |

This closes the local compile/test honesty gap for C#, Rust, and the experimental
Windows C++ artifact. It does not certify remote GitHub Actions, native packaging,
or a clean publishable worktree.
