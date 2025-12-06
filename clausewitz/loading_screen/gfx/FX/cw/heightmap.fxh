# This file simply exists to redirect to terrain2 heightmap.fxh.
# heightmap.fxh implements things required by both backends.
Includes = {
	"cw/terrain2_heightmap.fxh"
	"cw/terrain2_utils.fxh"
}

Code
[[
	// Functions that required for system that depend on the old terrain to "work" with terrain2.

	// This is required for the mapeditor.shader but we don't have an implementation for this in terrain2.
	float4 SampleLookupTexture( float2 LookupCoordinates )
	{
		return vec4( 0.0 );
	}

	float2 WorldSpaceToTerrain01( float2 WorldSpaceXZ )
	{
		return WorldSpaceXZ * _InvTerrainSize;
	}

	float2 GetLookupCoordinates( float2 WorldSpacePosXZ )
	{
		return clamp( WorldSpaceToTerrain01( WorldSpacePosXZ ), vec2( 0.0 ), vec2( 0.999999 ) );
	}

	// This is required for the mapeditor.shader and TerrainDebug but we don't have an implementation for this in terrain2.
	float2 GetHeightMapCoordinates( float2 WorldSpacePosXZ )
	{
		return WorldSpacePosXZ;
	}

	float GetHeightScale()
	{
		return _HeightScale;
	}

	float GetHeight01( float2 WorldSpacePosXZ )
	{
		#ifdef TERRAIN_DISABLED
			return 0.0f;
		#else		
			// Wrap world space position along the X direction and clamp along the Z direction
			float OutsideBoundsX = floor( WorldSpacePosXZ.x * _InvTerrainSize.x );
			WorldSpacePosXZ.x -= OutsideBoundsX * _TerrainSize.x;
			WorldSpacePosXZ.y = clamp( WorldSpacePosXZ.y, 0, _TerrainSize.y );

			uint Lod = (uint)CalculateVirtualLayerDistanceMip( float3( WorldSpacePosXZ.x, 0, WorldSpacePosXZ.y ), _VirtualHeightmapConstants );
			return SampleVirtualHeightmapWS( WorldSpacePosXZ, Lod ).r;
		#endif
	}

	float GetHeight( float2 WorldSpacePosXZ )
	{
		#ifdef TERRAIN_DISABLED
			return 0.0f;
		#else
			return GetHeight01( WorldSpacePosXZ ) * GetHeightScale();
		#endif
	}

	float GetHeightMultisample01( float2 WorldSpacePosXZ, float FilterSize )
	{
		#ifdef TERRAIN_DISABLED
			return 0.0f;
		#else
			float2 HeightmapToWorld = _TerrainSize * _VirtualHeightmapConstants._ClipmapConstants._InvVirtualTextureSize;
			float2 FilterSizeInWorldSpace = FilterSize * HeightmapToWorld;

			float Height = 0.0;
			Height += GetHeight01( WorldSpacePosXZ );
			Height += GetHeight01( WorldSpacePosXZ + float2( -FilterSizeInWorldSpace.x, 0 ) );
			Height += GetHeight01( WorldSpacePosXZ + float2( 0, -FilterSizeInWorldSpace.y ) );
			Height += GetHeight01( WorldSpacePosXZ + float2( FilterSizeInWorldSpace.x, 0 ) );
			Height += GetHeight01( WorldSpacePosXZ + float2( 0, FilterSizeInWorldSpace.y ) );
			Height += GetHeight01( WorldSpacePosXZ + float2( -FilterSizeInWorldSpace.x, -FilterSizeInWorldSpace.y ) );
			Height += GetHeight01( WorldSpacePosXZ + float2(  FilterSizeInWorldSpace.x, -FilterSizeInWorldSpace.y ) );
			Height += GetHeight01( WorldSpacePosXZ + float2(  FilterSizeInWorldSpace.x,  FilterSizeInWorldSpace.y ) );
			Height += GetHeight01( WorldSpacePosXZ + float2( -FilterSizeInWorldSpace.x,  FilterSizeInWorldSpace.y ) );

			Height /= 9.0;
			return Height;
		#endif
	}

	float GetHeightMultisample( float2 WorldSpacePosXZ, float FilterSize )
	{
		#ifdef TERRAIN_DISABLED
			return 0.0f;
		#else
			return GetHeightMultisample01( WorldSpacePosXZ, FilterSize ) * GetHeightScale();
		#endif
	}
]]
