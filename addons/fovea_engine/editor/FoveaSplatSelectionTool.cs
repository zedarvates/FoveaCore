using Godot;
using System;
using System.Collections.Generic;

namespace FoveaEngine
{
    public partial class FoveaSplatSelectionTool : RefCounted
    {
        public List<int> SelectedIndices { get; } = new List<int>();

        /// <summary>
        /// Selects the closest splat intersecting a ray.
        /// </summary>
        public int SelectIndividual(FoveaSplatNode3D node, Vector3 rayOrigin, Vector3 rayDirection, float maxDistance = 100f)
        {
            SelectedIndices.Clear();
            if (node == null || node.SplatResource == null) return -1;

            var pos = node.SplatResource.Positions;
            int count = node.SplatCount;
            int bestIdx = -1;
            float minRayDist = 0.2f; // Selection tolerance
            float minRayDistSq = minRayDist * minRayDist;

            Vector3 localOrigin = node.GlobalTransform.AffineInverse() * rayOrigin;
            Vector3 localDir = node.GlobalTransform.AffineInverse().Basis * rayDirection;
            localDir = localDir.Normalized();

            for (int i = 0; i < count; i++)
            {
                Vector3 p = pos[i];
                // Project position onto ray
                Vector3 toPoint = p - localOrigin;
                float t = toPoint.Dot(localDir);
                if (t < 0 || t > maxDistance) continue;

                Vector3 proj = localOrigin + localDir * t;
                float d2 = p.DistanceSquaredTo(proj);

                if (d2 < minRayDistSq)
                {
                    minRayDistSq = d2;
                    bestIdx = i;
                }
            }

            if (bestIdx != -1)
            {
                SelectedIndices.Add(bestIdx);
            }

            return bestIdx;
        }

        /// <summary>
        /// Selects all splats within a sphere of influence.
        /// </summary>
        public void SelectZone(FoveaSplatNode3D node, Vector3 center, float radius)
        {
            SelectedIndices.Clear();
            if (node == null || node.SplatResource == null) return;

            var pos = node.SplatResource.Positions;
            int count = node.SplatCount;
            Vector3 localCenter = node.GlobalTransform.AffineInverse() * center;

            float radiusSq = radius * radius;
            for (int i = 0; i < count; i++)
            {
                if (pos[i].DistanceSquaredTo(localCenter) <= radiusSq)
                {
                    SelectedIndices.Add(i);
                }
            }
        }

        /// <summary>
        /// Translates, rotates, and scales the selected group of splats.
        /// </summary>
        public void TransformSelection(FoveaSplatNode3D node, Vector3 translation, Vector3 rotationEuler, Vector3 scale)
        {
            if (node == null || node.SplatResource == null || SelectedIndices.Count == 0) return;

            var resource = node.SplatResource;
            var pos = resource.Positions;
            var rot = resource.Rotations;
            var scl = resource.Scales;

            // Calculate center of selection to rotate/scale around it
            Vector3 pivot = Vector3.Zero;
            foreach (int idx in SelectedIndices)
            {
                pivot += pos[idx];
            }
            pivot /= SelectedIndices.Count;

            Basis basis = Basis.FromEuler(rotationEuler);

            foreach (int idx in SelectedIndices)
            {
                // Translate/Scale/Rotate relative to pivot
                Vector3 localPos = pos[idx] - pivot;
                localPos = (basis * localPos) * scale;
                pos[idx] = localPos + pivot + translation;

                // Rotate orientation
                rot[idx] = (Quaternion.FromEuler(rotationEuler) * rot[idx]).Normalized();

                // Scale covariance
                scl[idx] = scl[idx] * scale;
            }

            // Sync flat rotations
            resource.Rotations = rot;
            resource.RecalculateBounds();
            
            // Trigger renderer update
            node.SplatResource = resource;
        }
    }
}
