# This file simply exists to redirect to terrain2 terrain.fxh.
# terrain.fxh implements things required by both backends.
Includes = {
	"cw/terrain2_materials.fxh"
	"cw/heightmap.fxh"
}

Code
[[
	float3 CalculateNormal( float2 WorldSpacePosXZ )
	{
	#ifdef TERRAIN_WRAP_X
		float TerrainSizeX = _TerrainSize.x;

		float HeightMinX = GetHeight01( float2( mod( WorldSpacePosXZ.x + TerrainSizeX - _NormalStepSize, TerrainSizeX ), WorldSpacePosXZ.y ) );
		float HeightMaxX = GetHeight01( float2( mod( WorldSpacePosXZ.x + TerrainSizeX + _NormalStepSize, TerrainSizeX ), WorldSpacePosXZ.y ) );
	#else
		float HeightMinX = GetHeight01( WorldSpacePosXZ + float2(-_NormalStepSize, 0) );
		float HeightMaxX = GetHeight01( WorldSpacePosXZ + float2(_NormalStepSize, 0) );
	#endif
		float HeightMinZ = GetHeight01( WorldSpacePosXZ + float2(0, -_NormalStepSize) );
		float HeightMaxZ = GetHeight01( WorldSpacePosXZ + float2(0, _NormalStepSize) );

		float3 Normal = float3( HeightMinX - HeightMaxX, 2.0, HeightMinZ - HeightMaxZ );
		return normalize(Normal);
	}

	// Rotates normals to the heightmap terrain normal
	float3 SimpleRotateNormalToTerrain( float3 Normal, float2 WorldSpacePosXZ )
	{
		float3 TerrainNormal = CalculateNormal( WorldSpacePosXZ );
		float3 Up = float3( 0.0, 1.0, 0.0 );

		float3 Axis = cross( Up, TerrainNormal );
		float Angle = acos( dot( Up, TerrainNormal ) ) * abs( Normal.y );

		return lerp( dot( Axis, Normal ) * Axis, Normal, cos( Angle ) ) + cross( Axis, Normal ) * sin( Angle );
	}
]]
