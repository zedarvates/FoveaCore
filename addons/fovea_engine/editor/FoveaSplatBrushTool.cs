using Godot;
using System;
using System.Collections.Generic;

namespace FoveaEngine
{
    public partial class FoveaSplatBrushTool : RefCounted
    {
        public float BrushRadius { get; set; } = 1.0f;
        public float BrushStrength { get; set; } = 0.5f;
        public Color PaintColor { get; set; } = Colors.Red;

        /// <summary>
        /// Paints color onto splats within the brush radius.
        /// </summary>
        public void Paint(FoveaSplatNode3D node, Vector3 brushPosWorld)
        {
            if (node == null || node.SplatResource == null) return;

            var resource = node.SplatResource;
            var pos = resource.Positions;
            var col = resource.Colors;
            int count = node.SplatCount;

            Vector3 localBrushPos = node.GlobalTransform.AffineInverse() * brushPosWorld;

            for (int i = 0; i < count; i++)
            {
                float d = pos[i].DistanceTo(localBrushPos);
                if (d <= BrushRadius)
                {
                    // Falloff factor based on distance
                    float factor = (1.0f - (d / BrushRadius)) * BrushStrength;
                    col[i] = col[i].Lerp(PaintColor, factor);
                }
            }

            node.SplatResource = resource; // Update
        }

        /// <summary>
        /// Sculpts density by either erasing (add = false) or spawning new splats (add = true).
        /// </summary>
        public void SculptDensity(FoveaSplatNode3D node, Vector3 brushPosWorld, bool add)
        {
            if (node == null || node.SplatResource == null) return;

            var resource = node.SplatResource;
            var pos = resource.Positions;
            var op = resource.Opacities;
            int count = node.SplatCount;

            Vector3 localBrushPos = node.GlobalTransform.AffineInverse() * brushPosWorld;

            if (add)
            {
                // Spawn new splats procedurally inside the brush volume
                var rand = new Random();
                int spawnCount = (int)(10 * BrushStrength);
                if (spawnCount <= 0) spawnCount = 1;

                var newPos = new List<Vector3>(pos);
                var newRot = new List<Quaternion>(resource.Rotations);
                var newScl = new List<Vector3>(resource.Scales);
                var newCol = new List<Color>(resource.Colors);
                var newOp = new List<float>(op);
                var newNorm = new List<Vector3>(resource.Normals);

                for (int i = 0; i < spawnCount; i++)
                {
                    float theta = (float)rand.NextDouble() * Mathf.Tau;
                    float phi = Mathf.Acos((float)(2.0 * rand.NextDouble() - 1.0));
                    float r = (float)rand.NextDouble() * BrushRadius;

                    float dx = r * Mathf.Sin(phi) * Mathf.Cos(theta);
                    float dy = r * Mathf.Sin(phi) * Mathf.Sin(theta);
                    float dz = r * Mathf.Cos(phi);

                    newPos.Add(localBrushPos + new Vector3(dx, dy, dz));
                    newRot.Add(Quaternion.Identity);
                    newScl.Add(new Vector3(0.05f, 0.05f, 0.05f));
                    newCol.Add(PaintColor);
                    newOp.Add(0.8f);
                    newNorm.Add(Vector3.Forward);
                }

                resource.Positions = newPos.ToArray();
                resource.Rotations = newRot.ToArray();
                resource.Scales = newScl.ToArray();
                resource.Colors = newCol.ToArray();
                resource.Opacities = newOp.ToArray();
                resource.Normals = newNorm.ToArray();
            }
            else
            {
                // Erase: lower opacity or prune
                var activeIndices = new List<int>();
                for (int i = 0; i < count; i++)
                {
                    float d = pos[i].DistanceTo(localBrushPos);
                    if (d <= BrushRadius)
                    {
                        float factor = (1.0f - (d / BrushRadius)) * BrushStrength;
                        op[i] = Math.Max(0.0f, op[i] - factor);
                    }

                    // Keep splats that are still visible
                    if (op[i] > 0.02f)
                    {
                        activeIndices.Add(i);
                    }
                }

                int newCount = activeIndices.Count;
                if (newCount != count)
                {
                    var newPos = new Vector3[newCount];
                    var newRot = new Quaternion[newCount];
                    var newScl = new Vector3[newCount];
                    var newCol = new Color[newCount];
                    var newOp = new float[newCount];
                    var newNorm = new Vector3[newCount];

                    var origRot = resource.Rotations;
                    bool hasNorm = resource.Normals != null && resource.Normals.Length == count;

                    for (int i = 0; i < newCount; i++)
                    {
                        int src = activeIndices[i];
                        newPos[i] = pos[src];
                        newRot[i] = origRot[src];
                        newScl[i] = resource.Scales[src];
                        newCol[i] = resource.Colors[src];
                        newOp[i] = op[src];
                        if (hasNorm) newNorm[i] = resource.Normals[src];
                    }

                    resource.Positions = newPos;
                    resource.Rotations = newRot;
                    resource.Scales = newScl;
                    resource.Colors = newCol;
                    resource.Opacities = newOp;
                    resource.Normals = newNorm;
                }
            }

            resource.RecalculateBounds();
            node.SplatResource = resource;
        }

