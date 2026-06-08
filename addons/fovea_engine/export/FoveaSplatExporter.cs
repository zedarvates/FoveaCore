using Godot;
using System;
using System.IO;
using System.Text;

namespace FoveaEngine
{
    public static class FoveaSplatExporter
    {
        public static bool ExportToFile(FoveaSplatResource resource, string path, float decimationRatio = 1.0f)
        {
            if (resource == null || resource.SplatCount == 0)
            {
                GD.PushError("FoveaSplatExporter: Cannot export an empty resource.");
                return false;
            }

            string globalPath = ProjectSettings.GlobalizePath(path);
            string ext = Path.GetExtension(path).ToLower();

            // Handle optional decimation for VR optimization
            if (decimationRatio < 0.99f && decimationRatio > 0.0f)
            {
                // Create a copy of the resource to avoid modifying the active scene node resource
                var tempResource = new FoveaSplatResource
                {
                    Positions = (Vector3[])resource.Positions.Clone(),
                    RotationsFlat = (float[])resource.RotationsFlat.Clone(),
                    Scales = (Vector3[])resource.Scales.Clone(),
                    Colors = (Color[])resource.Colors.Clone(),
                    Opacities = (float[])resource.Opacities.Clone(),
                    Normals = (Vector3[])resource.Normals.Clone(),
                    BBox = resource.BBox
                };
                FoveaSplatConverter.Decimate(tempResource, decimationRatio);
                resource = tempResource;
            }

            try
            {
                if (ext == ".ply")
                {
                    return ExportToPly(resource, globalPath);
                }
                else if (ext == ".splat" || ext == ".gsplat")
                {
                    return ExportToSplat(resource, globalPath);
                }
                else
                {
                    GD.PushError($"FoveaSplatExporter: Unsupported export format '{ext}'");
                    return false;
                }
            }
            catch (Exception ex)
            {
                GD.PushError($"FoveaSplatExporter: Error exporting to '{path}': {ex.Message}");
                return false;
            }
        }

        private static bool ExportToPly(FoveaSplatResource resource, string globalPath)
        {
            int count = resource.SplatCount;
            var pos = resource.Positions;
            var rot = resource.Rotations;
            var scl = resource.Scales;
            var col = resource.Colors;
            var op = resource.Opacities;

            using (var fs = new FileStream(globalPath, FileMode.Create, System.IO.FileAccess.Write))
            using (var bw = new BinaryWriter(fs))
            {
                // Write Header
                WriteStringLine(bw, "ply");
                WriteStringLine(bw, "format binary_little_endian 1.0");
                WriteStringLine(bw, $"element vertex {count}");
                WriteStringLine(bw, "property float x");
                WriteStringLine(bw, "property float y");
                WriteStringLine(bw, "property float z");
                WriteStringLine(bw, "property float opacity");
                WriteStringLine(bw, "property float scale_0");
                WriteStringLine(bw, "property float scale_1");
                WriteStringLine(bw, "property float scale_2");
                WriteStringLine(bw, "property float rot_0"); // rot_0 corresponds to w in 3DGS
                WriteStringLine(bw, "property float rot_1"); // x
                WriteStringLine(bw, "property float rot_2"); // y
                WriteStringLine(bw, "property float rot_3"); // z
                WriteStringLine(bw, "property float f_dc_0");
                WriteStringLine(bw, "property float f_dc_1");
                WriteStringLine(bw, "property float f_dc_2");
                WriteStringLine(bw, "end_header");

                for (int i = 0; i < count; i++)
                {
                    // Position
                    bw.Write(pos[i].X);
                    bw.Write(pos[i].Y);
                    bw.Write(pos[i].Z);

                    // Opacity (sigmoid inverse logit: log(p / (1-p)))
                    float p = Math.Clamp(op[i], 0.001f, 0.999f);
                    float logit = MathF.Log(p / (1.0f - p));
                    bw.Write(logit);

                    // Scales (log space)
                    float s0 = MathF.Log(Math.Max(scl[i].X, 0.0001f));
                    float s1 = MathF.Log(Math.Max(scl[i].Y, 0.0001f));
                    float s2 = MathF.Log(Math.Max(scl[i].Z, 0.0001f));
                    bw.Write(s0);
                    bw.Write(s1);
                    bw.Write(s2);

                    // Rotation (rot_0, rot_1, rot_2, rot_3 is w, x, y, z)
                    Quaternion q = rot[i].Normalized();
                    bw.Write(q.W);
                    bw.Write(q.X);
                    bw.Write(q.Y);
                    bw.Write(q.Z);

                    // Colors (f_dc spherical harmonics degree-0 coefficient: (c - 0.5) / 0.28209)
                    float dc0 = (col[i].R - 0.5f) / 0.28209f;
                    float dc1 = (col[i].G - 0.5f) / 0.28209f;
                    float dc2 = (col[i].B - 0.5f) / 0.28209f;
                    bw.Write(dc0);
                    bw.Write(dc1);
                    bw.Write(dc2);
                }

                return true;
            }
        }

        private static bool ExportToSplat(FoveaSplatResource resource, string globalPath)
        {
            int count = resource.SplatCount;
            var pos = resource.Positions;
            var rot = resource.Rotations;
            var scl = resource.Scales;
            var col = resource.Colors;
            var op = resource.Opacities;

            using (var fs = new FileStream(globalPath, FileMode.Create, System.IO.FileAccess.Write))
            using (var bw = new BinaryWriter(fs))
            {
                for (int i = 0; i < count; i++)
                {
                    // 12 bytes position (3 x float)
                    bw.Write(pos[i].X);
                    bw.Write(pos[i].Y);
                    bw.Write(pos[i].Z);

                    // 12 bytes scale (3 x float)
                    bw.Write(scl[i].X);
                    bw.Write(scl[i].Y);
                    bw.Write(scl[i].Z);

                    // 4 bytes color (RGBA uint8)
                    bw.Write((byte)Math.Clamp(col[i].R * 255f, 0f, 255f));
                    bw.Write((byte)Math.Clamp(col[i].G * 255f, 0f, 255f));
                    bw.Write((byte)Math.Clamp(col[i].B * 255f, 0f, 255f));
                    bw.Write((byte)Math.Clamp(op[i] * 255f, 0f, 255f));

                    // 4 bytes rotation quaternion (RGBA uint8 mapped to -1..1)
                    Quaternion q = rot[i].Normalized();
                    bw.Write((byte)Math.Clamp((q.X * 128f) + 128f, 0f, 255f));
                    bw.Write((byte)Math.Clamp((q.Y * 128f) + 128f, 0f, 255f));
                    bw.Write((byte)Math.Clamp((q.Z * 128f) + 128f, 0f, 255f));
                    bw.Write((byte)Math.Clamp((q.W * 128f) + 128f, 0f, 255f));
                }

                return true;
            }
        }

        private static void WriteStringLine(BinaryWriter bw, string text)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(text + "\n");
            bw.Write(bytes);
        }
    }
}
