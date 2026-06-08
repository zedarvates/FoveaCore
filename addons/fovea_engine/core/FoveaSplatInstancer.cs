using Godot;
using System;
using System.Collections.Generic;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatInstancer : Node3D
    {
        [Export]
        public FoveaSplatResource SourceResource { get; set; }

        [Export]
        public int InstanceCount { get; set; } = 100;

        [ExportGroup("Random Variations")]
        [Export]
        public Vector2 ScaleVariation { get; set; } = new Vector2(0.8f, 1.2f); // Min, Max scale multiplier

        [Export]
        public float RotationYVariation { get; set; } = 360f; // Max rotation on Y axis in degrees

        [Export]
        public Color ColorTintMin { get; set; } = new Color(0.9f, 0.9f, 0.9f);

        [Export]
        public Color ColorTintMax { get; set; } = new Color(1.1f, 1.1f, 1.1f);

        [ExportGroup("Procedural Placement")]
        [Export]
        public Vector3 PlacementAreaSize { get; set; } = new Vector3(20f, 0f, 20f);

        private FoveaSplatRenderer _renderer;
        private FoveaSplatResource _combinedResource;

        public override void _Ready()
        {
            _renderer = new FoveaSplatRenderer();
            _renderer.Name = "InstancedSplatRenderer";
            AddChild(_renderer);

            GenerateInstances();
        }

        /// <summary>
        /// Generates the instances procedurally and combines them into one FoveaSplatResource.
        /// </summary>
        public void GenerateInstances()
        {
            if (SourceResource == null || SourceResource.SplatCount == 0)
            {
                GD.PushWarning("FoveaSplatInstancer: SourceResource is empty or null.");
                return;
            }

            int srcCount = SourceResource.SplatCount;
            int totalCount = srcCount * InstanceCount;

            var combinedPositions = new Vector3[totalCount];
            var combinedRotations = new Quaternion[totalCount];
            var combinedScales = new Vector3[totalCount];
            var combinedColors = new Color[totalCount];
            var combinedOpacities = new float[totalCount];
            var combinedNormals = new Vector3[totalCount];

            var rand = new Random();

            var sourcePositions = SourceResource.Positions;
            var sourceRotations = SourceResource.Rotations;
            var sourceScales = SourceResource.Scales;
            var sourceColors = SourceResource.Colors;
            var sourceOpacities = SourceResource.Opacities;
            var sourceNormals = SourceResource.Normals;

            bool hasNormals = sourceNormals != null && sourceNormals.Length == srcCount;

            for (int inst = 0; inst < InstanceCount; inst++)
            {
                // Procedural Placement: Random position in area
                float px = ((float)rand.NextDouble() - 0.5f) * PlacementAreaSize.X;
                float py = ((float)rand.NextDouble() - 0.5f) * PlacementAreaSize.Y;
                float pz = ((float)rand.NextDouble() - 0.5f) * PlacementAreaSize.Z;
                Vector3 instPos = new Vector3(px, py, pz);

                // Random Y Rotation
                float angleRad = Mathf.DegToRad((float)rand.NextDouble() * RotationYVariation);
                Quaternion instRot = Quaternion.FromEuler(new Vector3(0, angleRad, 0));

                // Random Scale
                float instScaleMult = ScaleVariation.X + (float)rand.NextDouble() * (ScaleVariation.Y - ScaleVariation.X);
                Vector3 instScale = new Vector3(instScaleMult, instScaleMult, instScaleMult);

                // Random Color Tint
                float tr = ColorTintMin.R + (float)rand.NextDouble() * (ColorTintMax.R - ColorTintMin.R);
                float tg = ColorTintMin.G + (float)rand.NextDouble() * (ColorTintMax.G - ColorTintMin.G);
                float tb = ColorTintMin.B + (float)rand.NextDouble() * (ColorTintMax.B - ColorTintMin.B);
                Color instTint = new Color(tr, tg, tb);

                int offset = inst * srcCount;
                for (int i = 0; i < srcCount; i++)
                {
                    int dest = offset + i;

                    // Apply instance transform to position
                    Vector3 localPos = sourcePositions[i] * instScale;
                    combinedPositions[dest] = instRot * localPos + instPos;

                    // Combine rotation
                    combinedRotations[dest] = (instRot * sourceRotations[i]).Normalized();

                    // Apply scale
                    combinedScales[dest] = sourceScales[i] * instScale;

                    // Apply color tint
                    combinedColors[dest] = sourceColors[i] * instTint;

                    // Copy opacity
                    combinedOpacities[dest] = sourceOpacities[i];

                    // Copy and rotate normal
                    if (hasNormals)
                    {
                        combinedNormals[dest] = instRot * sourceNormals[i];
                    }
                }
            }

            _combinedResource = new FoveaSplatResource
            {
                Positions = combinedPositions,
                Rotations = combinedRotations,
                Scales = combinedScales,
                Colors = combinedColors,
                Opacities = combinedOpacities,
                Normals = combinedNormals
            };

            // Re-order combined splats for cache locality and compute AABB
            _combinedResource.SortByMorton();

            if (_renderer != null)
            {
                _renderer.SetSplatResource(_combinedResource);
            }
        }

        public FoveaSplatResource GetCombinedResource() => _combinedResource;
    }
}
