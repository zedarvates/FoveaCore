using System;

namespace FoveaEngine
{
    /// <summary>
    /// 30-bit Morton encoder used by C# splat resources. Kept Godot-free so CI can
    /// test the packing math without loading the Godot.NET SDK.
    /// </summary>
    public static class FoveaMorton
    {
        public static uint ExpandBits(uint value)
        {
            value &= 0x000003ff;
            value = (value | (value << 16)) & 0x030000ff;
            value = (value | (value << 8)) & 0x0300f00f;
            value = (value | (value << 4)) & 0x030c30c3;
            value = (value | (value << 2)) & 0x09249249;
            return value;
        }

        public static uint EncodeNormalized(float x, float y, float z)
        {
            uint ux = (uint)Math.Clamp(x * 1023.0f, 0.0f, 1023.0f);
            uint uy = (uint)Math.Clamp(y * 1023.0f, 0.0f, 1023.0f);
            uint uz = (uint)Math.Clamp(z * 1023.0f, 0.0f, 1023.0f);
            return (ExpandBits(ux) << 2) | (ExpandBits(uy) << 1) | ExpandBits(uz);
        }
    }
}
