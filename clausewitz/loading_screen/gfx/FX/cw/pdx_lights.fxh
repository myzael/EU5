Includes = {
	"cw/lighting.fxh"
	"cw/lighting_util.fxh"
	"cw/pdx_shadows.fxh"
}


ConstantBuffer( PdxLightCullingConstants )
{
	uint2 _NumTiles;
	uint2 _TileSize;
	uint _NumDirectionalLights;
	uint _NumPointLights;
	uint _NumSpotLights;
	uint unused;
	uint2 _ClusterIndexStride; 			# .x = _NumTiles.y * _NumDepthClusters, .y = _NumDepthClusters, z is implicit 1
	float _ClusterMinDepth;				# The minimum view space depth where the cluster generation starts
	float _ClusterDepthToClusterIndex; 	# Multiply ("ViewSpaceDepth" - _ClusterMinDepth) with this one to get the z cluster index
	
	int _CullingMode;
	int _LightListMode;
}


# Only one of these are used depending on ELightListMode
# They contain light data (a directional light uses NLightCulling::NumVectorPerDirectionalLight uint4, a point light uses NLightCulling::NumVectorPerPointLight uint4, a spotlight uses NLightCulling::NumVectorPerSpotLight uint4). 
# "ListEntry"._LightDataIndex specifies at what index to start reading data for a light
ConstantBuffer( PdxLightList )
{
	uint4 _LightData[4]; # This buffer is larger than "4" but setting it to large values increases shader compilation times by at least an order of magnitude :(
}
BufferTexture LightList
{
	Ref = PdxLightList
	type = uint4
}

# This one effectively contains a list of "ListEntry", where each entry specifies the lights for that entry, an entry is either a tile or a cluster depending on what culling mode is active
# struct "ListEntry"
# {
# 	uint _NumPointLights;
# 	uint _NumSpotLights;
# 	uint _LightDataIndex[ _NumPointLights ];
# 	uint _LightDataIndex[ _NumSpotLights ];
# }
BufferTexture LightsPerTileList
{
	Ref = PdxLightsPerTileList
	type = uint
}

# This one contains an entry for each tile/cluster, the entry is the index for this tile/cluster's "ListEntry" in the LightsPerTileList
BufferTexture ScreenTileToLightsPerTileList
{
	Ref = PdxScreenTileToLightsPerTileList
	type = uint
}

