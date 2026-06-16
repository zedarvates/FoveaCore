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

            // Re-allocate mutable resource arrays only when shape/count changes
            if (_animatedResource.Positions == null || _animatedResource.Positions.Length != maxCount)
            {
                _animatedResource.Positions = new Vector3[maxCount];
                _animatedResource.RotationsFlat = new float[maxCount * 4];
                _animatedResource.Scales = new Vector3[maxCount];
                _animatedResource.Colors = new Color[maxCount];
                _animatedResource.Opacities = new float[maxCount];
                _animatedResource.Normals = new Vector3[maxCount];
            }

            var posDest = _animatedResource.Positions;
            var rotFlatDest = _animatedResource.RotationsFlat;
            var scaleDest = _animatedResource.Scales;
            var colDest = _animatedResource.Colors;
            var opDest = _animatedResource.Opacities;
            var normDest = _animatedResource.Normals;

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
                    posDest[i] = posA[i].Lerp(posB[i], t);
                    
                    Quaternion r = rotA[i].Slerp(rotB[i], t);
                    rotFlatDest[i * 4] = r.X;
                    rotFlatDest[i * 4 + 1] = r.Y;
                    rotFlatDest[i * 4 + 2] = r.Z;
                    rotFlatDest[i * 4 + 3] = r.W;

                    scaleDest[i] = scaleA[i].Lerp(scaleB[i], t);
                    colDest[i] = colA[i].Lerp(colB[i], t);
                    opDest[i] = Mathf.Lerp(opA[i], opB[i], t);
                    normDest[i] = r * Vector3.Forward;
                }
                else if (i < countA) // Fade out remaining splats from cloud A
                {
                    posDest[i] = posA[i];
                    
                    Quaternion r = rotA[i];
                    rotFlatDest[i * 4] = r.X;
                    rotFlatDest[i * 4 + 1] = r.Y;
                    rotFlatDest[i * 4 + 2] = r.Z;
                    rotFlatDest[i * 4 + 3] = r.W;

                    scaleDest[i] = scaleA[i];
                    colDest[i] = colA[i];
                    opDest[i] = Mathf.Lerp(opA[i], 0f, t);
                    normDest[i] = r * Vector3.Forward;
                }
                else // Fade in remaining splats from cloud B
                {
                    posDest[i] = posB[i];
                    
                    Quaternion r = rotB[i];
                    rotFlatDest[i * 4] = r.X;
                    rotFlatDest[i * 4 + 1] = r.Y;
                    rotFlatDest[i * 4 + 2] = r.Z;
                    rotFlatDest[i * 4 + 3] = r.W;

                    scaleDest[i] = scaleB[i];
                    colDest[i] = colB[i];
                    opDest[i] = Mathf.Lerp(0f, opB[i], t);
                    normDest[i] = r * Vector3.Forward;
                }
            }

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
