using Godot;
using System;
using System.Collections.Generic;

namespace FoveaEngine
{
    [GlobalClass]
    public partial class FoveaSplatResource : Resource
    {
        [Export]
        public Vector3[] Positions { get; set; } = Array.Empty<Vector3>();

        private float[] _rotationsFlat = Array.Empty<float>();
        private Quaternion[] _rotationsCache = null;
        private bool _cacheDirty = true;

        [Export]
        public float[] RotationsFlat
        {
            get => _rotationsFlat;
            set
            {
                _rotationsFlat = value;
                _cacheDirty = true;
            }
        }

        [Export]
        public Vector3[] Scales { get; set; } = Array.Empty<Vector3>();

        [Export]
        public Color[] Colors { get; set; } = Array.Empty<Color>();

        [Export]
        public float[] Opacities { get; set; } = Array.Empty<float>();

        [Export]
        public Vector3[] Normals { get; set; } = Array.Empty<Vector3>();

        [Export]
        public byte[] LayerTypes { get; set; } = Array.Empty<byte>();

        [Export]
        public byte[] DitherSeeds { get; set; } = Array.Empty<byte>();

        [Export]
        public byte[] BrushTypes { get; set; } = Array.Empty<byte>();

        [Export]
        public Aabb BBox { get; set; } = new Aabb();

        public int SplatCount => Positions?.Length ?? 0;

        public Quaternion[] Rotations
        {
            get
            {
                if (_cacheDirty || _rotationsCache == null || _rotationsCache.Length != _rotationsFlat.Length / 4)
                {
                    int count = _rotationsFlat.Length / 4;
                    _rotationsCache = new Quaternion[count];
                    for (int i = 0; i < count; i++)
                    {
                        _rotationsCache[i] = new Quaternion(
                            _rotationsFlat[i * 4],
                            _rotationsFlat[i * 4 + 1],
                            _rotationsFlat[i * 4 + 2],
                            _rotationsFlat[i * 4 + 3]
                        );
                    }
                    _cacheDirty = false;
                }
                return _rotationsCache;
            }
            set
            {
                _rotationsCache = value;
                _rotationsFlat = new float[value.Length * 4];
                for (int i = 0; i < value.Length; i++)
                {
                    _rotationsFlat[i * 4] = value[i].X;
                    _rotationsFlat[i * 4 + 1] = value[i].Y;
                    _rotationsFlat[i * 4 + 2] = value[i].Z;
                    _rotationsFlat[i * 4 + 3] = value[i].W;
                }
                _cacheDirty = false;
            }
        }

        public Quaternion GetRotation(int index)
        {
            int offset = index * 4;
            if (_rotationsFlat != null && offset + 3 < _rotationsFlat.Length)
            {
                return new Quaternion(
                    _rotationsFlat[offset],
                    _rotationsFlat[offset + 1],
                    _rotationsFlat[offset + 2],
                    _rotationsFlat[offset + 3]
                );
            }
            return Quaternion.Identity;
        }

        public void SetRotation(int index, Quaternion q)
        {
            int offset = index * 4;
            if (_rotationsFlat != null && offset + 3 < _rotationsFlat.Length)
            {
                _rotationsFlat[offset] = q.X;
                _rotationsFlat[offset + 1] = q.Y;
                _rotationsFlat[offset + 2] = q.Z;
                _rotationsFlat[offset + 3] = q.W;
                _cacheDirty = true;
            }
        }

        /// <summary>
        /// Recalculates the bounding box (Aabb) of the splat cloud.
        /// </summary>
        public void RecalculateBounds()
        {
            if (Positions == null || Positions.Length == 0)
            {
                BBox = new Aabb();
                return;
            }

            Vector3 min = Positions[0];
            Vector3 max = Positions[0];

            for (int i = 1; i < Positions.Length; i++)
            {
                Vector3 p = Positions[i];
                min = new Vector3(
                    Math.Min(min.X, p.X),
                    Math.Min(min.Y, p.Y),
                    Math.Min(min.Z, p.Z)
                );
                max = new Vector3(
                    Math.Max(max.X, p.X),
                    Math.Max(max.Y, p.Y),
                    Math.Max(max.Z, p.Z)
                );
            }

            // Add small margins to prevent zero volume
            min -= new Vector3(0.1f, 0.1f, 0.1f);
            max += new Vector3(0.1f, 0.1f, 0.1f);

            BBox = new Aabb(min, max - min);
        }