Code
[[
	#define NUM_VECTORS_FOR_DIRECTIONALLIGHT 2
	#define NUM_VECTORS_FOR_POINTLIGHT 2
	#define NUM_VECTORS_FOR_SPOTLIGHT 4
	
	struct SDirectionalLight
	{
		float3	_ToLightDirection;
		float3	_Color;
		uint	_ShadowIndex;
	};
	struct SPointLight
	{
		float3	_Position;
		float	_Radius;
		float3	_Color;
		uint	_ShadowIndex;
	};
	struct SSpotLight
	{
		SPointLight	_PointLight;
		float3		_ConeDirection;
		float		_CosInnerConeHalfAngle;
		float		_CosOuterConeHalfAngle;
	};

	SDirectionalLight BuildDirectionalLight( float3 ToLightDirection, float3 Color, uint ShadowIndex )
	{
		SDirectionalLight DirectionalLight;
		DirectionalLight._ToLightDirection = ToLightDirection;
		DirectionalLight._Color = Color;
		DirectionalLight._ShadowIndex = ShadowIndex;
		return DirectionalLight;
	}
	SDirectionalLight BuildDirectionalLight( uint4 Data1, uint4 Data2 )
	{
		return BuildDirectionalLight( asfloat( Data1.xyz ), asfloat( Data2.xyz ), Data2.w );
	}
	
	SPointLight BuildPointLight( float4 PositionAndRadius, float3 Color, uint ShadowIndex )
	{
		SPointLight PointLight;
		PointLight._Position = PositionAndRadius.xyz;
		PointLight._Radius = PositionAndRadius.w;
		PointLight._Color = Color.xyz;
		PointLight._ShadowIndex = ShadowIndex;
		return PointLight;
	}
	SPointLight BuildPointLight( float4 PositionAndRadius, float3 Color )
	{
		return BuildPointLight( PositionAndRadius, Color, PDX_NO_SHADOW_INDEX );
	}
	SPointLight BuildPointLight( uint4 Data1, uint4 Data2 )
	{
		return BuildPointLight( asfloat( Data1 ), asfloat( Data2.xyz ),	Data2.w );
	}
	
	SSpotLight BuildSpotLight( float4 PositionAndRadius, float4 ColorAndInnerCosAngle, float4 DirectionAndOuterCosAngle, uint ShadowIndex )
	{
		SSpotLight SpotLight;
		SpotLight._PointLight = BuildPointLight( PositionAndRadius, ColorAndInnerCosAngle.xyz, ShadowIndex );
		SpotLight._ConeDirection = DirectionAndOuterCosAngle.xyz;
		SpotLight._CosInnerConeHalfAngle = ColorAndInnerCosAngle.w;
		SpotLight._CosOuterConeHalfAngle = DirectionAndOuterCosAngle.w;
		return SpotLight;
	}
	SSpotLight BuildSpotLight( float4 PositionAndRadius, float4 ColorAndInnerCosAngle, float4 DirectionAndOuterCosAngle )
	{
		return BuildSpotLight( PositionAndRadius, ColorAndInnerCosAngle, DirectionAndOuterCosAngle, PDX_NO_SHADOW_INDEX );
	}
	SSpotLight BuildSpotLight( uint4 Data1, uint4 Data2, uint4 Data3, uint4 Data4 )
	{
		return BuildSpotLight( asfloat( Data1 ), asfloat( Data2 ), asfloat( Data3 ), Data4.x );
	}

	
	// Define either of these to disable the dynamic branching and use a hardcoded version of the specified light list mode
	//#define CONSTANT_LIGHT_LIST
	//#define BUFFER_LIGHT_LIST
	
	// Define either of these to disable the dynamic branching and use a hardcoded version of the specified culling mode
	//#define CULLING_MODE_NONE
	//#define CULLING_MODE_TILED
	//#define CULLING_MODE_CLUSTERED
	
#if !defined( CONSTANT_LIGHT_LIST ) && !defined( BUFFER_LIGHT_LIST )
	#define DYNAMIC_LIGHT_LIST
#endif

#ifdef DYNAMIC_LIGHT_LIST
	static int ELightListMode_Constants = 0;	// Lights are stored in the constants buffer PdxLightList (limited to 4096 float4)
	static int ELightListMode_Buffer = 1;		// Lights are stored in the buffer texture PdxLightList
#endif
	
#if !defined( CULLING_MODE_NONE ) && !defined( CULLING_MODE_TILED ) && !defined( CULLING_MODE_CLUSTERED )
	#define DYNAMIC_CULLING_MODE
#endif

#ifdef DYNAMIC_CULLING_MODE
	static int ECullingMode_CpuTiled = 0;
	static int ECullingMode_GpuTiled = 1;
	static int ECullingMode_CpuGpuTiled = 2;
	static int ECullingMode_CpuClustered = 3;
#endif


	// Helper function to get directionallight data starting at LightDataIndex, hides the details of the different light list modes
	SDirectionalLight GetDirectionalLight( uint LightDataIndex )
	{
#ifdef DYNAMIC_LIGHT_LIST
		if ( _LightListMode == ELightListMode_Constants )
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
		{
			return BuildDirectionalLight( _LightData[LightDataIndex], _LightData[LightDataIndex+1] );
		}
		
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
#ifdef DYNAMIC_LIGHT_LIST
		else
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
		{
			return BuildDirectionalLight( PdxReadBuffer4( LightList, LightDataIndex ), PdxReadBuffer4( LightList, LightDataIndex + 1 ) );
		}
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
	}

	// Helper function to get pointlight data starting at LightDataIndex, hides the details of the different light list modes
	SPointLight GetPointLight( uint LightDataIndex )
	{
#ifdef DYNAMIC_LIGHT_LIST
		if ( _LightListMode == ELightListMode_Constants )
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
		{
			return BuildPointLight( _LightData[LightDataIndex], _LightData[LightDataIndex+1] );
		}
		
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
#ifdef DYNAMIC_LIGHT_LIST
		else
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
		{
			return BuildPointLight( PdxReadBuffer4( LightList, LightDataIndex ), PdxReadBuffer4( LightList, LightDataIndex + 1 ) );
		}
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
	}
	
	// Helper function to get spotlight data starting at LightDataIndex, hides the details of the different light list modes
	SSpotLight GetSpotLight( uint LightDataIndex )
	{
#ifdef DYNAMIC_LIGHT_LIST
		if ( _LightListMode == ELightListMode_Constants )
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
		{
			return BuildSpotLight( _LightData[LightDataIndex], _LightData[LightDataIndex + 1], _LightData[LightDataIndex + 2], _LightData[LightDataIndex + 3] );
		}
		
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( CONSTANT_LIGHT_LIST )
#ifdef DYNAMIC_LIGHT_LIST
		else
#endif
#if defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
		{
			return BuildSpotLight( PdxReadBuffer4( LightList, LightDataIndex ), PdxReadBuffer4( LightList, LightDataIndex + 1 ), PdxReadBuffer4( LightList, LightDataIndex + 2 ), PdxReadBuffer4( LightList, LightDataIndex + 3 ) );
		}
#endif // defined( DYNAMIC_LIGHT_LIST ) || defined ( BUFFER_LIGHT_LIST )
	}
	
	
	// Calculate the "tile position/id" for the tile containing PixelPos
	uint2 CalculateTileForPixel( uint2 PixelPos, uint2 TileSize )
	{
		return PixelPos / TileSize;
	}
	// Calculate the "linear" offset for the tile position/id TilePos (i.e. index into ScreenTileToLightsPerTileList)
	uint CalculateOffsetForTile( uint2 TilePos, uint2 NumTiles )
	{
		return TilePos.x * NumTiles.y + TilePos.y;
	}
	// Calculate the "linear" offset for the tile containing PixelPos (i.e. index into ScreenTileToLightsPerTileList)
	uint CalculateOffsetForTileForPixel( uint2 PixelPos, uint2 TileSize, uint2 NumTiles )
	{
		return CalculateOffsetForTile( CalculateTileForPixel( PixelPos, TileSize ), NumTiles );
	}	
	uint CalculateOffsetForTileForPixel( uint2 PixelPos )
	{
		return CalculateOffsetForTile( CalculateTileForPixel( PixelPos, _TileSize ), _NumTiles );
	}
	
	// Calculate the 3d "cluster index" for the cluster containing [PixelPos.xy, ViewSpaceDepth]
	uint3 CalculateClusterIndexForPixel( uint2 PixelPos, float ViewSpaceDepth )
	{
		return uint3( PixelPos / _TileSize, ( ViewSpaceDepth - _ClusterMinDepth ) * _ClusterDepthToClusterIndex );
	}
	// Calculate the "linear" offset for the 3d cluster index "ClusterIndex" (i.e. index into ScreenTileToLightsPerTileList)
	uint CalculateOffsetForClusterIndex( uint3 ClusterIndex )
	{
		return ClusterIndex.x * _ClusterIndexStride.x + ClusterIndex.y * _ClusterIndexStride.y + ClusterIndex.z;
	}
	// Calculate the "linear" offset for the cluster containing [PixelPos.xy, ViewSpaceDepth] (i.e. index into ScreenTileToLightsPerTileList)
	uint CalculateOffsetForClusterForPixel( uint2 PixelPos, float ViewSpaceDepth )
	{
		return CalculateOffsetForClusterIndex( CalculateClusterIndexForPixel( PixelPos, ViewSpaceDepth ) );
	}
	
	// Calculate the LightsPerTileList index for where light data can be found for the tile containing PixelPos
	uint CalculateLightsPerTileListIndexForTile( float2 PixelPos )
	{
		// Calculate the "ScreenTileToLightsPerTileList" offset for the current tile
		uint TileOffset = CalculateOffsetForTileForPixel( uint2( PixelPos ) );

		// Lookup where this tiles light data is stored, ScreenTileToLightsPerTileList contains an entry for each tile that is the offset of that tiles data in the LightsPerTileList
		uint LightsPerTileListIndex = PdxReadBuffer( ScreenTileToLightsPerTileList, TileOffset );
		return LightsPerTileListIndex;
	}
	
	// Calculate the LightsPerTileList index for where light data can be found for the cluster containing [PixelPos, ViewSpaceDepth]
	uint CalculateLightsPerTileListIndexForCluster( float2 PixelPos, float ViewSpaceDepth )
	{
		// Calculate the "ScreenTileToLightsPerTileList" offset for the current cluster
		uint ClusterOffset = CalculateOffsetForClusterForPixel( uint2( PixelPos ), ViewSpaceDepth );
		
		// Lookup where this clusters light data is stored, ScreenTileToLightsPerTileList contains an entry for each cluster that is the offset of that clusters data in the LightsPerTileList
		uint LightsPerTileListIndex = PdxReadBuffer( ScreenTileToLightsPerTileList, ClusterOffset );
		return LightsPerTileListIndex;
	}

	// Calculate the LightsPerTileList index for where light data can be found for the tile/cluster (depending on _CullingMode) containing [PixelPos, ViewSpaceDepth]
	uint CalculateLightsPerTileListIndex( float2 PixelPos, float ViewSpaceDepth )
	{
		uint LightsPerTileListIndex = 0;
		
		// Get LightsPerTileListIndex depending on what culling mode is active
#ifdef DYNAMIC_CULLING_MODE
		if ( _CullingMode == ECullingMode_CpuClustered )
#endif
#if defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_CLUSTERED )
		{
			LightsPerTileListIndex = CalculateLightsPerTileListIndexForCluster( PixelPos, ViewSpaceDepth );
		}
#endif // defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_CLUSTERED )

#ifdef DYNAMIC_CULLING_MODE
		else
#endif
#if defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_TILED ) || defined( CULLING_MODE_NONE )
		{
			LightsPerTileListIndex = CalculateLightsPerTileListIndexForTile( PixelPos );
		}
#endif // defined( DYNAMIC_CULLING_MODE ) || defined ( CULLING_MODE_TILED ) || defined( CULLING_MODE_NONE )
		
		return LightsPerTileListIndex;
	}
	
	
	// Macros to make different usage of light sources easier, expected usage is: (specifically we currently expect that you do PDX_LIGHT_LOOP_POINTLIGHTS followed by PDX_LIGHT_LOOP_SPOTLIGHTS, this can be relaxed in the future if needed)
	//	PDX_LIGHT_LOOP_BEGIN( PixelPos, ViewSpaceDepth )
	// 	PDX_LIGHT_LOOP_DIRECTIONAL_LIGHTS
	// 	Do code that uses directional lights here, variable "DirectionalLight" is the SDirectionalLight for the current directional light
	// 	PDX_LIGHT_LOOP_POINT_LIGHTS
	// 	Do code that uses point lights here, variable "PointLight" is the SPointLight for the current point light
	//	PDX_LIGHT_LOOP_SPOT_LIGHTS
	// 	Do code that uses spot lights here, variable "SpotLight" is the SSpotLight for the current spot light
	//	PDX_LIGHT_LOOP_END
	
	#define PDX_LIGHT_LOOP_BEGIN( PixelPos, ViewSpaceDepth )                                                  	\
		uint LightsPerTileListIndex = CalculateLightsPerTileListIndex( ( PixelPos ), ( ViewSpaceDepth ) );    	\
		/* First entries in the list is the number of point/spot lights for the tile */                       	\
		uint NumPointLights = PdxReadBuffer( LightsPerTileList, LightsPerTileListIndex );                     	\
		uint NumSpotLights = PdxReadBuffer( LightsPerTileList, LightsPerTileListIndex + 1 );

	#define PDX_LIGHT_LOOP_DIRECTIONAL_LIGHTS																	\
		for ( uint i = 0; i < _NumDirectionalLights; ++i ) 														\
		{																										\
			uint LightDataIndex = i * NUM_VECTORS_FOR_DIRECTIONALLIGHT;											\
			SDirectionalLight DirectionalLight = GetDirectionalLight( LightDataIndex );

	#define PDX_LIGHT_LOOP_POINT_LIGHTS                                                                        	\
		}																									  	\
		/* The rest of the entries are the light data indices */                                              	\
		uint Offset = LightsPerTileListIndex + 2;  /* +2 to jump over the "NumPointLights/NumSpotLights" */   	\
		for ( uint i = 0; i < NumPointLights; ++i )                                                           	\
		{                                                                                                     	\
			uint LightDataIndex = PdxReadBuffer( LightsPerTileList, Offset + i );                             	\
			SPointLight PointLight = GetPointLight( LightDataIndex );
		
	#define PDX_LIGHT_LOOP_SPOT_LIGHTS                                                                         	\
		}                                                                                                     	\
		Offset += NumPointLights; /* Jump over point lights */                                                	\
		for ( uint i = 0; i < NumSpotLights; ++i )                                                            	\
		{                                                                                                     	\
			uint LightDataIndex = PdxReadBuffer( LightsPerTileList, Offset + i );                             	\
			SSpotLight SpotLight = GetSpotLight( LightDataIndex );

	#define PDX_LIGHT_LOOP_END                                                                               	\
		}
]]


