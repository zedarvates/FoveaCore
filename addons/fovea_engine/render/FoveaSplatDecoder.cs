using Godot;
using System;
using System.Threading.Tasks;

namespace FoveaEngine
{
    public static class FoveaSplatDecoder
    {
        public static void DecodeParallel(
            byte[] culledBytes,
            int numSplats,
            Vector3 aabbMin,
            Vector3 aabbMax,
            Vector3[] xfArray,
            Color[] cdArray,
            Transform3D[] originalTransforms)
        {
            float rangeX = Math.Max(aabbMax.X - aabbMin.X, 0.001f);
            float rangeY = Math.Max(aabbMax.Y - aabbMin.Y, 0.001f);
            float rangeZ = Math.Max(aabbMax.Z - aabbMin.Z, 0.001f);

            Parallel.For(0, numSplats, i =>
            {
                int src = i * 16;

                // Decode quantized 16-bit position -> float world space
                ushort qxRaw = BitConverter.ToUInt16(culledBytes, src);
                ushort qyRaw = BitConverter.ToUInt16(culledBytes, src + 2);
                ushort qzRaw = BitConverter.ToUInt16(culledBytes, src + 4);

                float qx = qxRaw / 65535.0f;
                float qy = qyRaw / 65535.0f;
                float qz = qzRaw / 65535.0f;

                float px = aabbMin.X + qx * rangeX;
                float py = aabbMin.Y + qy * rangeY;
                float pz = aabbMin.Z + qz * rangeZ;

                Vector3 worldPos = new Vector3(px, py, pz);
                Vector3 basisX = Vector3.Right;
                Vector3 basisY = Vector3.Up;
                Vector3 basisZ = Vector3.Back;

                // PackedVector3Array layout: 4 Vector3 per instance
                int xfOff = i * 4;
                xfArray[xfOff] = basisX;
                xfArray[xfOff + 1] = basisY;
                xfArray[xfOff + 2] = basisZ;
                xfArray[xfOff + 3] = worldPos;

                // Re-interpret the raw 32-bit floats for the shader Custom Data
                float r = BitConverter.ToSingle(culledBytes, src);
                float g = BitConverter.ToSingle(culledBytes, src + 4);
                float b = BitConverter.ToSingle(culledBytes, src + 8);
                float a = BitConverter.ToSingle(culledBytes, src + 12);

                cdArray[i] = new Color(r, g, b, a);

                if (originalTransforms != null)
                {
                    originalTransforms[i] = new Transform3D(new Basis(basisX, basisY, basisZ), worldPos);
                }
            });
        }
    }
}
