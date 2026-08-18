using Xunit;

namespace FoveaEngine.Tests;

public class FoveaMortonTests
{
    [Fact]
    public void EncodeNormalized_MapsKnownBounds()
    {
        Assert.Equal(0u, FoveaMorton.EncodeNormalized(0f, 0f, 0f));
        Assert.Equal(0x3fffffffu, FoveaMorton.EncodeNormalized(1f, 1f, 1f));
    }

    [Fact]
    public void EncodeNormalized_ClampsOutOfRangeAxes()
    {
        Assert.Equal(
            FoveaMorton.EncodeNormalized(0f, 0f, 1f),
            FoveaMorton.EncodeNormalized(-8f, -3f, 4f)
        );
    }

    [Fact]
    public void EncodeNormalized_InterleavesExpandedBits()
    {
        const uint x = 1;
        const uint y = 2;
        const uint z = 3;
        uint expected =
            (FoveaMorton.ExpandBits(x) << 2) |
            (FoveaMorton.ExpandBits(y) << 1) |
            FoveaMorton.ExpandBits(z);
        Assert.Equal(expected, FoveaMorton.EncodeNormalized(x / 1023f, y / 1023f, z / 1023f));
    }
}
