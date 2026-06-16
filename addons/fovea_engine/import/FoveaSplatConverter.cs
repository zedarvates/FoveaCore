using Godot;
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

namespace FoveaEngine
{
    public static class FoveaSplatConverter
    {
        public static FoveaSplatResource ConvertFileToResource(string path)
        {
            string globalPath = ProjectSettings.GlobalizePath(path);
            if (!File.Exists(globalPath))
            {
                GD.PushError($"FoveaSplatConverter: File not found at '{globalPath}'");
                return null;
            }

            string ext = Path.GetExtension(path).ToLower();
            FoveaSplatResource resource = null;

            try
            {
                if (ext == ".ply") resource = LoadPly(globalPath);
                else if (ext == ".splat" || ext == ".gsplat") resource = LoadSplat(globalPath);
                else if (ext == ".pcd") resource = LoadPcd(globalPath);
                else if (ext == ".bin") resource = LoadBin(globalPath);
                else if (ext == ".npy") resource = LoadNpy(globalPath);
                else
                {
                    GD.PushError($"FoveaSplatConverter: Unsupported format '{ext}'");
                }
            }
            catch (Exception ex)
            {
                GD.PushError($"FoveaSplatConverter: Error parsing '{path}': {ex.Message}");
            }

            if (resource != null)
            {
                resource.RecalculateBounds();
                resource.SortByMorton();
            }

            return resource;
        }

        public static void Decimate(FoveaSplatResource resource, float ratio)
        {
            if (resource == null || ratio <= 0f || ratio >= 1.0f) return;

            int count = resource.SplatCount;
            int targetCount = (int)(count * ratio);
            if (targetCount <= 0) targetCount = 1;

            var newPositions = new Vector3[targetCount];
            var newRotationsFlat = new float[targetCount * 4];
            var newScales = new Vector3[targetCount];
            var newColors = new Color[targetCount];
            var newOpacities = new float[targetCount];
            var newNormals = new Vector3[targetCount];

            var rand = new Random();
            var indices = new List<int>(count);
            for (int i = 0; i < count; i++) indices.Add(i);

            // Fisher-Yates shuffle subset
            for (int i = 0; i < targetCount; i++)
            {
                int r = rand.Next(i, count);
                int tmp = indices[i];
                indices[i] = indices[r];
                indices[r] = tmp;
            }

            bool hasNormals = resource.Normals != null && resource.Normals.Length == count;

            for (int i = 0; i < targetCount; i++)
            {
                int src = indices[i];
                newPositions[i] = resource.Positions[src];
                newRotationsFlat[i * 4] = resource.RotationsFlat[src * 4];
                newRotationsFlat[i * 4 + 1] = resource.RotationsFlat[src * 4 + 1];
                newRotationsFlat[i * 4 + 2] = resource.RotationsFlat[src * 4 + 2];
                newRotationsFlat[i * 4 + 3] = resource.RotationsFlat[src * 4 + 3];
                newScales[i] = resource.Scales[src];
                newColors[i] = resource.Colors[src];
                newOpacities[i] = resource.Opacities[src];
                if (hasNormals)
                {
                    newNormals[i] = resource.Normals[src];
                }
            }

            resource.Positions = newPositions;
            resource.RotationsFlat = newRotationsFlat;
            resource.Scales = newScales;
            resource.Colors = newColors;
            resource.Opacities = newOpacities;
            if (hasNormals) resource.Normals = newNormals;
            resource.RecalculateBounds();
        }

        public static void RecalculateNormals(FoveaSplatResource resource)
        {
            if (resource == null) return;
            int count = resource.SplatCount;
            var normals = new Vector3[count];
            var rotations = resource.Rotations;

            for (int i = 0; i < count; i++)
            {
                // The normal of a Gaussian Splat is oriented along the thinnest axis (local Z/Forward)
                normals[i] = rotations[i] * Vector3.Forward;
            }

            resource.Normals = normals;
        }

        private struct PlyProperty
        {
            public string Name;
            public string Type;
        }

        private static float ReadPropertyVal(BinaryReader br, string type)
        {
            switch (type)
            {
                case "char":
                case "int8":
                    return br.ReadSByte();
                case "uchar":
                case "uint8":
                    return br.ReadByte();
                case "short":
                case "int16":
                    return br.ReadInt16();
                case "ushort":
                case "uint16":
                    return br.ReadUInt16();
                case "int":
                case "int32":
                    return br.ReadInt32();
                case "uint":
                case "uint32":
                    return br.ReadUInt32();
                case "float":
                case "float32":
                    return br.ReadSingle();
                case "double":
                case "float64":
                    return (float)br.ReadDouble();
                default:
                    return br.ReadSingle();
            }
        }