        /// <summary>
        /// Recalibrates splat orientations (rotations) using neighbor variance distribution.
        /// </summary>
        public void RecalibrateCovariance(FoveaSplatNode3D node, Vector3 brushPosWorld)
        {
            if (node == null || node.SplatResource == null) return;

            var resource = node.SplatResource;
            var pos = resource.Positions;
            var rot = resource.Rotations;
            int count = node.SplatCount;

            Vector3 localBrushPos = node.GlobalTransform.AffineInverse() * brushPosWorld;

            // Find all indices inside brush
            var inBrush = new List<int>();
            for (int i = 0; i < count; i++)
            {
                if (pos[i].DistanceTo(localBrushPos) <= BrushRadius)
                {
                    inBrush.Add(i);
                }
            }

            if (inBrush.Count < 3) return;

            // Compute local mean position
            Vector3 mean = Vector3.Zero;
            foreach (int idx in inBrush) mean += pos[idx];
            mean /= inBrush.Count;

            // Recalibrate covariance: align orientation Z to point away from mean (simple approximation)
            foreach (int idx in inBrush)
            {
                Vector3 toMean = (pos[idx] - mean).Normalized();
                if (toMean.LengthSquared() > 0.01f)
                {
                    Vector3 up = Vector3.Up;
                    if (Math.Abs(toMean.Dot(up)) > 0.9f)
                    {
                        up = Vector3.Right;
                    }
                    rot[idx] = Quaternion.FromEuler(Basis.LookingAt(toMean, up).GetEuler());
                }
            }

            resource.Rotations = rot;
            node.SplatResource = resource;
        }

        /// <summary>
        /// Merges splats that are close together into a single averaged splat.
        /// </summary>
        public void MergeClusters(FoveaSplatNode3D node, Vector3 brushPosWorld)
        {
            if (node == null || node.SplatResource == null) return;

            var resource = node.SplatResource;
            var pos = resource.Positions;
            int count = node.SplatCount;

            Vector3 localBrushPos = node.GlobalTransform.AffineInverse() * brushPosWorld;

            var inBrush = new List<int>();
            var outsideBrush = new List<int>();

            for (int i = 0; i < count; i++)
            {
                if (pos[i].DistanceTo(localBrushPos) <= BrushRadius)
                {
                    inBrush.Add(i);
                }
                else
                {
                    outsideBrush.Add(i);
                }
            }

            // Need at least 2 splats to merge
            if (inBrush.Count < 2) return;

            // Compute averages
            Vector3 avgPos = Vector3.Zero;
            Quaternion avgRot = Quaternion.Identity; // Standard average
            Vector3 avgScl = Vector3.Zero;
            Color avgCol = Colors.Black;
            float avgOp = 0f;

            var rot = resource.Rotations;
            var scl = resource.Scales;
            var col = resource.Colors;
            var op = resource.Opacities;

            foreach (int idx in inBrush)
            {
                avgPos += pos[idx];
                avgScl += scl[idx];
                avgCol += col[idx];
                avgOp += op[idx];
            }

            avgPos /= inBrush.Count;
            avgScl /= inBrush.Count;
            avgCol /= inBrush.Count;
            avgOp /= inBrush.Count;

            // Rotation average (simple slerp cascade)
            if (inBrush.Count > 0)
            {
                avgRot = rot[inBrush[0]];
                for (int i = 1; i < inBrush.Count; i++)
                {
                    avgRot = avgRot.Slerp(rot[inBrush[i]], 1.0f / (i + 1));
                }
            }

            // Create new arrays
            int newCount = outsideBrush.Count + 1;
            var newPos = new Vector3[newCount];
            var newRot = new Quaternion[newCount];
            var newScl = new Vector3[newCount];
            var newCol = new Color[newCount];
            var newOp = new float[newCount];
            var newNorm = new Vector3[newCount];

            for (int i = 0; i < outsideBrush.Count; i++)
            {
                int src = outsideBrush[i];
                newPos[i] = pos[src];
                newRot[i] = rot[src];
                newScl[i] = scl[src];
                newCol[i] = col[src];
                newOp[i] = op[src];
                newNorm[i] = resource.Normals[src];
            }

            // Append merged splat at the end
            int lastIdx = newCount - 1;
            newPos[lastIdx] = avgPos;
            newRot[lastIdx] = avgRot;
            newScl[lastIdx] = avgScl;
            newCol[lastIdx] = avgCol;
            newOp[lastIdx] = avgOp;
            newNorm[lastIdx] = avgRot * Vector3.Forward;

            resource.Positions = newPos;
            resource.Rotations = newRot;
            resource.Scales = newScl;
            resource.Colors = newCol;
            resource.Opacities = newOp;
            resource.Normals = newNorm;

            resource.RecalculateBounds();
            node.SplatResource = resource;
        }
    }
}
