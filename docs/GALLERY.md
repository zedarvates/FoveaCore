# FoveaCore runtime gallery

Real Gaussian-splat captures from the local FoveaCore desktop runtime. These are reconstructed splat renders, not concept art.

This page does **not** claim OpenXR / VR proof, city-scale streaming, or production visual parity with every backend. Desktop Forward+ captures only.

## Horse statue - video to 3DGS to Godot

Synthetic turntable video of [Horse Statue 01](https://polyhaven.com/a/horse_statue_01) (Rico Cilliers, [Poly Haven](https://polyhaven.com), CC0) reconstructed with official gsplat (25,674 splats after sanitize) and loaded through FoveaSplat3D in Godot 4.7.dev5, Forward+, D3D12.

![Horse statue Gaussian splat orbiting in the Godot viewport](gallery/horse-runtime-orbit.jpg)

_Default demo capture at 61 FPS. Overlay text is from the local proof scene, not a benchmark claim._

<table>
<tr>
<td><img src="gallery/horse-runtime-front.jpg" alt="Horse statue splat, front" /></td>
<td><img src="gallery/horse-runtime-az000.jpg" alt="Horse statue splat, azimuth 0" /></td>
</tr>
<tr>
<td><img src="gallery/horse-runtime-az180.jpg" alt="Horse statue splat, azimuth 180" /></td>
<td><img src="gallery/horse-runtime-az270.jpg" alt="Horse statue splat, azimuth 270" /></td>
</tr>
</table>

_Four framed runtime viewpoints of the same PLY in the Godot viewport._

![Training versus reconstructed view of the horse statue](gallery/horse-training-compare.jpg)

_Official gsplat validation pair at step 6999 (PSNR 34.62, SSIM 0.986). Left: source view. Right: reconstructed splat._

## Bonsai fixture

![Bonsai Gaussian-splat fixture in Godot](gallery/bonsai-runtime.jpg)

_Checked-in demo_bonsai.ply loaded through FoveaSplat3D on desktop Forward+. This shows the current PLY runtime path, not a performance number._

## StudioTo3D editor

![StudioTo3D reconstruction dock inside the Godot editor](gallery/studio-to-3d-editor.jpg)

_In-editor reconstruction dock: dependency setup, region controls, stages, and render options. Interface still evolving._

## What is not shown

- No Furby or other rights-restricted captures.
- No OpenXR / eye-tracked captures.
- No claim that WorldMirror 2.0 produced these particular images; the horse proof used official gsplat on a synthetic CC0 turntable.
