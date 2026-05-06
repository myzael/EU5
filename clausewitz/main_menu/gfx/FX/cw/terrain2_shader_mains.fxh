Includes = {
	"cw/terrain.fxh"
	"cw/terrain2_utils.fxh"

	"jomini/jomini_lighting.fxh"
}

TextureSampler EnvironmentMap
{
	Ref = JominiEnvironmentMap
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
	Type = "Cube"
	File = "gfx/map/environment/panorama_cube_specular_GGX_burley_2_16f.dds"
}

Code
[[
	struct STerrain2Vertex
	{
		float2 _QuadTreePos;
		float3 _WorldSpacePos;
	};

	STerrain2Vertex Terrain2_CalcTerrainVertex( float2 GridPosition0To1, STerrain2NodeData NodeData )
	{
		STerrain2Vertex Out;

		Out._QuadTreePos = GridPosition0To1 * NodeData._Scale + NodeData._Offset;

		float2 WorldSpacePosXZ = Out._QuadTreePos * _QuadTreeSize;

		// Clamp xz extents to the extent of the actual heightmap
		WorldSpacePosXZ = min( WorldSpacePosXZ, _TerrainSize );

		float HeightSample = SampleVirtualHeightmap( GridPosition0To1, NodeData._PhysicalPageDataIndex ).r;

		Out._WorldSpacePos = float3( WorldSpacePosXZ.x, HeightSample * _HeightScale, WorldSpacePosXZ.y );

		return Out;
	}

	STerrain2VertexOutput Terrain2_VertexShaderMain( STerrain2VertexInput Input )
	{
		STerrain2VertexOutput Output;

		STerrain2NodeData NodeData = Terrain2_UnpackNodeDataFromVertex( Input );
		float2 GridPosition0To1 = Terrain2_CalcGridPosition01( Input.VertexID, NodeData );
		STerrain2Vertex Vertex = Terrain2_CalcTerrainVertex( GridPosition0To1, NodeData );

		Output.WorldSpacePosition = Vertex._WorldSpacePos;
		Output.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex._WorldSpacePos, 1.0 ) );
		Output.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex._WorldSpacePos, 1.0 ) );

		return Output;
	}
]]

PixelShader =
{
	Code
	[[
	float4 Terrain2_PixelShaderMain( float3 WorldSpacePosition, float4 ShadowProj, SLightingProperties LightingProps )
	{
		float HeightLod = CalculateVirtualLayerDistanceMip( WorldSpacePosition, _VirtualHeightmapConstants );

		int HeightLodTruncated = HeightLod;
		float HeightLodFrac = HeightLod - (float)HeightLodTruncated;
		float LerpFactor = smoothstep( 0.7, 1.0, HeightLodFrac );

		float3 DerivedNormal = CalculateNormal( WorldSpacePosition.xz, HeightLodTruncated );
		if ( LerpFactor > 0.0 )
		{
			int NextLevelLod = HeightLodTruncated + 1;
			float3 NormalNext = CalculateNormal( WorldSpacePosition.xz, NextLevelLod );
			DerivedNormal = lerp( DerivedNormal, NormalNext, LerpFactor );
		}

		float4 MaterialDiffuseAndHeight;
		float3 MaterialNormal;
		float4 MaterialProperties;
		float3 BlendWeights;

		CalculateMaterials( WorldSpacePosition, DerivedNormal, MaterialDiffuseAndHeight, MaterialNormal, MaterialProperties, BlendWeights );

		float3 ReorientedNormal = ReorientNormal( DerivedNormal, MaterialNormal );

		float3 Diffuse = MaterialDiffuseAndHeight.rgb;

		SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse, ReorientedNormal, MaterialProperties.a, MaterialProperties.g, MaterialProperties.b );

		float3 FinalColor = CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap );

		#if defined( TERRAIN2_DEBUG_MODE )
		if ( TERRAIN2_DEBUG_MODE != 0 )
		{
			FinalColor = TerrainMaterialDebug( WorldSpacePosition, MaterialDiffuseAndHeight, MaterialNormal, MaterialProperties, DerivedNormal, ReorientedNormal, BlendWeights ).rgb;
		}
		#endif

		return float4( FinalColor, 1.0 );
	}
	]]
}