        private static FoveaSplatResource LoadPly(string globalPath)
        {
            using (var fs = new FileStream(globalPath, FileMode.Open, System.IO.FileAccess.Read))
            using (var br = new BinaryReader(fs))
            {
                // Parse Header
                string line = ReadLine(br);
                if (line != "ply") throw new Exception("Not a valid PLY file.");

                int vertexCount = 0;
                var properties = new List<PlyProperty>();

                while (true)
                {
                    line = ReadLine(br);
                    if (line == "end_header") break;

                    if (line.StartsWith("element vertex"))
                    {
                        var parts = line.Split(' ');
                        vertexCount = int.Parse(parts[2]);
                    }
                    else if (line.StartsWith("property"))
                    {
                        var parts = line.Split(' ');
                        if (parts.Length >= 3)
                        {
                            properties.Add(new PlyProperty { Name = parts[2], Type = parts[1] });
                        }
                    }
                }

                var propMap = new Dictionary<string, int>();
                for (int i = 0; i < properties.Count; i++)
                {
                    propMap[properties[i].Name] = i;
                }

                var positions = new Vector3[vertexCount];
                var rotations = new Quaternion[vertexCount];
                var scales = new Vector3[vertexCount];
                var colors = new Color[vertexCount];
                var opacities = new float[vertexCount];
                var normals = new Vector3[vertexCount];

                int propCount = properties.Count;

                for (int i = 0; i < vertexCount; i++)
                {
                    float[] data = new float[propCount];
                    for (int p = 0; p < propCount; p++)
                    {
                        data[p] = ReadPropertyVal(br, properties[p].Type);
                    }

                    Vector3 pos = Vector3.Zero;
                    if (propMap.TryGetValue("x", out int idxX)) pos.X = data[idxX];
                    if (propMap.TryGetValue("y", out int idxY)) pos.Y = data[idxY];
                    if (propMap.TryGetValue("z", out int idxZ)) pos.Z = data[idxZ];
                    positions[i] = pos;

                    float op = 1.0f;
                    if (propMap.TryGetValue("opacity", out int idxOp))
                    {
                        float logit = data[idxOp];
                        op = 1.0f / (1.0f + Mathf.Exp(-logit));
                    }
                    opacities[i] = op;

                    Vector3 scale = Vector3.One;
                    if (propMap.TryGetValue("scale_0", out int idxS0)) scale.X = Mathf.Exp(data[idxS0]);
                    if (propMap.TryGetValue("scale_1", out int idxS1)) scale.Y = Mathf.Exp(data[idxS1]);
                    if (propMap.TryGetValue("scale_2", out int idxS2)) scale.Z = Mathf.Exp(data[idxS2]);
                    scales[i] = scale;

                    Quaternion rot = Quaternion.Identity;
                    if (propMap.TryGetValue("rot_0", out int idxR0) &&
                        propMap.TryGetValue("rot_1", out int idxR1) &&
                        propMap.TryGetValue("rot_2", out int idxR2) &&
                        propMap.TryGetValue("rot_3", out int idxR3))
                    {
                        // Quaternion rotation values in PLY are [w, x, y, z] or [x, y, z, w] depending on convention.
                        // Standard Gaussian Splatting uses [rot_0, rot_1, rot_2, rot_3] as [w, x, y, z].
                        // Godot Quaternion constructor is (x, y, z, w).
                        rot = new Quaternion(data[idxR1], data[idxR2], data[idxR3], data[idxR0]).Normalized();
                    }
                    rotations[i] = rot;

                    float r = 0.5f, g = 0.5f, b = 0.5f;
                    if (propMap.TryGetValue("f_dc_0", out int idxC0)) r = 0.5f + 0.28209f * data[idxC0];
                    if (propMap.TryGetValue("f_dc_1", out int idxC1)) g = 0.5f + 0.28209f * data[idxC1];
                    if (propMap.TryGetValue("f_dc_2", out int idxC2)) b = 0.5f + 0.28209f * data[idxC2];
                    colors[i] = new Color(r, g, b);

                    // Estimate normal direction
                    normals[i] = rot * Vector3.Forward;
                }

                var resource = new FoveaSplatResource
                {
                    Positions = positions,
                    Rotations = rotations,
                    Scales = scales,
                    Colors = colors,
                    Opacities = opacities,
                    Normals = normals
                };

                return resource;
            }
        }

