struct STerrain2VirtualLayerConstants
{
	float _LodScale;
	float3 _Pad0;
	SVirtualTextureClipmapConstants _ClipmapConstants;
}

Code
[[
	// Given a worldspace position, calculates an appropriate mip level which will definitely be included in the layer's clipmap.
	float CalculateVirtualLayerDistanceMip( float3 WorldSpacePosition, STerrain2VirtualLayerConstants LayerConstants )
	{
		#define MIP_STRATEGY_2D 0
		#define MIP_STRATEGY_3D 1
		#define MIP_STRATEGY_HIGHEST 3

		#define MIP_STRATEGY MIP_STRATEGY_3D

		float MipUnclamped;

#if MIP_STRATEGY == MIP_STRATEGY_2D
		// log2 of distance to sample, ignoring height component
		float2 LodVector = WorldSpacePosition.xz - _LodPosition.xz;
		float DistanceSqr = dot( LodVector, LodVector ); // We can avoid doing a square root by taking advantage of the log properties log(sqrt(a)) = log(a)* 1/2
		MipUnclamped = max( 0.0f, log2( DistanceSqr * LayerConstants._LodScale * LayerConstants._LodScale ) * 0.5 + 1.0 );
#elif MIP_STRATEGY == MIP_STRATEGY_3D
		// log2 of distance to sample
		float3 LodVector = WorldSpacePosition - _LodPosition;
		float DistanceSqr = dot( LodVector, LodVector ); // We can avoid doing a square root by taking advantage of the log properties log(sqrt(a)) = log(a)* 1/2
		MipUnclamped = max( 0.0f, log2( DistanceSqr * LayerConstants._LodScale * LayerConstants._LodScale ) * 0.5 + 1.0 );
#elif MIP_STRATEGY == MIP_STRATEGY_HIGHEST
		// Find finest mip possible at sample which is covered by virtual texture indirection texel
		#error "Not implemented"
#else
		#error "Invalid mip strategy"
#endif

		return min( MipUnclamped, LayerConstants._ClipmapConstants._NumMipLevels - 1 );
	}

	struct SPhysicalTexel
	{
		uint2 _Position;
		float2 _PositionFrac;
		int _PageMip;
	};

	SPhysicalTexel _CalcPhysicalTexel( float3 WorldSpacePosition, Texture2DArray<uint4> VirtualLayerIndirectionTexture, STerrain2VirtualLayerConstants LayerConstants, uint Mip )
	{
		SPhysicalTexel Texel;

		float2 VirtualUV = WorldSpacePosition.xz * _InvQuadTreeSize;

		// TODO, to make mip0 match up with previous version after adding the -= 0.5 below
		VirtualUV += 0.5 / float( LayerConstants._ClipmapConstants._FullIndirectionSize * LayerConstants._ClipmapConstants._PageSize );

		uint4 IndirectionData = SampleIndirectionData( VirtualUV, Mip, VirtualLayerIndirectionTexture, LayerConstants._ClipmapConstants );
		float2 PhysicalTexel = CalculatePhysicalTexels( VirtualUV, IndirectionData.xy, IndirectionData.z, LayerConstants._ClipmapConstants );
		Texel._PageMip = IndirectionData.z;

		// This is currently needed so that the masks does not "move" when switching lods
		PhysicalTexel -= 0.5;

		float2 PhysicalTexelFloored = floor( PhysicalTexel );
		Texel._PositionFrac = PhysicalTexel - PhysicalTexelFloored;

		Texel._Position = (uint2)( PhysicalTexelFloored );

		return Texel;
	}
]]
