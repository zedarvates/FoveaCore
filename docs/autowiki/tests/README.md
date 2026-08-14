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
| C++ GDExtension | SCons Windows release build | Expected binary created; compilation artifact only, not current descriptor-load proof |
| Visual | `capture_render.gd` against a committed golden | Threshold and renderer recorded |

## Runtime evidence record — 2026-08-08

Environment: Godot 4.7.dev5 Mono, Forward+, D3D12, NVIDIA RTX 5060 Ti, Windows desktop fallback.

| Check | Result | Evidence state |
| --- | --- | --- |
| `demo_bonsai.ply` auto-framed capture | 12,473 splats loaded; PNG written; no script, parse, or load errors | VALIDATED |
| Default visual fixture capture | 8,000 splats loaded; PNG written; no script, parse, or load errors | VALIDATED |
| GPU sort permutation gate | GPU result was incomplete; exact CPU fallback retained the source splat count | EXPERIMENTAL |
| `demo_bonsai.fovea` historical auto-framed capture | Zero splats loaded; capture gate failed before the 2026-08-11 fallback | FAILED (HISTORICAL) |
| Transparency blend scene | Textual five-scenario summary reached, but 629 `ERROR` lines and one `SCRIPT ERROR` were recorded | FAILED |
| C++ GDExtension runtime contract | `foveacore_init` and `gdext_rust_init` disagree at the same DLL path | CONFLICT |

The PLY images are compatibility evidence, not FPS, VR, or image-quality benchmarks. The transparency harness cannot become a passing test until it captures pixels, applies declared gates, and exits non-zero on failure.

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
| Native section contract | 47/47 assertions passed for canonical payload preservation, palette fallback, real AABB, 32-byte covariance stride, linear-scale handling, Godot 4.7 shader compatibility, and malformed-input rejection | VALIDATED |
| D3D12 native capture | 12,473 records loaded, cleaning retained 11,808 splats, and a framed green/brown 800×600 bonsai image was written without shader, script, parse, or load errors | VALIDATED |
| PLY regression control | The canonical 12,473-splat PLY fixture still loaded and produced a framed green/brown 800×600 capture after the shared shader change | VALIDATED |
| Representative image parity | The native result is recognizable and no longer blue or oversized, but it remains visibly stylized and has no quantitative reference-image threshold | EXPERIMENTAL |
| Instanced compute culling | The last opt-in D3D12 counter/readback gate still returned zero output and was not promoted by this CPU-path result | FAILED |
| Shutdown resource hygiene | Both successful capture logs retain the known RenderingDevice RID leak warnings outside the instanced CPU fallback | EXPERIMENTAL |

Root cause: Rust fast-path methods received `res://` paths that `std::fs::File`
could not open, so the renderer lost the canonical palette, AABB, and covariance
sections. The fallback now loads the Godot resource, reads the 1×N palette with
nearest filtering, consumes 32-byte covariance entries, and avoids exponentiating
scales that are already linear. This closes the blank/blue/oversized quick win;
it does not certify visual parity, GPU compute acceleration, VR, or cleanup.

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

CI therefore keeps the C# build as a hard gate but no longer labels the empty
`dotnet test` target as a test run. Adding a separate C# test project remains a
release-quality improvement; current functional coverage is primarily GDScript
and Rust.

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
