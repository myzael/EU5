Includes = {
	"cw/terrain2_heightmap.fxh"
	"cw/terrain2_utils.fxh"
	"cw/terrain2_biomes.fxh"
	"cw/put_string_util.fxh"
	"cw/terrain2_virtual_layers.fxh"
}

BindlessResources
{
	Texture
}

Sampler PointSampler
{
	MagFilter = "Point"
	MinFilter = "Point"
	MipFilter = "Point"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

Sampler DetailMaskPointSampler
{
	MagFilter = "Point"
	MinFilter = "Point"
	MipFilter = "Point"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

Sampler BiomeMaterialSampler
{
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Wrap"
	SampleModeV = "Wrap"
}

# Colormap. Not accounted for in terrain2, but used in eg. meshes.
# TODO[TS]: Move out of terrain2 folder?
TextureSampler ColorTexture
{
	Ref = PdxTerrainColorMap
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Wrap"
	SampleModeV = "Clamp"
}

struct STerrain2MaterialHandles
{
	int _DiffuseHandle;
	int _NormalHandle;
	int _PropertiesHandle;
	int _Pad0;
}

struct STerrain2Biome
{
	# NOTE[TS]: HLSL packs array elements to 16 bytes. So in C++ this is declared as int32[64]
	int4 _Materials[16];
}

struct SBiomeMaterialConstants
{
	STerrain2MaterialHandles _MaterialHandles[256];
	STerrain2Biome _Biomes[200];
}

ConstantBuffer( PdxTerrain2MaterialConstants )
{
	float _InvMaterialTileSize;
	float _TriPlanarUVTightenFactor;
	float2 _Pad0;
	SBiomeMaterialConstants _BiomeMaterialConstants;
}

Code
[[
	STerrain2MaterialHandles GetMaterialHandles( int BiomeIdx, int MaterialIdx )
	{
		if ( MaterialIdx < 0 )
		{
			// MaterialIdx -1 is what we get when there's no material at a certain texel. This is ok, we'll just return the lowest priority material for the biome
			return _BiomeMaterialConstants._MaterialHandles[ _BiomeMaterialConstants._Biomes[ BiomeIdx ]._Materials[ 3 ][ 3 ] ];
		}
		int MaterialIdx1 = MaterialIdx / 4;
		int MaterialIdx2 = MaterialIdx % 4;
		return _BiomeMaterialConstants._MaterialHandles[ _BiomeMaterialConstants._Biomes[ BiomeIdx ]._Materials[ MaterialIdx1 ][ MaterialIdx2 ] ];
	}

	float4 CalcHeightBlendFactors( float4 MaterialHeights, float4 MaterialFactors, float BlendRange )
	{
		float4 Mat = MaterialHeights + MaterialFactors;
		float BlendStart = max( max( Mat.x, Mat.y ), max( Mat.z, Mat.w ) ) - BlendRange;

		float4 MatBlend = max( Mat - vec4( BlendStart ), vec4( 0.0 ) );

		float Epsilon = 0.00001;
		return float4( MatBlend ) / ( dot( MatBlend, vec4( 1.0 ) ) + Epsilon );
	}

	// Extracts the top `Count` highest priority materials from mask.
	// `Count` Must be [1, 4]
	int4 ExtractMaterialIndices( uint MaterialMask, int Count )
	{
		int4 Indices = int4( -1, -1, -1, -1 );
		int IndexIndex = 0; // :)

		for ( uint MaterialIdx = 0; MaterialIdx < 16; ++MaterialIdx )
		{
			if ( ( MaterialMask & ( 1u << MaterialIdx ) ) != 0u )
			{
				Indices[ IndexIndex ] = (int)MaterialIdx;
				IndexIndex++;
				if ( IndexIndex == Count )
				{
					return Indices;
				}
			}
		}

		return Indices;
	}

	int CalculateMaskCardinality( uint MaterialMask )
	{
		int Cardinality = 0;

		for ( uint MaterialIdx = 0; MaterialIdx < 16; ++MaterialIdx )
		{
			if ( ( MaterialMask & ( 1u << MaterialIdx ) ) != 0u )
			{
				Cardinality++;
			}
		}

		return Cardinality;
	}

	// TODO[TS]: Where should this live?
	float BlendAddSub( float Background, float Foreground)
	{
		float RelativeTo05 = Foreground - 0.5f;
		return Background + abs( RelativeTo05 ) * sign( RelativeTo05 );
	}

	float3 BlendAddSub( float3 Background, float Foreground, float Strength )
	{
		float RelativeTo05 = Foreground - 0.5f;
		return Background + abs( RelativeTo05 ) * sign( RelativeTo05 ) * 2.0 * Strength;
	}

	void SampleMaterialDiffuse( float2 MaterialUV, int BiomeIdx, int MaterialIdx, out float4 DiffuseAndHeight )
	{
		STerrain2MaterialHandles Handles = GetMaterialHandles( BiomeIdx, MaterialIdx );

		Texture2D MaterialDiffuse = GetBindlessTexture2DNonUniform( Handles._DiffuseHandle );

		DiffuseAndHeight = ToLinear( PdxSampleTex2D( MaterialDiffuse, BiomeMaterialSampler, MaterialUV ) );
	}

	void SampleMaterialTextures( float2 MaterialUV, int BiomeIdx, int MaterialIdx, out float4 DiffuseAndHeight, out float3 Normal, out float4 Properties )
	{
		STerrain2MaterialHandles Handles = GetMaterialHandles( BiomeIdx, MaterialIdx );

		Texture2D MaterialDiffuse = GetBindlessTexture2DNonUniform( Handles._DiffuseHandle );
		Texture2D MaterialNormal = GetBindlessTexture2DNonUniform( Handles._NormalHandle );
		Texture2D MaterialProperties = GetBindlessTexture2DNonUniform( Handles._PropertiesHandle );

		DiffuseAndHeight = PdxSampleTex2D( MaterialDiffuse, BiomeMaterialSampler, MaterialUV );
		Normal = UnpackRRxGNormal( PdxSampleTex2D( MaterialNormal, BiomeMaterialSampler, MaterialUV ) );
		Properties = PdxSampleTex2D( MaterialProperties, BiomeMaterialSampler, MaterialUV );
	}

	uint GetMaterialMaskAt( uint2 PhysicalTexel )
	{
		return PdxTexture2DLoad0( VirtualMaterialsPhysicalTexture, PhysicalTexel ).r;
	}

	int GetTopMaterialIndexAt( uint2 PhysicalTexel )
	{
		uint Mask = GetMaterialMaskAt( PhysicalTexel );
		return ExtractMaterialIndices( Mask, 1 )[ 0 ];
	}

	template < typename T >
	T LerpBilinear( float2 Frac, T TL, T TR, T BL, T BR )
	{
		T L1 = lerp( TL, TR, Frac.x );
		T L2 = lerp( BL, BR, Frac.x );
		return lerp( L1, L2, Frac.y );
	}

	float3 GetTriPlanarUVBlendFactor( float3 Normal )
	{
		const float3 Tighten = float3( _TriPlanarUVTightenFactor, _TriPlanarUVTightenFactor, _TriPlanarUVTightenFactor );

		Normal = abs( Normal );

		if( Normal.y < 0.866 )
		{
			Normal.y = 0.0f;
		}

		float3 Blending = Normal - Tighten;

		// Force weights to sum to 1.0
		Blending = normalize( max( Blending, 0.00001 ) );
		float B = ( Blending.x + Blending.y + Blending.z );
		Blending /= float3( B, B, B );
		return Blending;
	}

	void CalcTriPlanarUV( float3 WorldSpacePosition, int4 MaterialIndex, int4 Biome, float2 PhysicalTexelFrac, float3 BlendFactor, out float4 DiffuseAndHeight, out float3 Normal, out float4 Properties )
	{
		DiffuseAndHeight = float4( 0, 0, 0, 0 );
		Normal = float3( 0, 0, 0 );
		Properties = float4( 0, 0, 0, 0 );

		float4 Diffuses[ 4 ];
		float3 Normals[ 4 ];
		float4 _Properties[ 4 ];
		
		float2 MaterialUV[ 3 ];
		MaterialUV[ 0 ] = WorldSpacePosition.zy * _InvMaterialTileSize;
		MaterialUV[ 1 ] = WorldSpacePosition.xz * _InvMaterialTileSize;
		MaterialUV[ 2 ] = WorldSpacePosition.xy * _InvMaterialTileSize;

		float Epsilon = 0.01;

		for ( int i = 0; i < 3; ++i )
		{
			if( BlendFactor[ i ] > Epsilon )
			{
				for ( int j = 0; j < 4; ++j )
				{
					SampleMaterialTextures( MaterialUV[ i ], Biome[ j ], MaterialIndex[ j ], Diffuses[ j ], Normals[ j ], _Properties[ j ] );
				}
				
				DiffuseAndHeight += LerpBilinear( PhysicalTexelFrac, Diffuses[ 0 ], Diffuses[ 1 ], Diffuses[ 2 ], Diffuses[ 3 ] ) * BlendFactor[ i ];
				Normal += LerpBilinear( PhysicalTexelFrac, Normals[ 0 ], Normals[ 1 ], Normals[ 2 ], Normals[ 3 ] ) * BlendFactor[ i ];
				Properties += LerpBilinear( PhysicalTexelFrac, _Properties[ 0 ], _Properties[ 1 ], _Properties[ 2 ], _Properties[ 3 ] ) * BlendFactor[ i ];
			}
		}
	}

	void CalculateMaterialsBilinear( float3 WorldSpacePosition, float3 WorldSpaceNormal, out float4 DiffuseAndHeight, out float3 Normal, out float4 Properties, out float3 BlendWeights )
	{
		DiffuseAndHeight = float4( 0, 0, 0, 0 );
		Normal = float3( 0, 1, 0 );
		Properties = float4( 0, 0, 0, 0 );

		SPhysicalTexel MaterialsTexel = CalcPhysicalMaterialsTexel( WorldSpacePosition, CalculateVirtualLayerDistanceMip( WorldSpacePosition, _VirtualMaterialsConstants ) );
#ifdef TERRAIN2_CURVATURE_ENABLED
		SPhysicalTexel CurvatureTexel = CalcPhysicalCurvatureTexel( WorldSpacePosition, CalculateVirtualLayerDistanceMip( WorldSpacePosition, _VirtualCurvatureConstants ) );
#endif // TERRAIN2_CURVATURE_ENABLED

		int2 Offsets[ 4 ] = { int2( 0, 0 ), int2( 1, 0 ), int2( 0, 1 ), int2( 1, 1 ) };

		float2 MaterialUV = WorldSpacePosition.xz * _InvMaterialTileSize;

		float4 Diffuses[ 4 ];
		float3 Normals[ 4 ];
		float4 _Properties[ 4 ];
#ifdef TERRAIN2_CURVATURE_ENABLED
		float Curvatures[ 4 ];
#endif // TERRAIN2_CURVATURE_ENABLED

		float2 MaterialToWorld = _TerrainSize * _VirtualMaterialsConstants._ClipmapConstants._InvVirtualTextureSize;
		float2 MaterialTexelSizeInWorldSpace = MaterialToWorld * float( 1u << MaterialsTexel._PageMip );
		float2 WorldSpace00 = WorldSpacePosition.xz - MaterialTexelSizeInWorldSpace * MaterialsTexel._PositionFrac;

		int4 MaterialIndex;
		int4 Biome;
		for ( int i = 0; i < 4; ++i )
		{
			MaterialIndex[ i ] = GetTopMaterialIndexAt( MaterialsTexel._Position + Offsets[ i ] );
			Biome[ i ] = GetBiomeWorldspace( WorldSpace00 + MaterialTexelSizeInWorldSpace * Offsets[ i ], MaterialIndex[ i ] );
#ifdef TERRAIN2_CURVATURE_ENABLED
			Curvatures[ i ] = PdxTexture2DLoad0( VirtualCurvaturePhysicalTexture, CurvatureTexel._Position + Offsets[ i ] ).r;
#endif // TERRAIN2_CURVATURE_ENABLED
		}

#ifndef TRIPLANAR_UV_MAPPING_ENABLED
		for ( int i = 0; i < 4; ++i )
		{
			SampleMaterialTextures( MaterialUV, Biome[ i ], MaterialIndex[ i ], Diffuses[ i ], Normals[ i ], _Properties[ i ] );
		}

		DiffuseAndHeight = LerpBilinear( MaterialsTexel._PositionFrac, Diffuses[ 0 ], Diffuses[ 1 ], Diffuses[ 2 ], Diffuses[ 3 ] );
		Normal = LerpBilinear( MaterialsTexel._PositionFrac, Normals[ 0 ], Normals[ 1 ], Normals[ 2 ], Normals[ 3 ] );
		Properties = LerpBilinear( MaterialsTexel._PositionFrac, _Properties[ 0 ], _Properties[ 1 ], _Properties[ 2 ], _Properties[ 3 ] );

		// For material debugging only
		BlendWeights = float3( 0, 1, 0 );
#else
		float3 BlendFactor = GetTriPlanarUVBlendFactor( WorldSpaceNormal );
		CalcTriPlanarUV( WorldSpacePosition, MaterialIndex, Biome, MaterialsTexel._PositionFrac, BlendFactor, DiffuseAndHeight, Normal, Properties );

		// For material debugging only
		BlendWeights = BlendFactor;
#endif

#ifdef TERRAIN2_CURVATURE_ENABLED
		float Curvature = LerpBilinear( CurvatureTexel._PositionFrac, Curvatures[ 0 ], Curvatures[ 1 ], Curvatures[ 2 ], Curvatures[ 3 ] );
		DiffuseAndHeight.rgb = saturate( BlendAddSub( DiffuseAndHeight.rgb, Curvature, _CurvatureMapStrength ) );
#endif // TERRAIN2_CURVATURE_ENABLED
	}

	float CalculateGridMask( int2 Texel, int GridSize )
	{
		Texel /= GridSize;
		return (float)( ( ( Texel.x & 1 ) + ( Texel.y & 1 ) ) & 1 );
	}

	#define T2_DEBUG_NONE 0u
	#define T2_DEBUG_MASK_CARDINALITY 1u
	#define T2_DEBUG_MATERIAL_PRIORITY_1 2u
	#define T2_DEBUG_MATERIAL_PRIORITY_2 3u
	#define T2_DEBUG_MATERIAL_PRIORITY_3 4u
	#define T2_DEBUG_MATERIAL_PRIORITY_4 5u
	#define T2_DEBUG_MATERIAL_TEXEL_GRID 6u
	#define T2_DEBUG_BIOME 7u
	#define T2_DEBUG_MATERIAL_NORMAL 8u
	#define T2_DEBUG_DERIVED_NORMAL 9u
	#define T2_DEBUG_REORIENTED_NORMAL 10u
	#define T2_DEBUG_PROPERTIES_R 11u
	#define T2_DEBUG_PROPERTIES_G 12u
	#define T2_DEBUG_PROPERTIES_B 13u
	#define T2_DEBUG_PROPERTIES_A 14u
	#define T2_DEBUG_DIFFUSE 15u
	#define T2_DEBUG_MATERIAL_HEIGHT 16u
	#define T2_DEBUG_MATERIAL_SOLID_LERP_2 17u
	#define T2_DEBUG_MATERIAL_SOLID_LERP_3 18u
	#define T2_DEBUG_MATERIAL_MASK_INFO 19u
	#define T2_DEBUG_CURVATURE_MAP 20u
	#define T2_DEBUG_BLEND_WEIGHTS 21u

	#if !defined( TERRAIN2_DEBUG_MODE )
	#define TERRAIN2_DEBUG_MODE T2_DEBUG_NONE
	#endif

	float3 TerrainMaterialDebug( float3 WorldSpacePosition, float4 MaterialDiffuseAndHeight, float3 MaterialNormal, float4 MaterialProperties, float3 DerivedNormal, float3 ReorientedNormal, float3 BlendWeights )
	{
		SPhysicalTexel MaterialsTexel = CalcPhysicalMaterialsTexel( WorldSpacePosition, CalculateVirtualLayerDistanceMip( WorldSpacePosition, _VirtualMaterialsConstants ) );

		int Biome = GetBiomeWorldspace( WorldSpacePosition.xz );
		uint MaterialMask = GetMaterialMaskAt( MaterialsTexel._Position );

		switch ( uint( TERRAIN2_DEBUG_MODE ) )
		{
			case T2_DEBUG_NONE: {
				break;
			}

			case T2_DEBUG_MASK_CARDINALITY: {
				return IntToNiceColor( CalculateMaskCardinality( MaterialMask ) );
			}

			case T2_DEBUG_MATERIAL_PRIORITY_1: {
				int MaterialIdx = ExtractMaterialIndices( MaterialMask, 1 )[ 0 ];
				if ( MaterialIdx < 0 ) { return float3( 0, 0, 0 ); }
				return IntToNiceColor( MaterialIdx );
			}

			case T2_DEBUG_MATERIAL_PRIORITY_2: {
				int MaterialIdx = ExtractMaterialIndices( MaterialMask, 2 )[ 1 ];
				if ( MaterialIdx < 0 ) { return float3( 0, 0, 0 ); }
				return IntToNiceColor( MaterialIdx );
			}

			case T2_DEBUG_MATERIAL_PRIORITY_3: {
				int MaterialIdx = ExtractMaterialIndices( MaterialMask, 3 )[ 2 ];
				if ( MaterialIdx < 0 ) { return float3( 0, 0, 0 ); }
				return IntToNiceColor( MaterialIdx );
			}

			case T2_DEBUG_MATERIAL_PRIORITY_4: {
				int MaterialIdx = ExtractMaterialIndices( MaterialMask, 4 )[ 3 ];
				if ( MaterialIdx < 0 ) { return float3( 0, 0, 0 ); }
				return IntToNiceColor( MaterialIdx );
			}

			case T2_DEBUG_MATERIAL_TEXEL_GRID: {
				// TODO[TS]: Not useful, show mip level
				float Mask1 = CalculateGridMask( MaterialsTexel._Position, 1 );
				float Mask8 = CalculateGridMask( MaterialsTexel._Position, 8 );
				float Mask64 = CalculateGridMask( MaterialsTexel._Position, 64 );
				return float3( Mask1, Mask8, Mask64 );
			}

			case T2_DEBUG_BIOME: {
				return IntToNiceColor( Biome );
			}

			case T2_DEBUG_MATERIAL_NORMAL: {
				return float3( ( MaterialNormal + 1 ) / 2 );
			}

			case T2_DEBUG_DERIVED_NORMAL: {
				return float3( ( DerivedNormal + 1 ) / 2 );
			}

			case T2_DEBUG_REORIENTED_NORMAL: {
				return float3( ( ReorientedNormal + 1 ) / 2 );
			}

			case T2_DEBUG_PROPERTIES_R: {
				return float3( MaterialProperties.rrr );
			}

			case T2_DEBUG_PROPERTIES_G: {
				return float3( MaterialProperties.ggg );
			}

			case T2_DEBUG_PROPERTIES_B: {
				return float3( MaterialProperties.bbb );
			}

			case T2_DEBUG_PROPERTIES_A: {
				return float3( MaterialProperties.aaa );
			}

			case T2_DEBUG_DIFFUSE: {
				return float3( MaterialDiffuseAndHeight.rgb );
			}

			case T2_DEBUG_MATERIAL_HEIGHT: {
				return float3( MaterialDiffuseAndHeight.aaa );
			}

			case T2_DEBUG_MATERIAL_SOLID_LERP_2: {
				const int MATERIAL_COUNT = 2;
				float3 Col = float3( 0, 0, 0 );
				int4 Indices = ExtractMaterialIndices( MaterialMask, MATERIAL_COUNT );
				int MaterialCount = 0;
				for ( int i = 0; i < MATERIAL_COUNT; ++i )
				{
					if ( Indices[ i ] < 0 ) break;
					Col += IntToNiceColor( Indices[ i ] );
					MaterialCount++;
				}
				return Col / (float)max( MaterialCount, 1 );
			}

			case T2_DEBUG_MATERIAL_SOLID_LERP_3: {
				const int MATERIAL_COUNT = 3;
				float3 Col = float3( 0, 0, 0 );
				int4 Indices = ExtractMaterialIndices( MaterialMask, MATERIAL_COUNT );
				int MaterialCount = 0;
				for ( int i = 0; i < MATERIAL_COUNT; ++i )
				{
					if ( Indices[ i ] < 0 ) break;
					Col += IntToNiceColor( Indices[ i ] );
					MaterialCount++;
				}
				return Col / (float)max( MaterialCount, 1 );
			}

			case T2_DEBUG_MATERIAL_MASK_INFO: {
				int String[ 16 ];
				String[ 0 ] = ExtractAsciiHexCharIndex( MaterialMask, 3 );
				String[ 1 ] = ExtractAsciiHexCharIndex( MaterialMask, 2 );
				String[ 2 ] = ExtractAsciiHexCharIndex( MaterialMask, 1 );
				String[ 3 ] = ExtractAsciiHexCharIndex( MaterialMask, 0 );
				String[ 4 ] = 0; // NUL

				float PixelGridMask = CalculateGridMask( MaterialsTexel._Position, 1 );
				MaterialsTexel._PositionFrac.y = 1 - MaterialsTexel._PositionFrac.y;
				float StrMask = PutString( MaterialsTexel._PositionFrac, uint2( 2, 2 ), String );

				int2 QuadrantUV = (int2)(MaterialsTexel._PositionFrac * 2);
				int QuadrantIdx = ( QuadrantUV.x & 1u ) + ( QuadrantUV.y & 1u ) * 2;
				int4 Indices = ExtractMaterialIndices( MaterialMask, QuadrantIdx + 1 );

				float3 TextColor = Indices[ QuadrantIdx ] != -1 ? IntToNiceColor( Indices[ QuadrantIdx ] ) : float3( 0, 0, 0 );
				float3 BgColor = lerp( float3( 0.1, 0.1, 0.1 ), float3( 0.4, 0.4, 0.4 ), PixelGridMask );

				return lerp( BgColor, TextColor, StrMask );
			}

			case T2_DEBUG_CURVATURE_MAP: {
#ifdef TERRAIN2_CURVATURE_ENABLED
				SPhysicalTexel CurvatureTexel = CalcPhysicalCurvatureTexel( WorldSpacePosition, CalculateVirtualLayerDistanceMip( WorldSpacePosition, _VirtualCurvatureConstants ) );
				float Curvature = ToLinear( PdxTexture2DLoad0( VirtualCurvaturePhysicalTexture, CurvatureTexel._Position ).r );
				return float3( Curvature, Curvature, Curvature );
#else
				return float3( 1, 1, 1 );
#endif
			}
			
			case T2_DEBUG_BLEND_WEIGHTS: {
				int CountSamples = 0;
				const float TIGHTEN = 0.01;
				if ( BlendWeights.r > TIGHTEN )
				{
					CountSamples++;
				}
				if ( BlendWeights.g > TIGHTEN )
				{
					CountSamples++;
				}
				if ( BlendWeights.b > TIGHTEN )
				{
					CountSamples++;
				}
				switch( CountSamples )
				{
					case 1:
						return float3( 0, 1, 0 );
					case 2:
						return float3( 1, 1, 0 );
					case 3:
						return float3( 1, 0, 0 );
				}
			}
		}

		return float3( 0, 0, 0 );
	}

	void CalculateMaterials( float3 WorldSpacePosition, float3 WorldSpaceNormal, out float4 DiffuseAndHeight, out float3 Normal, out float4 Properties, out float3 BlendWeights )
	{
		CalculateMaterialsBilinear( WorldSpacePosition, WorldSpaceNormal, DiffuseAndHeight, Normal, Properties, BlendWeights );
	}
]]
