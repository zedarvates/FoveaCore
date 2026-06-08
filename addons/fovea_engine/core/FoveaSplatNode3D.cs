using Godot;
using System;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatNode3D : Node3D
    {
        private FoveaSplatResource _splatResource;

        [Export]
        public FoveaSplatResource SplatResource
        {
            get => _splatResource;
            set
            {
                _splatResource = value;
                UpdateRenderer();
            }
        }

        [Export(PropertyHint.File, "*.ply,*.fovea,*.splat,*.gsplat,*.pcd,*.bin,*.npy")]
        public string SplatFilePath { get; set; } = "";

        [ExportGroup("Physics Collision")]
        [Export]
        public bool GenerateCollisions { get; set; } = false;

        [Export]
        public float VoxelSize { get; set; } = 0.15f;

        [Export(PropertyHint.Range, "0.0,1.0")]
        public float OpacityThreshold { get; set; } = 0.1f;

        [ExportGroup("Skeleton Attachment")]
        [Export]
        public NodePath SkeletonPath { get; set; }
        
        [Export]
        public string BoneName { get; set; } = "";

        public int SplatCount => SplatResource?.SplatCount ?? 0;

        private FoveaSplatRenderer _renderer;
        private Skeleton3D _skeleton;
        private int _boneIdx = -1;

        public override void _Ready()
        {
            // Ensure FoveaSplatRenderer is instantiated
            _renderer = new FoveaSplatRenderer();
            _renderer.Name = "FoveaSplatRenderer";
            AddChild(_renderer);

            if (!string.IsNullOrEmpty(SplatFilePath))
            {
                LoadSplatFile(SplatFilePath);
            }
            else if (_splatResource != null)
            {
                UpdateRenderer();
            }

            if (GenerateCollisions)
            {
                Callable.From(GenerateVoxelCollisions).CallDeferred();
            }

            SetupSkeletonAttachment();
        }

        public override void _Process(double delta)
        {
            if (_skeleton != null && _boneIdx != -1)
            {
                // Align node transform to bone pose
                Transform3D bonePose = _skeleton.GetBoneGlobalPose(_boneIdx);
                GlobalTransform = _skeleton.GlobalTransform * bonePose;
            }
        }

        public void LoadSplatFile(string path)
        {
            SplatFilePath = path;
            var resource = FoveaSplatConverter.ConvertFileToResource(path);
            if (resource != null)
            {
                SplatResource = resource;
            }
        }

        private void UpdateRenderer()
        {
            if (_renderer != null && _splatResource != null)
            {
                _renderer.SetSplatResource(_splatResource);
            }
        }

        private void SetupSkeletonAttachment()
        {
            if (SkeletonPath == null || string.IsNullOrEmpty(BoneName)) return;

            _skeleton = GetNodeOrNull<Skeleton3D>(SkeletonPath);
            if (_skeleton != null)
            {
                _boneIdx = _skeleton.FindBone(BoneName);
                if (_boneIdx == -1)
                {
                    GD.PushWarning($"FoveaSplatNode3D: Bone '{BoneName}' not found in skeleton '{SkeletonPath}'.");
                }
            }
        }

        private void GenerateVoxelCollisions()
        {
            GD.Print($"FoveaSplatNode3D: Generating physics collision using FoveaVoxelizer for {SplatFilePath}...");
            
            // Check if FoveaVoxelizer GDExtension/GDScript singleton is available
            if (ClassDB.CanInstantiate("FoveaVoxelizer"))
            {
                try
                {
                    GodotObject voxelizer = ClassDB.Instantiate("FoveaVoxelizer").AsGodotObject();
                    if (voxelizer != null)
                    {
                        var shape = voxelizer.Call("generate_collision_shape", SplatFilePath, VoxelSize, OpacityThreshold).As<Shape3D>();
                        if (shape != null)
                        {
                            var staticBody = new StaticBody3D { Name = "SplatCollisionBody" };
                            var collisionShape = new CollisionShape3D { Name = "SplatCollisionShape", Shape = shape };
                            staticBody.AddChild(collisionShape);
                            AddChild(staticBody);
                            GD.Print("FoveaSplatNode3D: Physics collision body attached.");
                        }
                    }
                }
                catch (Exception ex)
                {
                    GD.PushError($"FoveaSplatNode3D: Failed to call FoveaVoxelizer: {ex.Message}");
                }
            }
            else
            {
                GD.PushWarning("FoveaSplatNode3D: FoveaVoxelizer ClassDB type not available. Voxel collision skipped.");
            }
        }

        public FoveaSplatRenderer GetRenderer() => _renderer;
    }
}
