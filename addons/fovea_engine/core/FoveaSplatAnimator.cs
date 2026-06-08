using Godot;
using System;
using System.Collections.Generic;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatAnimator : Node
    {
        [Export]
        public FoveaSplatNode3D TargetNode { get; set; }

        [ExportGroup("Morphing")]
        [Export]
        public FoveaSplatResource MorphTargetResource { get; set; }

        [Export(PropertyHint.Range, "0.0,1.0")]
        public float MorphProgress
        {
            get => _morphProgress;
            set
            {
                _morphProgress = value;
                ApplyMorph();
            }
        }

        [ExportGroup("Path Animation")]
        [Export]
        public Path3D PathNode { get; set; }

        [Export]
        public float PathSpeed { get; set; } = 1.0f;

        [Export]
        public bool LoopPath { get; set; } = true;

        [ExportGroup("Skeletal Animation")]
        [Export]
        public Skeleton3D Skeleton { get; set; }

        private float _morphProgress = 0.0f;
        private FoveaSplatResource _baseResource;
        private FoveaSplatResource _animatedResource;
        private float _pathProgress = 0.0f;

        // Skeletal skinning weights cache: SplatIndex -> (BoneIndex, Weight)
        private struct BoneWeight
        {
            public int BoneIdx;
            public float Weight;
        }
        private BoneWeight[] _splatBoneWeights;

        public override void _Ready()
        {
            if (TargetNode != null && TargetNode.SplatResource != null)
            {
                SetBaseResource(TargetNode.SplatResource);
            }
        }

        public override void _Process(double delta)
        {
            if (PathNode != null && TargetNode != null)
            {
                AnimatePath((float)delta);
            }

            if (Skeleton != null && TargetNode != null && _baseResource != null)
            {
                AnimateSkeleton();
            }
        }

        public void SetBaseResource(FoveaSplatResource resource)
        {
            _baseResource = resource;
            // Clone base resource to create a mutable animated instance
            _animatedResource = new FoveaSplatResource
            {
                Positions = (Vector3[])_baseResource.Positions.Clone(),
                RotationsFlat = (float[])_baseResource.RotationsFlat.Clone(),
                Scales = (Vector3[])_baseResource.Scales.Clone(),
                Colors = (Color[])_baseResource.Colors.Clone(),
                Opacities = (float[])_baseResource.Opacities.Clone(),
                Normals = (Vector3[])_baseResource.Normals.Clone(),
                BBox = _baseResource.BBox
            };

            if (Skeleton != null)
            {
                CalculateSkinningWeights();
            }
        }

        private void ApplyMorph()
        {
            if (TargetNode == null || _baseResource == null || MorphTargetResource == null) return;

            int countA = _baseResource.SplatCount;
            int countB = MorphTargetResource.SplatCount;
            int maxCount = Math.Max(countA, countB);

            var morphPositions = new Vector3[maxCount];
            var morphRotations = new Quaternion[maxCount];
            var morphScales = new Vector3[maxCount];
            var morphColors = new Color[maxCount];
            var morphOpacities = new float[maxCount];

            var posA = _baseResource.Positions;
            var rotA = _baseResource.Rotations;
            var scaleA = _baseResource.Scales;
            var colA = _baseResource.Colors;
            var opA = _baseResource.Opacities;

            var posB = MorphTargetResource.Positions;
            var rotB = MorphTargetResource.Rotations;
            var scaleB = MorphTargetResource.Scales;
            var colB = MorphTargetResource.Colors;
            var opB = MorphTargetResource.Opacities;

            float t = _morphProgress;

            for (int i = 0; i < maxCount; i++)
            {
                if (i < countA && i < countB)
                {
                    morphPositions[i] = posA[i].Lerp(posB[i], t);
                    morphRotations[i] = rotA[i].Slerp(rotB[i], t);
                    morphScales[i] = scaleA[i].Lerp(scaleB[i], t);
                    morphColors[i] = colA[i].Lerp(colB[i], t);
                    morphOpacities[i] = Mathf.Lerp(opA[i], opB[i], t);
                }
                else if (i < countA) // Fade out remaining splats from cloud A
                {
                    morphPositions[i] = posA[i];
                    morphRotations[i] = rotA[i];
                    morphScales[i] = scaleA[i];
                    morphColors[i] = colA[i];
                    morphOpacities[i] = Mathf.Lerp(opA[i], 0f, t);
                }
                else // Fade in remaining splats from cloud B
                {
                    morphPositions[i] = posB[i];
                    morphRotations[i] = rotB[i];
                    morphScales[i] = scaleB[i];
                    morphColors[i] = colB[i];
                    morphOpacities[i] = Mathf.Lerp(0f, opB[i], t);
                }
            }

            _animatedResource.Positions = morphPositions;
            _animatedResource.Rotations = morphRotations;
            _animatedResource.Scales = morphScales;
            _animatedResource.Colors = morphColors;
            _animatedResource.Opacities = morphOpacities;
            _animatedResource.RecalculateBounds();

            TargetNode.SplatResource = _animatedResource;
        }

        private void AnimatePath(float delta)
        {
            var curve = PathNode.Curve;
            if (curve == null) return;

            float pathLength = curve.GetBakedLength();
            if (pathLength <= 0) return;

            _pathProgress += PathSpeed * delta;
            if (_pathProgress > pathLength)
            {
                if (LoopPath) _pathProgress = _pathProgress % pathLength;
                else _pathProgress = pathLength;
            }

            Transform3D pathTrans = curve.SampleBackup(TargetNode.GlobalTransform, _pathProgress);
            TargetNode.GlobalTransform = pathTrans;
        }

        private void CalculateSkinningWeights()
        {
            if (Skeleton == null || _baseResource == null) return;

            int count = _baseResource.SplatCount;
            _splatBoneWeights = new BoneWeight[count];

            int boneCount = Skeleton.GetBoneCount();
            if (boneCount == 0) return;

            var pos = _baseResource.Positions;

            for (int i = 0; i < count; i++)
            {
                Vector3 splatPos = pos[i];
                int bestBone = 0;
                float minDist = float.MaxValue;

                // Simple nearest-bone skinning mapping
                for (int b = 0; b < boneCount; b++)
                {
                    Transform3D boneTrans = Skeleton.GetBoneGlobalPose(b);
                    float d = splatPos.DistanceTo(boneTrans.Origin);
                    if (d < minDist)
                    {
                        minDist = d;
                        bestBone = b;
                    }
                }

                _splatBoneWeights[i] = new BoneWeight { BoneIdx = bestBone, Weight = 1.0f };
            }
        }

        private void AnimateSkeleton()
        {
            if (Skeleton == null || TargetNode == null || _baseResource == null || _animatedResource == null) return;

            int count = _baseResource.SplatCount;
            if (_splatBoneWeights == null || _splatBoneWeights.Length != count)
            {
                CalculateSkinningWeights();
            }

            var origPos = _baseResource.Positions;
            var animPos = _animatedResource.Positions;

            for (int i = 0; i < count; i++)
            {
                BoneWeight bw = _splatBoneWeights[i];
                Transform3D boneTrans = Skeleton.GetBoneGlobalPose(bw.BoneIdx);
                // Apply skeletal transformation
                animPos[i] = boneTrans * origPos[i];
            }

            _animatedResource.RecalculateBounds();
            TargetNode.SplatResource = _animatedResource;
        }
    }

    public static class PathCurveExtensions
    {
        public static Transform3D SampleBackup(this Curve3D curve, Transform3D currentTrans, float offset)
        {
            Vector3 pos = curve.SampleBaked(offset);
            Vector3 nextPos = curve.SampleBaked(offset + 0.1f);
            Vector3 dir = (nextPos - pos).Normalized();
            
            Vector3 up = Vector3.Up;
            if (Math.Abs(dir.Dot(up)) > 0.9f)
            {
                up = Vector3.Right;
            }

            var result = new Transform3D(Basis.LookingAt(dir, up), pos);
            return result;
        }
    }
}