        private static FoveaSplatResource LoadSplat(string globalPath)
        {
            using (var fs = new FileStream(globalPath, FileMode.Open, System.IO.FileAccess.Read))
            using (var br = new BinaryReader(fs))
            {
                long length = fs.Length;
                int count = (int)(length / 32); // Each splat is 32 bytes

                var positions = new Vector3[count];
                var rotations = new Quaternion[count];
                var scales = new Vector3[count];
                var colors = new Color[count];
                var opacities = new float[count];
                var normals = new Vector3[count];

                for (int i = 0; i < count; i++)
                {
                    // 12 bytes position (3 x float)
                    float px = br.ReadSingle();
                    float py = br.ReadSingle();
                    float pz = br.ReadSingle();
                    positions[i] = new Vector3(px, py, pz);

                    // 12 bytes scale (3 x float)
                    float sx = br.ReadSingle();
                    float sy = br.ReadSingle();
                    float sz = br.ReadSingle();
                    scales[i] = new Vector3(sx, sy, sz);

                    // 4 bytes color (RGBA uint8)
                    byte r = br.ReadByte();
                    byte g = br.ReadByte();
                    byte b = br.ReadByte();
                    byte a = br.ReadByte();
                    colors[i] = new Color(r / 255f, g / 255f, b / 255f);
                    opacities[i] = a / 255f;

                    // 4 bytes rotation quaternion (RGBA uint8 mapped to -1..1)
                    float rx = (br.ReadByte() - 128f) / 128f;
                    float ry = (br.ReadByte() - 128f) / 128f;
                    float rz = (br.ReadByte() - 128f) / 128f;
                    float rw = (br.ReadByte() - 128f) / 128f;
                    var q = new Quaternion(rx, ry, rz, rw).Normalized();
                    rotations[i] = q;

                    normals[i] = q * Vector3.Forward;
                }

                return new FoveaSplatResource
                {
                    Positions = positions,
                    Rotations = rotations,
                    Scales = scales,
                    Colors = colors,
                    Opacities = opacities,
                    Normals = normals
                };
            }
        }

        private static FoveaSplatResource LoadPcd(string globalPath)
        {
            var positions = new List<Vector3>();
            var colors = new List<Color>();

            using (var fs = new FileStream(globalPath, FileMode.Open, System.IO.FileAccess.Read))
            using (var reader = new StreamReader(fs))
            {
                string line;
                bool readingData = false;
                while ((line = reader.ReadLine()) != null)
                {
                    if (line.StartsWith("DATA"))
                    {
                        readingData = true;
                        continue;
                    }
                    if (!readingData || string.IsNullOrWhiteSpace(line)) continue;

                    var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length >= 3)
                    {
                        float x = float.Parse(parts[0]);
                        float y = float.Parse(parts[1]);
                        float z = float.Parse(parts[2]);
                        positions.Add(new Vector3(x, y, z));

                        Color col = Colors.White;
                        if (parts.Length >= 4)
                        {
                            // If RGB is packed as float/int
                            if (float.TryParse(parts[3], out float rgbPacked))
                            {
                                int rgb = BitConverter.ToInt32(BitConverter.GetBytes(rgbPacked), 0);
                                byte r = (byte)((rgb >> 16) & 0xFF);
                                byte g = (byte)((rgb >> 8) & 0xFF);
                                byte b = (byte)(rgb & 0xFF);
                                col = new Color(r / 255f, g / 255f, b / 255f);
                            }
                        }
                        colors.Add(col);
                    }
                }
            }

            int count = positions.Count;
            var rotations = new Quaternion[count];
            var scales = new Vector3[count];
            var opacities = new float[count];
            var normals = new Vector3[count];

            for (int i = 0; i < count; i++)
            {
                rotations[i] = Quaternion.Identity;
                scales[i] = new Vector3(0.05f, 0.05f, 0.05f); // Point cloud nodes default size
                opacities[i] = 1.0f;
                normals[i] = Vector3.Forward;
            }

            return new FoveaSplatResource
            {
                Positions = positions.ToArray(),
                Rotations = rotations,
                Scales = scales,
                Colors = colors.ToArray(),
                Opacities = opacities,
                Normals = normals
            };
        }

        private static FoveaSplatResource LoadBin(string globalPath)
        {
            // InstantNGP format parser
            using (var fs = new FileStream(globalPath, FileMode.Open, System.IO.FileAccess.Read))
            using (var br = new BinaryReader(fs))
            {
                // First 4 bytes: int count of points
                int count = br.ReadInt32();
                var positions = new Vector3[count];
                var rotations = new Quaternion[count];
                var scales = new Vector3[count];
                var colors = new Color[count];
                var opacities = new float[count];
                var normals = new Vector3[count];

                for (int i = 0; i < count; i++)
                {
                    float px = br.ReadSingle();
                    float py = br.ReadSingle();
                    float pz = br.ReadSingle();
                    positions[i] = new Vector3(px, py, pz);

                    // Default values since NGP represents points
                    rotations[i] = Quaternion.Identity;
                    scales[i] = new Vector3(0.02f, 0.02f, 0.02f);
                    colors[i] = Colors.White;
                    opacities[i] = 1.0f;
                    normals[i] = Vector3.Forward;
                }

                return new FoveaSplatResource
                {
                    Positions = positions,
                    Rotations = rotations,
                    Scales = scales,
                    Colors = colors,
                    Opacities = opacities,
                    Normals = normals
                };
            }
        }