        public static uint CalculateMorton3D(float x, float y, float z)
        {
            return FoveaMorton.EncodeNormalized(x, y, z);
        }

        /// <summary>
        /// Sorts all splat data based on 30-bit Morton codes for improved cache locality.
        /// </summary>
        public void SortByMorton()
        {
            int count = SplatCount;
            if (count <= 1) return;

            RecalculateBounds();
            Vector3 size = BBox.Size;
            if (size.X <= 0) size.X = 0.001f;
            if (size.Y <= 0) size.Y = 0.001f;
            if (size.Z <= 0) size.Z = 0.001f;

            var items = new List<Tuple<uint, int>>(count);
            for (int i = 0; i < count; i++)
            {
                Vector3 localPos = (Positions[i] - BBox.Position) / size;
                uint code = CalculateMorton3D(localPos.X, localPos.Y, localPos.Z);
                items.Add(new Tuple<uint, int>(code, i));
            }

            // Sort by Morton code
            items.Sort((a, b) => a.Item1.CompareTo(b.Item1));

            // Rearrange arrays
            var newPositions = new Vector3[count];
            var newRotationsFlat = new float[count * 4];
            var newScales = new Vector3[count];
            var newColors = new Color[count];
            var newOpacities = new float[count];
            var newNormals = new Vector3[count];
            var newLayerTypes = new byte[count];
            var newDitherSeeds = new byte[count];
            var newBrushTypes = new byte[count];

            bool hasNormals = Normals != null && Normals.Length == count;
            bool hasRotations = RotationsFlat != null && RotationsFlat.Length == count * 4;
            bool hasScales = Scales != null && Scales.Length == count;
            bool hasColors = Colors != null && Colors.Length == count;
            bool hasOpacities = Opacities != null && Opacities.Length == count;
            bool hasLayers = LayerTypes != null && LayerTypes.Length == count;
            bool hasDithers = DitherSeeds != null && DitherSeeds.Length == count;
            bool hasBrushes = BrushTypes != null && BrushTypes.Length == count;

            for (int i = 0; i < count; i++)
            {
                int srcIdx = items[i].Item2;
                newPositions[i] = Positions[srcIdx];

                if (hasRotations)
                {
                    newRotationsFlat[i * 4]     = RotationsFlat[srcIdx * 4];
                    newRotationsFlat[i * 4 + 1] = RotationsFlat[srcIdx * 4 + 1];
                    newRotationsFlat[i * 4 + 2] = RotationsFlat[srcIdx * 4 + 2];
                    newRotationsFlat[i * 4 + 3] = RotationsFlat[srcIdx * 4 + 3];
                }

                if (hasScales)   newScales[i]   = Scales[srcIdx];
                if (hasColors)   newColors[i]   = Colors[srcIdx];
                if (hasOpacities) newOpacities[i] = Opacities[srcIdx];
                if (hasNormals)  newNormals[i]  = Normals[srcIdx];
                if (hasLayers)   newLayerTypes[i] = LayerTypes[srcIdx];
                if (hasDithers)  newDitherSeeds[i] = DitherSeeds[srcIdx];
                if (hasBrushes)  newBrushTypes[i] = BrushTypes[srcIdx];
            }

            Positions = newPositions;
            RotationsFlat = newRotationsFlat;
            Scales = newScales;
            Colors = newColors;
            Opacities = newOpacities;
            if (hasNormals) Normals = newNormals;
            if (hasLayers) LayerTypes = newLayerTypes;
            if (hasDithers) DitherSeeds = newDitherSeeds;
            if (hasBrushes) BrushTypes = newBrushTypes;
        }
    }
}
