Includes = {
	"cw/utility.fxh"
	"cw/upscale_utils.fxh"
}

ConstantBuffer( PdxDecalCullingConstants )
{
	uint2 _TileSizeDecals;
	uint2 _ClusterIndexStrideDecals; 			# .x = _NumTiles.y * _NumDepthSplits, .y = _NumDepthSplits, z is implicit 1
	float _ClusterMinDepthDecals;				# The minimum view space depth where the cluster generation starts
	float _ClusterDepthToClusterIndexDecals; 	# Multiply ("ViewSpaceDepth" - _ClusterMinDepthDecals) with this one to get the z cluster index
}


BufferTexture DecalList
{
	Ref = PdxDecalList
	type = float4
}

# This one effectively contains a list of "ListEntry", where each entry specifies the decals for that entry
# struct "ListEntry"
# {
# 	uint _NumDecals;
# 	uint _DecalDataIndex[ _NumDecals ];
# }
BufferTexture DecalPerClusterList
{
	Ref = PdxDecalPerClusterList
	type = uint
}

# This one contains an entry for each cluster, the entry is the index for this cluster's "ListEntry" in the DecalPerClusterList
BufferTexture ClusterToDecalsPerClusterList
{
	Ref = PdxClusterToDecalsPerClusterList
	type = uint
}


# TODO, this is just to get something up quick and dirty
Sampler DecalSampler
{
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}
Texture DecalAlbedoTextures
{
	Ref = PdxDecalTestArrayTextures0
	ResourceArraySize = 10
}
Texture DecalNormalTextures
{
	Ref = PdxDecalTestArrayTextures1
	ResourceArraySize = 10
}
Texture DecalPropertiesTextures
{
	Ref = PdxDecalTestArrayTextures2
	ResourceArraySize = 10
}


