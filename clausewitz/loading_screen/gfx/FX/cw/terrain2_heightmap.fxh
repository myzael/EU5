Includes = {
	"cw/pdx_virtual_texture_clipmap.fxh"
	"cw/terrain2_virtual_layers.fxh"
}

Sampler VirtualHeightmapLinearSampler
{
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

Sampler VirtualHeightmapPointSampler
{
	MagFilter = "Point"
	MinFilter = "Point"
	MipFilter = "Point"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

ConstantBuffer( PdxTerrain2TransformationConstants )
{
	# NOTE: The quadtree worldspace size necessarily matches the size of the virtual textures!!
	float _QuadTreeSize;
	float _InvQuadTreeSize;
	float2 _WorldSpaceToDetail;

	float2 _TerrainSize;
	float2 _InvTerrainSize;
}

Code
[[
	// TODO[TS]
	#define _WorldSpaceToTerrain0To1 _InvTerrainSize
]]

ConstantBuffer( PdxTerrain2HeightmapConstants )
{
	float _HeightScale;
	float _NormalStepSize;

	uint _GridSize;
	float _InvGridSizeMinusOne;

	float2 _InvVirtualHeightmapSize;
	float _CurvatureMapStrength;
	float _HeightmapConstantsPad0;
}

ConstantBuffer( PdxTerrain2LodConstants )
{
	float3 _LodPosition;
}

ConstantBuffer( PdxTerrain2PhysicalPageConstants )
{
	# Rectangles into the heightmap physical texture, indexed by the vertex grid instance index.
	# This is only usable in the vertex shader, as it is the only point where we have these indices.
	# Each element represents an UV rect with xy = offset and zw = size
	float4 _PhysicalPageData[4096];
}

Code
[[
	float4 SamplePhysicalHeightmap( float2 PhysicalUV )
	{
		return PdxSampleTex2DLod0( VirtualHeightmapPhysicalTexture, VirtualHeightmapLinearSampler, PhysicalUV );
	}

	float2 CalculatePhysicalUV( float2 WorldSpacePosXZ, int Lod, out uint PhysicalPageMipLevel )
	{
		float2 VirtualUV = WorldSpacePosXZ * _InvQuadTreeSize;

		SVirtualTextureSampleParameters SampleParams;
		CalculateSampleParameters( VirtualUV, Lod, VirtualHeightmapIndirectionTexture, _VirtualHeightmapConstants._ClipmapConstants, SampleParams );
		PhysicalPageMipLevel = SampleParams._IndirectionData.z;

		float2 PhysicalUV = SampleParams._PhysicalUV;

		// Heightmap sampling is a bit special since we want to sample the center of the texels at uv 0/1, this is why we do this offset here
		PhysicalUV += vec2( 0.5 ) * _VirtualHeightmapConstants._ClipmapConstants._InvPhysicalTextureSize;

		return PhysicalUV;
	}

	float3 CalculateNormal( float2 WorldSpacePosXZ, int Lod )
	{
		uint PhysicalPageMipLevel;
		float2 PhysicalUV = CalculatePhysicalUV( WorldSpacePosXZ, Lod, PhysicalPageMipLevel );

		float SampleStepSize = _NormalStepSize * ( 1u << PhysicalPageMipLevel );
		float WorldSpaceStepSize = ( SampleStepSize * _InvVirtualHeightmapSize.x ) * _QuadTreeSize;

		float2 SampleOffset = vec2( _NormalStepSize ) * _VirtualHeightmapConstants._ClipmapConstants._InvPhysicalTextureSize;
		float HeightMinX = SamplePhysicalHeightmap( PhysicalUV + float2( -SampleOffset.x, 0.0 ) ).r;
		float HeightMaxX = SamplePhysicalHeightmap( PhysicalUV + float2( SampleOffset.x, 0.0 ) ).r;

		float HeightMinZ = SamplePhysicalHeightmap( PhysicalUV + float2( 0.0, -SampleOffset.y ) ).r;
		float HeightMaxZ = SamplePhysicalHeightmap( PhysicalUV + float2( 0.0, SampleOffset.y ) ).r;

		//TODO[DvdB]: Removed normal scale, we have to check if that's okay.
		float3 Normal = float3( HeightMinX - HeightMaxX, 2.0, HeightMinZ - HeightMaxZ ) * float3( _HeightScale, WorldSpaceStepSize, _HeightScale );
		return normalize( Normal );
	}

	float4 SampleVirtualHeightmap( float2 GridPosition0To1, uint PhysicalPageDataIndex )
	{
		float2 PhysicalUV = _PhysicalPageData[PhysicalPageDataIndex].xy + GridPosition0To1 * _PhysicalPageData[PhysicalPageDataIndex].zw;
		return SamplePhysicalHeightmap( PhysicalUV );
	}

	// A version that samples the virtual heightmap by providing worldspace pos and a lod
	// This is currently used for lerping high detail heightmap to "source" heightmap
	// (This could also be accomplished by calculating _PhysicalPageData for the "source" data level and using the above function)
	float4 SampleVirtualHeightmapWS( float2 WorldSpacePosXZ, int Lod )
	{
		uint PhysicalPageMipLevel;
		float2 PhysicalUV = CalculatePhysicalUV( WorldSpacePosXZ, Lod, PhysicalPageMipLevel );
		return SamplePhysicalHeightmap( PhysicalUV );
	}
]]