        private static FoveaSplatResource LoadNpy(string globalPath)
        {
            // Nerfstudio/Numpy array parser
            using (var fs = new FileStream(globalPath, FileMode.Open, System.IO.FileAccess.Read))
            using (var br = new BinaryReader(fs))
            {
                byte[] magic = br.ReadBytes(6);
                string magicStr = Encoding.ASCII.GetString(magic);
                if (magicStr != "\x93NUMPY") throw new Exception("Not a valid NPY file.");

                byte major = br.ReadByte();
                byte minor = br.ReadByte();
                ushort headerLen = br.ReadUInt16();

                byte[] headerBytes = br.ReadBytes(headerLen);
                string header = Encoding.ASCII.GetString(headerBytes);

                // Extract shape
                int count = 1000;
                int dim = 3; // Default fallback to XYZ
                
                var shapeIdx = header.IndexOf("'shape'");
                if (shapeIdx == -1) shapeIdx = header.IndexOf("\"shape\"");
                if (shapeIdx != -1)
                {
                    var startTuple = header.IndexOf('(', shapeIdx);
                    var endTuple = header.IndexOf(')', startTuple);
                    if (startTuple != -1 && endTuple != -1)
                    {
                        var tupleStr = header.Substring(startTuple + 1, endTuple - startTuple - 1);
                        var parts = tupleStr.Split(',');
                        if (parts.Length > 0 && int.TryParse(parts[0].Trim(), out int parsedCount))
                        {
                            count = parsedCount;
                        }
                        if (parts.Length > 1 && int.TryParse(parts[1].Trim(), out int parsedDim))
                        {
                            dim = parsedDim;
                        }
                    }
                }

                long remainingBytes = fs.Length - fs.Position;
                if (remainingBytes > 0 && dim <= 3)
                {
                    count = (int)(remainingBytes / (3 * 4)); // Assume 3 floats per point (XYZ)
                }

                var positions = new Vector3[count];
                var rotations = new Quaternion[count];
                var scales = new Vector3[count];
                var colors = new Color[count];
                var opacities = new float[count];
                var normals = new Vector3[count];

                for (int i = 0; i < count; i++)
                {
                    if (fs.Position + dim * 4 > fs.Length) break;

                    float[] row = new float[dim];
                    for (int d = 0; d < dim; d++)
                    {
                        row[d] = br.ReadSingle();
                    }

                    positions[i] = new Vector3(row[0], row[1], row[2]);

                    if (dim >= 6)
                    {
                        // f_dc_0, f_dc_1, f_dc_2 -> SH to RGB
                        float r = 0.5f + 0.28209f * row[3];
                        float g = 0.5f + 0.28209f * row[4];
                        float b = 0.5f + 0.28209f * row[5];
                        colors[i] = new Color(r, g, b);
                    }
                    else
                    {
                        colors[i] = Colors.White;
                    }

                    if (dim >= 7)
                    {
                        // opacity logit -> sigmoid
                        float logit = row[6];
                        opacities[i] = 1.0f / (1.0f + Mathf.Exp(-logit));
                    }
                    else
                    {
                        opacities[i] = 1.0f;
                    }

                    if (dim >= 10)
                    {
                        scales[i] = new Vector3(Mathf.Exp(row[7]), Mathf.Exp(row[8]), Mathf.Exp(row[9]));
                    }
                    else
                    {
                        scales[i] = new Vector3(0.05f, 0.05f, 0.05f);
                    }

                    if (dim >= 14)
                    {
                        // rotation [w, x, y, z] -> Godot Quaternion (x, y, z, w)
                        rotations[i] = new Quaternion(row[11], row[12], row[13], row[10]).Normalized();
                    }
                    else
                    {
                        rotations[i] = Quaternion.Identity;
                    }

                    normals[i] = rotations[i] * Vector3.Forward;
                }

                return new FoveaSplatResource
                {
                    Positions = positions,
                    Rotations = rotations,
                    Scales = scales,
                    Colors = colors,
                    Opacities = opacities,
                    Normals = normals
                };
            }
        }

        private static string ReadLine(BinaryReader br)
        {
            var sb = new StringBuilder();
            while (true)
            {
                byte b = br.ReadByte();
                if (b == '\n') break;
                if (b != '\r') sb.Append((char)b);
            }
            return sb.ToString();
        }
    }
}
