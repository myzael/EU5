
# This is the default biome implementation where biomes are static and authored in a biomes.png
# For game projects that don't want this static biome behavior simply override this file with your own implementation
# Be mindful of changes to this file as some changes may be breaking changes to projects that override it.

Includes = {
	"cw/terrain.fxh"
}

Texture BiomesTexture
{
	Ref = PdxTerrain2BiomesTexture
}

Code
[[
	int GetBiomeWorldspace( float2 WorldSpacePosXZ )
	{
		float2 VirtualUV = WorldSpacePosXZ * _InvTerrainSize;
		float2 BiomesTextureSize;
		PdxTexture2DSize( BiomesTexture, BiomesTextureSize );
		return (int)(PdxTexture2DLoad( BiomesTexture, BiomesTextureSize * VirtualUV, 0 ).r * 255.0);
	}
	int GetBiomeWorldspace( float2 WorldSpacePosXZ, int MaterialIndex )
	{
		return GetBiomeWorldspace( WorldSpacePosXZ );
	}
]]