Code
[[
	struct SDecal
	{
		float4x4 _DecalMatrix;
		float _DecalIndex;
		float _AlbedoFactor;
		float _NormalFactor;
		float _PropertiesFactor;
	};
	
	SDecal BuildDecal( float4x4 DecalMatrix, float DecalIndex, float AlbedoFactor, float NormalFactor, float PropertiesFactor )
	{
		SDecal Decal;
		Decal._DecalMatrix = DecalMatrix;
		Decal._DecalIndex = DecalIndex;
		Decal._AlbedoFactor = AlbedoFactor;
		Decal._NormalFactor = NormalFactor;
		Decal._PropertiesFactor = PropertiesFactor;
		return Decal;
	}

	// Helper function to get decal data starting at DecalDataIndex
	SDecal GetDecal( uint DecalDataIndex )
	{
		float4x4 DecalMatrix = Create4x4(
			PdxReadBuffer4( DecalList, DecalDataIndex ),
			PdxReadBuffer4( DecalList, DecalDataIndex + 1 ),
			PdxReadBuffer4( DecalList, DecalDataIndex + 2 ),
			PdxReadBuffer4( DecalList, DecalDataIndex + 3 )
		);
		float4 IndexAndFactors = PdxReadBuffer4( DecalList, DecalDataIndex + 4 );
		return BuildDecal( DecalMatrix, IndexAndFactors.x, IndexAndFactors.y, IndexAndFactors.z, IndexAndFactors.w );
	}
	
	// Calculate the 3d "cluster index" for the cluster containing [PixelPos.xy, ViewSpaceDepth]
	uint3 CalculateDecalsClusterIndexForPixel( uint2 PixelPos, float ViewSpaceDepth )
	{
		return uint3( PixelPos / _TileSizeDecals, ( ViewSpaceDepth - _ClusterMinDepthDecals ) * _ClusterDepthToClusterIndexDecals );
	}
	// Calculate the "linear" offset for the 3d cluster index "ClusterIndex" (i.e. index into ClusterToDecalsPerClusterList)
	uint CalculateDecalsOffsetForClusterIndex( uint3 ClusterIndex )
	{
		return ClusterIndex.x * _ClusterIndexStrideDecals.x + ClusterIndex.y * _ClusterIndexStrideDecals.y + ClusterIndex.z;
	}
	// Calculate the "linear" offset for the cluster containing [PixelPos.xy, ViewSpaceDepth] (i.e. index into ClusterToDecalsPerClusterList)
	uint CalculateDecalsOffsetForClusterForPixel( uint2 PixelPos, float ViewSpaceDepth )
	{
		return CalculateDecalsOffsetForClusterIndex( CalculateDecalsClusterIndexForPixel( PixelPos, ViewSpaceDepth ) );
	}

	// Calculate the DecalsPerClusterList index for where decal data can be found for the cluster containing [PixelPos, ViewSpaceDepth]
	uint CalculateDecalsPerClusterListIndexForCluster( float2 PixelPos, float ViewSpaceDepth )
	{
		// Calculate the "ClusterToDecalsPerClusterList" offset for the current cluster
		uint ClusterOffset = CalculateDecalsOffsetForClusterForPixel( PixelPos, ViewSpaceDepth );
		
		// Lookup where this clusters decal data is stored, ClusterToDecalsPerClusterList contains an entry for each cluster that is the offset of that clusters data in the DecalsPerClusterList
		uint DecalsPerClusterListIndex = PdxReadBuffer( ClusterToDecalsPerClusterList, ClusterOffset );
		return DecalsPerClusterListIndex;
	}
	
	
	// Macros to make different usage of decals easier, expected usage is:
	//	PDX_DECAL_LOOP_BEGIN( PixelPos, ViewSpaceDepth )
	// 	PDX_DECAL_LOOP
	// 	Do code that uses decal here, variable "Decal" is the SDecal for the current decal
	//	PDX_DECAL_LOOP_END
	
	#define PDX_DECAL_LOOP_BEGIN( PixelPos, ViewSpaceDepth )                                                                    \
		uint DecalsPerClusterListIndex = CalculateDecalsPerClusterListIndexForCluster( ( PixelPos ), ( ViewSpaceDepth ) );		\
		/* First entry in the list is the number of decals for the cluster */													\
		uint NumDecals = PdxReadBuffer( DecalPerClusterList, DecalsPerClusterListIndex );

	#define PDX_DECAL_LOOP                                                                                          			\
		/* The rest of the entries are the decal data indices */                                              					\
		uint Offset = DecalsPerClusterListIndex + 1;  /* +1 to jump over the "NumDecals" */  									\
		for ( uint i = 0; i < NumDecals; ++i )                                                         							\
		{                                                                                                   					\
			uint DecalDataIndex = PdxReadBuffer( DecalPerClusterList, Offset + i );                      						\
			SDecal Decal = GetDecal( DecalDataIndex );

	#define PDX_DECAL_LOOP_END                                                                                           		\
		}
		
		
	// From http://www.thetenthplanet.de/archives/1180
	float3x3 CalcCotangentFrame( float3 Normal, float3 WorldSpacePosDx, float3 WorldSpacePosDy, float2 UvDx, float2 UvDy )
	{
		// solve the linear system
		float3 DyPerp = cross( WorldSpacePosDy, Normal );
		float3 DxPerp = cross( Normal, WorldSpacePosDx );
		float3 T = DyPerp * UvDx.x + DxPerp * UvDy.x;
		float3 B = DyPerp * UvDx.y + DxPerp * UvDy.y;
	 
		// construct a scale-invariant frame 
		float InvMax = 1.0 / sqrt( max( dot(T,T), dot(B,B) ) );
		return Create3x3( T * InvMax, B * InvMax, Normal );
	}
	
	float CalcFadeFactor( float ZValue )
	{
		return smoothstep( 0.0, 1.0, saturate( ( 1.0 - abs( ZValue - 0.5 ) * 2.0 ) * 10.0 ) );
	}
	
	// Helper function to loop over all decals for the current tile/cluster (tile containing [PixelPos]/cluster containing [PixelPos.xy, ViewSpaceDepth]) and perform "default" decal blending
	void CalculateDecals( float2 PixelPos, float ViewSpaceDepth, float3 WorldSpacePos, float3 Normal, inout float3 DiffuseOut, inout float3 NormalOut, inout float4 PropertiesOut )
	{
		float3 WorldSpacePosDx = ddx( WorldSpacePos );
		float3 WorldSpacePosDy = ddy( WorldSpacePos );
		
		PDX_DECAL_LOOP_BEGIN( PixelPos, ViewSpaceDepth )
		PDX_DECAL_LOOP
			float3 DecalUVZ = mul( Decal._DecalMatrix, float4( WorldSpacePos, 1.0 ) ).xyz;
			if ( any( DecalUVZ < vec3( 0.0 ) ) || any( DecalUVZ > vec3( 1.0 ) ) )
			{
				continue;
			}
			
			float2 DecalUV = DecalUVZ.xy;
			float FadeFactor = CalcFadeFactor( DecalUVZ.z );
			float2 DecalUVDx = ApplyUpscaleLodBiasMultiplier( mul( Decal._DecalMatrix, float4( WorldSpacePosDx, 0.0 ) ).xy );
			float2 DecalUVDy = ApplyUpscaleLodBiasMultiplier( mul( Decal._DecalMatrix, float4( WorldSpacePosDy, 0.0 ) ).xy );
			
			uint DecalIndex = Decal._DecalIndex;
			float4 Diffuse = PdxSampleTex2DGrad( DecalAlbedoTextures[ NonUniformResourceIndex( DecalIndex) ], DecalSampler, DecalUV, DecalUVDx, DecalUVDy );
			float4 Properties = PdxSampleTex2DGrad( DecalPropertiesTextures[ NonUniformResourceIndex( DecalIndex) ], DecalSampler, DecalUV, DecalUVDx, DecalUVDy );
			float3 NormalSample = UnpackRRxGNormal( PdxSampleTex2DGrad( DecalNormalTextures[ NonUniformResourceIndex( DecalIndex) ], DecalSampler, DecalUV, DecalUVDx, DecalUVDy ) );

			// TODO, figure out what "base" normal to use for cotangent frame, currently uses "normalmapped" normal (NormalOut), but could also use "vertex normal" (Normal) or any other normal...
			float3x3 TBN = CalcCotangentFrame( NormalOut, WorldSpacePosDx, WorldSpacePosDy, DecalUVDx, DecalUVDy );
			
			float LerpFactor = FadeFactor *  Diffuse.a;
			DiffuseOut = lerp( DiffuseOut, Diffuse.rgb, LerpFactor * Decal._AlbedoFactor );
			PropertiesOut = lerp( PropertiesOut, Properties, LerpFactor * Decal._PropertiesFactor );
			NormalOut = lerp( NormalOut, normalize( mul( NormalSample, TBN ) ), LerpFactor * Decal._NormalFactor );
		
		PDX_DECAL_LOOP_END
	}
	
	// This one will use currently bound camera constants to calculate ViewSpaceDepth from WorldSpacePos
	void CalculateDecals( float2 PixelPos, float3 WorldSpacePos, float3 Normal, inout float3 DiffuseOut, inout float3 NormalOut, inout float4 PropertiesOut )
	{
		CalculateDecals( PixelPos, mul( ViewMatrix, float4( WorldSpacePos, 1.0 ) ).z, WorldSpacePos, Normal, DiffuseOut, NormalOut, PropertiesOut );
	}
]]