PixelShader =
{
	Code
	[[
		void CalculateLightingFromDirectionalLight( SDirectionalLight DirectionalLight, float3 WorldSpacePos, float ShadowTerm, SMaterialProperties MaterialProps, inout float3 DiffuseLightOut, inout float3 SpecularLightOut )
		{
			float3 ToCameraDir = normalize( CameraPosition - WorldSpacePos );
			float3 ToLightDir = DirectionalLight._ToLightDirection;

			float3 DiffuseLight;
			float3 SpecularLight;
			CalculateLightingFromLight( MaterialProps, ToCameraDir, ToLightDir, DirectionalLight._Color * ShadowTerm, DiffuseLight, SpecularLight );
			DiffuseLightOut += DiffuseLight;
			SpecularLightOut += SpecularLight;
		}
		
		void CalculateLightingFromPointLight( SPointLight PointLight, float3 WorldSpacePos, float ShadowTerm, SMaterialProperties MaterialProps, inout float3 DiffuseLightOut, inout float3 SpecularLightOut )
		{
			float3 PosToLight = PointLight._Position - WorldSpacePos;
			float DistanceToLight = length( PosToLight );
		
			float LightIntensity = CalcLightFalloff( PointLight._Radius, DistanceToLight ) * ShadowTerm;
			if ( LightIntensity > 0.0 )
			{
				float3 ToCameraDir = normalize( CameraPosition - WorldSpacePos );
				float3 ToLightDir = PosToLight / DistanceToLight;
				
				float3 DiffuseLight;
				float3 SpecularLight;
				CalculateLightingFromLight( MaterialProps, ToCameraDir, ToLightDir, PointLight._Color * LightIntensity, DiffuseLight, SpecularLight );
				DiffuseLightOut += DiffuseLight;
				SpecularLightOut += SpecularLight;
			}
		}
		
		void CalculateLightingFromSpotLight( SSpotLight SpotLight, float3 WorldSpacePos, float ShadowTerm, SMaterialProperties MaterialProps, inout float3 DiffuseLightOut, inout float3 SpecularLightOut )
		{
			float3 PosToLight = SpotLight._PointLight._Position - WorldSpacePos;
			float DistanceToLight = length( PosToLight );
			float3 ToLightDir = PosToLight / DistanceToLight;
			
			float PdotL = dot( -ToLightDir, SpotLight._ConeDirection );
			float SpotLightShadow = smoothstep( SpotLight._CosOuterConeHalfAngle, SpotLight._CosInnerConeHalfAngle, PdotL );
			
			// Treat spotlight as a pointlight with an extra shadowterm
			CalculateLightingFromPointLight( SpotLight._PointLight, WorldSpacePos, ShadowTerm * SpotLightShadow, MaterialProps, DiffuseLightOut, SpecularLightOut );
		}


		// Helper function to loop over all lights for the current tile/cluster (tile containing [PixelPos]/cluster containing [PixelPos.xy, ViewSpaceDepth]) and perform "default" lighting
		void CalculateLightSourceLighting( float2 PixelPos, float ViewSpaceDepth, float3 WorldSpacePos, SMaterialProperties MaterialProps, inout float3 DiffuseLightOut, inout float3 SpecularLightOut )
		{
			PDX_LIGHT_LOOP_BEGIN( PixelPos, ViewSpaceDepth )
			
			PDX_LIGHT_LOOP_DIRECTIONAL_LIGHTS
				float ShadowTerm = CalculateDirectionalShadow( WorldSpacePos, DirectionalLight._ShadowIndex );
				CalculateLightingFromDirectionalLight( DirectionalLight, WorldSpacePos, ShadowTerm, MaterialProps, DiffuseLightOut, SpecularLightOut );

			PDX_LIGHT_LOOP_POINT_LIGHTS
				float ShadowTerm = CalculateCubeShadow( WorldSpacePos, PointLight._Position, PointLight._ShadowIndex );
				CalculateLightingFromPointLight( PointLight, WorldSpacePos, ShadowTerm, MaterialProps, DiffuseLightOut, SpecularLightOut );
				
			PDX_LIGHT_LOOP_SPOT_LIGHTS
				float ShadowTerm = CalculateProjectorShadow( WorldSpacePos, SpotLight._PointLight._ShadowIndex );
				CalculateLightingFromSpotLight( SpotLight, WorldSpacePos, ShadowTerm, MaterialProps, DiffuseLightOut, SpecularLightOut );
				
			PDX_LIGHT_LOOP_END
		}
		
		// This one will use currently bound camera constants to calculate ViewSpaceDepth from WorldSpacePos
		void CalculateLightSourceLighting( float2 PixelPos, float3 WorldSpacePos, SMaterialProperties MaterialProps, inout float3 DiffuseLightOut, inout float3 SpecularLightOut )
		{
			CalculateLightSourceLighting( PixelPos, mul( ViewMatrix, float4( WorldSpacePos, 1.0 ) ).z, WorldSpacePos, MaterialProps, DiffuseLightOut, SpecularLightOut );
		}
	]]
}
