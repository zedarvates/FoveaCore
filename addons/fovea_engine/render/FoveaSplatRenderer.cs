using Godot;
using System;
using System.Threading.Tasks;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatRenderer : MultiMeshInstance3D
    {
        [Export]
        public string AssetPath { get; set; } = "";

        [Export]
        public float CullThreshold { get; set; } = 0.0f;

        [Export]
        public bool UseTriangleMesh { get; set; } = true;

        [Export]
        public int SplatSubdivisions { get; set; } = 16;

        [Export]
        public float SortDistanceThreshold { get; set; } = 0.1f;

        [Export]
        public float ChunkLoadRadius { get; set; } = 20.0f;

        [ExportGroup("Cleaning")]
        [Export]
        public bool EnableCleaning { get; set; } = true;

        [Export(PropertyHint.Range, "1,4")]
        public int FloaterNeighborRadius { get; set; } = 1;

        [Export(PropertyHint.Range, "1,10")]
        public int FloaterMinNeighbors { get; set; } = 2;

        [ExportGroup("Motion-Adaptive Splatting")]
        [Export]
        public bool EnableMotionLod { get; set; } = true;

        [Export]
        public float MotionSpeedThreshold { get; set; } = 1.5f;

        [Export(PropertyHint.Range, "0.05,1.0")]
        public float MotionLodMinimum { get; set; } = 0.25f;

        [Export]
        public bool EnableMotionStretch { get; set; } = true;

        [Export(PropertyHint.Range, "0.0,5.0")]
        public float MotionStretchMax { get; set; } = 2.5f;

        private FoveaSplatResource _splatResource;
        private byte[] _packedBytes;
        private RefCounted _cullerPipeline;
        private Vector3 _lastCameraPos = Vector3.Zero;
        private Vector3 _prevCamPos = Vector3.Zero;
        private ArrayMesh _splatMesh;
        private ShaderMaterial _material;

        public override void _Ready()
        {
            GenerateSplatGeometry();
            SetupShaderMaterial();
            SetupCullerPipeline();

            if (!string.IsNullOrEmpty(AssetPath))
            {
                LoadAssetFromFile();
            }
        }

        public override void _Process(double delta)
        {
            var camera = GetViewport().GetCamera3D();
            if (camera == null || _material == null) return;

            Vector3 camPos = camera.GlobalPosition;
            float speed = 0.0f;

            if (delta > 0.0001)
            {
                Vector3 velocity = (camPos - _prevCamPos) / (float)delta;
                speed = velocity.Length();
                _prevCamPos = camPos;

                if (EnableMotionLod)
                {
                    float lod = 1.0f;
                    if (speed > MotionSpeedThreshold)
                    {
                        float overThreshold = speed - MotionSpeedThreshold;
                        float t = Mathf.Clamp(overThreshold / MotionSpeedThreshold, 0.0f, 1.0f);
                        lod = Mathf.Lerp(1.0f, MotionLodMinimum, t);

                        if (EnableMotionStretch)
                        {
                            Basis viewBasis = camera.GetCameraTransform().AffineInverse().Basis;
                            Vector3 velView = viewBasis * velocity;
                            Vector2 motionDirScreen = new Vector2(velView.X, -velView.Y);
                            if (motionDirScreen.Length() > 0.001f)
                            {
                                motionDirScreen = motionDirScreen.Normalized();
                            }
                            float stretch = t * MotionStretchMax;

                            _material.SetShaderParameter("motion_dir_screen", motionDirScreen);
                            _material.SetShaderParameter("motion_stretch_factor", stretch);
                        }
                        else
                        {
                            _material.SetShaderParameter("motion_stretch_factor", 0.0f);
                        }
                    }
                    else
                    {
                        if (EnableMotionStretch)
                        {
                            float currentStretch = (float)_material.GetShaderParameter("motion_stretch_factor");
                            if (currentStretch > 0.01f)
                            {
                                _material.SetShaderParameter("motion_stretch_factor", Mathf.Lerp(currentStretch, 0.0f, 0.15f));
                            }
                            else
                            {
                                _material.SetShaderParameter("motion_stretch_factor", 0.0f);
                            }
                        }
                    }

                    _material.SetShaderParameter("lod_ratio", lod);
                }
            }

            // Real-time culling and distance update
            if (!string.IsNullOrEmpty(AssetPath) && (camPos - _lastCameraPos).Length() > SortDistanceThreshold)
            {
                _lastCameraPos = camPos;
                UpdateGPUCulling(camera);
            }
        }

        public void SetSplatResource(FoveaSplatResource resource)
        {
            _splatResource = resource;
            if (_splatResource != null)
            {
                _packedBytes = PackSplatResource(_splatResource);
                RenderSplatsDirect();
            }
        }

        public int render_splats(Godot.Collections.Array splats)
        {
            int count = splats.Count;
            if (count == 0) return 0;

            var positions = new Vector3[count];
            var rotations = new Quaternion[count];
            var scales = new Vector3[count];
            var colors = new Color[count];
            var opacities = new float[count];
            var normals = new Vector3[count];

            for (int i = 0; i < count; i++)
            {
                var s = splats[i].AsGodotObject();
                if (s != null)
                {
                    positions[i] = s.Get("position").AsVector3();
                    rotations[i] = s.Get("rotation").AsQuaternion();
                    scales[i] = s.Get("scale").AsVector3();
                    colors[i] = s.Get("color").AsColor();
                    opacities[i] = (float)s.Get("opacity").AsDouble();
                    
                    var normalVar = s.Get("normal");
                    normals[i] = normalVar.VariantType != Variant.Type.Nil ? normalVar.AsVector3() : Vector3.Forward;
                }
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
            resource.RecalculateBounds();

            SetSplatResource(resource);

            return count;
        }

        private void GenerateSplatGeometry()
        {
            _splatMesh = new ArrayMesh();
            var surfaceTool = new SurfaceTool();
            surfaceTool.Begin(Mesh.PrimitiveType.Triangles);

            float angleStep = Mathf.Tau / SplatSubdivisions;
            var vertices = new Vector3[SplatSubdivisions];

            for (int i = 0; i < SplatSubdivisions; i++)
            {
                float angle = i * angleStep;
                vertices[i] = new Vector3(Mathf.Cos(angle), Mathf.Sin(angle), 0);
            }

            for (int i = 0; i < SplatSubdivisions; i++)
            {
                int nextI = (i + 1) % SplatSubdivisions;

                // Vertex 1: Center
                surfaceTool.SetNormal(new Vector3(0, 0, 1));
                surfaceTool.SetUV(new Vector2(0.5f, 0.5f));
                surfaceTool.AddVertex(Vector3.Zero);

                // Vertex 2: i
                float angleI = i * angleStep;
                var uvI = new Vector2((Mathf.Cos(angleI) + 1.0f) * 0.5f, (Mathf.Sin(angleI) + 1.0f) * 0.5f);
                surfaceTool.SetNormal(new Vector3(0, 0, 1));
                surfaceTool.SetUV(uvI);
                surfaceTool.AddVertex(vertices[i]);

                // Vertex 3: i+1
                float angleNext = nextI * angleStep;
                var uvNext = new Vector2((Mathf.Cos(angleNext) + 1.0f) * 0.5f, (Mathf.Sin(angleNext) + 1.0f) * 0.5f);
                surfaceTool.SetNormal(new Vector3(0, 0, 1));
                surfaceTool.SetUV(uvNext);
                surfaceTool.AddVertex(vertices[nextI]);
            }

            surfaceTool.GenerateNormals();
            _splatMesh = surfaceTool.Commit();

            Multimesh = new MultiMesh
            {
                TransformFormat = MultiMesh.TransformFormatEnum.Transform3D,
                UseCustomData = true,
                Mesh = _splatMesh
            };
        }

        private void SetupShaderMaterial()
        {
            _material = new ShaderMaterial();
            _material.Shader = GD.Load<Shader>("res://addons/fovea_engine/render/FoveaSplatRenderer.gdshader");
            _material.SetShaderParameter("splat_subdivisions", SplatSubdivisions);
            MaterialOverride = _material;
            SetDefaultCovarTexture();
        }

        private void SetupCullerPipeline()
        {
            try
            {
                var script = GD.Load<Script>("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd");
                if (script != null)
                {
                    _cullerPipeline = (RefCounted)script.Call("new");
                    _cullerPipeline.Set("interleave_factor", 4);
                }
            }
            catch (Exception ex)
            {
                GD.PushWarning($"FoveaSplatRenderer: GPUCullerPipeline GDExtension or GDScript not found. Falling back to CPU decoder: {ex.Message}");
            }
        }

        private void LoadAssetFromFile()
        {
            var res = FoveaSplatConverter.ConvertFileToResource(AssetPath);
            if (res != null)
            {
                SetSplatResource(res);
            }
        }

        private void RenderSplatsDirect()
        {
            if (_splatResource == null || _packedBytes == null) return;

            int count = _splatResource.SplatCount;
            Multimesh.InstanceCount = count;

            if (count == 0) return;

            Vector3 aabbMin = _splatResource.BBox.Position;
            Vector3 aabbMax = _splatResource.BBox.End;

            _material.SetShaderParameter("aabb_min", aabbMin);
            _material.SetShaderParameter("aabb_max", aabbMax);

            var xfArray = new Vector3[count * 4];
            var cdArray = new Color[count];
            var origTransforms = new Transform3D[count];

            FoveaSplatDecoder.DecodeParallel(_packedBytes, count, aabbMin, aabbMax, xfArray, cdArray, origTransforms);

            Multimesh.TransformArray = xfArray;
            Multimesh.CustomDataArray = cdArray;
        }

        private void UpdateGPUCulling(Camera3D camera)
        {
            if (_cullerPipeline == null || string.IsNullOrEmpty(AssetPath)) return;

            try
            {
                // Call culler pipeline
                // In Godot C#, calling GDScript methods requires Call()
                Rid depthTex = new Rid(); // Mock depth tex
                Vector3 aabbMin = _splatResource != null ? _splatResource.BBox.Position : new Vector3(-10, -10, -10);
                Vector3 aabbMax = _splatResource != null ? _splatResource.BBox.End : new Vector3(10, 10, 10);

                Rid outputBuf = _cullerPipeline.Call("process_splats_from_file", AssetPath, camera, depthTex, CullThreshold, aabbMin, aabbMax).AsRid();
                if (outputBuf.IsValid)
                {
                    var rd = (RenderingDevice)_cullerPipeline.Get("rd");
                    if (rd != null)
                    {
                        byte[] culledBytes = rd.BufferGetData(outputBuf);
                        int survivingCount = culledBytes.Length / 16;
                        
                        if (survivingCount > 0)
                        {
                            Multimesh.InstanceCount = survivingCount;
                            var xfArray = new Vector3[survivingCount * 4];
                            var cdArray = new Color[survivingCount];
                            var origTransforms = new Transform3D[survivingCount];

                            FoveaSplatDecoder.DecodeParallel(culledBytes, survivingCount, aabbMin, aabbMax, xfArray, cdArray, origTransforms);

                            Multimesh.TransformArray = xfArray;
                            Multimesh.CustomDataArray = cdArray;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                GD.PushError($"FoveaSplatRenderer: GPU Culling process failed, rendering direct. Error: {ex.Message}");
                RenderSplatsDirect();
            }
        }

        private void SetDefaultCovarTexture()
        {
            byte[] defaultData = new byte[32];
            // Pixel 0
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 0, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 4, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 8, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(1.0f), 0, defaultData, 12, 4);
            // Pixel 1
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 16, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 20, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 24, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(0.0f), 0, defaultData, 28, 4);

            var img = Image.CreateFromData(2, 1, false, Image.Format.Rgbaf, defaultData);
            var tex = ImageTexture.CreateFromImage(img);
            _material.SetShaderParameter("covar_texture", tex);
        }

        private byte[] PackSplatResource(FoveaSplatResource resource)
        {
            int count = resource.SplatCount;
            byte[] bytes = new byte[count * 16];

            Vector3 aabbMin = resource.BBox.Position;
            Vector3 aabbMax = resource.BBox.End;

            float rangeX = Math.Max(aabbMax.X - aabbMin.X, 0.001f);
            float rangeY = Math.Max(aabbMax.Y - aabbMin.Y, 0.001f);
            float rangeZ = Math.Max(aabbMax.Z - aabbMin.Z, 0.001f);

            var pos = resource.Positions;
            var rot = resource.Rotations;
            var col = resource.Colors;
            var op = resource.Opacities;
            var normals = resource.Normals;

            bool hasNormals = normals != null && normals.Length == count;

            for (int i = 0; i < count; i++)
            {
                int src = i * 16;

                ushort qx = (ushort)Math.Clamp((pos[i].X - aabbMin.X) / rangeX * 65535.0f, 0f, 65535f);
                ushort qy = (ushort)Math.Clamp((pos[i].Y - aabbMin.Y) / rangeY * 65535.0f, 0f, 65535f);
                ushort qz = (ushort)Math.Clamp((pos[i].Z - aabbMin.Z) / rangeZ * 65535.0f, 0f, 65535f);

                Buffer.BlockCopy(BitConverter.GetBytes(qx), 0, bytes, src, 2);
                Buffer.BlockCopy(BitConverter.GetBytes(qy), 0, bytes, src + 2, 2);
                Buffer.BlockCopy(BitConverter.GetBytes(qz), 0, bytes, src + 4, 2);

                Vector3 norm = hasNormals ? normals[i] : (rot[i] * Vector3.Forward);
                byte nx = (byte)Math.Clamp((norm.X * 0.5f + 0.5f) * 255.0f, 0f, 255f);
                byte nz = (byte)Math.Clamp((norm.Z * 0.5f + 0.5f) * 255.0f, 0f, 255f);
                bytes[src + 6] = nx;
                bytes[src + 7] = nz;

                byte r5 = (byte)Math.Clamp(col[i].R * 31.0f, 0f, 31f);
                byte g6 = (byte)Math.Clamp(col[i].G * 63.0f, 0f, 63f);
                byte b5 = (byte)Math.Clamp(col[i].B * 31.0f, 0f, 31f);
                ushort rgb565 = (ushort)((r5 << 11) | (g6 << 5) | b5);
                Buffer.BlockCopy(BitConverter.GetBytes(rgb565), 0, bytes, src + 8, 2);

                bytes[src + 10] = 0;
                bytes[src + 11] = 0;

                byte opacityByte = (byte)Math.Clamp(op[i] * 255.0f, 0f, 255f);
                bytes[src + 12] = opacityByte;

                bytes[src + 13] = 0;
                bytes[src + 14] = 0;
                bytes[src + 15] = 0;
            }

            return bytes;
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _cullerPipeline != null)
            {
                _cullerPipeline.Call("cleanup");
            }
            base.Dispose(disposing);
        }
    }
}
