Includes = {
	"cw/utility.fxh"
}

Sampler PdxVtLinearSampler
{
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
}

struct SVirtualTextureClipmapConstants
{
	uint2 _PhysicalTextureSize;
	float2 _InvPhysicalTextureSize;
	uint2 _ClipmapPosition;
	uint _IndirectionTextureSize;
	uint _PageSize;
	uint _PageBorder;
	uint _PhysicalPageSize;
	uint _FullIndirectionSize;
	uint _NumMipLevels;
	uint _VirtualTextureSize;
	float _InvVirtualTextureSize;
}

Code
[[
	#ifdef PIXEL_SHADER
		//#define DEBUG_FRAC_COORDS
		//#define DEBUG_VIRTUAL_PAGES
		//#define DEBUG_VIRTUAL_TEXELS
		//#define DEBUG_PHYSICAL_PAGES
		//#define DEBUG_PHYSICAL_TEXELS
	#endif

	// Just try to get some identifier to differentiate different pages
	uint Debug_CalculatePageIdentifier( float2 VirtualUV, uint Mip, SVirtualTextureClipmapConstants Constants )
	{
		uint MipSize = ( Constants._FullIndirectionSize >> Mip );
		uint2 xy = uint2( VirtualUV * float2( MipSize, MipSize ) );
		return Constants._FullIndirectionSize * Constants._FullIndirectionSize * Mip + xy.y * MipSize.x + xy.x;
	}

	float Debug_GetTexelBorder( float2 UV, float2 TextureSize, float BorderSize )
	{
		float2 FracScaledUV = frac( UV * TextureSize );
		if ( FracScaledUV.x < BorderSize || FracScaledUV.x > (1.0 - BorderSize) || FracScaledUV.y < BorderSize || FracScaledUV.y > (1.0 - BorderSize) )
		{
			return 1.0;
		}
		else
		{
			return 0.0;
		}
	}
	float4 Debug_VirtualPages( float2 VirtualUV, uint Mip, SVirtualTextureClipmapConstants Constants )
	{
		uint Id = Debug_CalculatePageIdentifier( VirtualUV, Mip, Constants );
		return float4( HSVtoRGB( ( Id / 4.7 ), 1.0, 1.0, 1.0 ) );
	}
	float4 Debug_VirtualTexels( float2 VirtualUV, uint Mip, SVirtualTextureClipmapConstants Constants )
	{
		uint MipSize = ( Constants._FullIndirectionSize >> Mip );
		float TexelBorder = Debug_GetTexelBorder( VirtualUV, vec2( MipSize * Constants._PageSize ), 0.05 );
		return Debug_VirtualPages( VirtualUV, Mip, Constants ) * float4( vec3( TexelBorder ), 1.0 );
	}
	float4 Debug_PhysicalPages( uint4 IndirectionData, SVirtualTextureClipmapConstants Constants )
	{
		uint PhysicalPageOffset = IndirectionData.y * ( Constants._PhysicalTextureSize.x / Constants._PhysicalPageSize ) + IndirectionData.x;
		return float4( HSVtoRGB( ( PhysicalPageOffset / 4.7 ), 1.0, 1.0, 1.0 ) );
	}
	float4 Debug_PhysicalTexels( uint4 IndirectionData, float2 PhysicalUV, SVirtualTextureClipmapConstants Constants )
	{
		float TexelBorder = Debug_GetTexelBorder( PhysicalUV, Constants._PhysicalTextureSize, 0.05 );
		return Debug_PhysicalPages( IndirectionData, Constants ) * float4( vec3( TexelBorder ), 1.0 );
	}

	float2 CalculatePhysicalTexels( float2 UV, uint2 PhysicalPageIndex, uint PhysicalPageMipLevel, SVirtualTextureClipmapConstants Constants )
	{
		// Calculate the fractional coordinates (i.e. coordinates used to sample the physical page)
		uint ActualMipSize = ( Constants._FullIndirectionSize >> PhysicalPageMipLevel );
		float2 MipTexelCoords = UV * ActualMipSize;
		float2 FracCoords = frac( MipTexelCoords );
	#ifdef DEBUG_FRAC_COORDS
		return FracCoords;
	#endif

		// Calculate texel coordinate in physical texture
		float2 PhysicalUV = PhysicalPageIndex * Constants._PhysicalPageSize + Constants._PageBorder + FracCoords * Constants._PageSize;
		return PhysicalUV;
	}

	float2 CalculatePhysicalUV( float2 UV, uint2 PhysicalPageIndex, uint PhysicalPageMipLevel, SVirtualTextureClipmapConstants Constants )
	{
		return CalculatePhysicalTexels( UV, PhysicalPageIndex, PhysicalPageMipLevel, Constants ) * Constants._InvPhysicalTextureSize;
	}

	uint4 SampleIndirectionData( float2 VirtualUV, uint Mip, Texture2DArray<uint4> IndirectionTexture, SVirtualTextureClipmapConstants Constants )
	{
		// Calculate indirection coordinates and sample indirection texture
		uint MipSize = ( Constants._FullIndirectionSize >> Mip );
		uint2 IndirectionCoord = uint2( VirtualUV * MipSize ) % Constants._IndirectionTextureSize;
		// We do load since pointsampling does not match frac calculation on some hardware? (Intel)
		return uint4( PdxTexture2DArrayLoad0( IndirectionTexture, IndirectionCoord, Mip ) );
	}

	struct SVirtualTextureSampleParameters
	{
		uint4 _IndirectionData;
		float2 _PhysicalUV;

		float2 _NextLevelPhysicalUV;
		float _LerpFactor;
	};

	void CalculateSampleParameters( float2 VirtualUV, float Lod, Texture2DArray<uint4> IndirectionTexture, SVirtualTextureClipmapConstants Constants, inout SVirtualTextureSampleParameters SampleParams )
	{
		// Limit mip to available range
		uint LodTruncated = uint( Lod );
		uint Mip = min( Constants._NumMipLevels - 1, LodTruncated );

		uint4 IndirectionData = SampleIndirectionData( VirtualUV, Mip, IndirectionTexture, Constants );
		SampleParams._IndirectionData = IndirectionData;
		SampleParams._PhysicalUV = CalculatePhysicalUV( VirtualUV, IndirectionData.xy, IndirectionData.z, Constants );

		// TODO, this is not really classical trilinear but it was a better fit for the terrain
		SampleParams._LerpFactor = smoothstep( 0.5, 1.0, Lod - LodTruncated );
		if ( SampleParams._LerpFactor > 0.0 )
		{
			uint NextLevelMip = min( Constants._NumMipLevels - 1, Mip + 1 );
			uint4 NextLevelIndirectionData = SampleIndirectionData( VirtualUV, NextLevelMip, IndirectionTexture, Constants );

			SampleParams._NextLevelPhysicalUV = CalculatePhysicalUV( VirtualUV, NextLevelIndirectionData.xy, NextLevelIndirectionData.z, Constants );
		}
		else
		{
			SampleParams._NextLevelPhysicalUV = SampleParams._PhysicalUV;
		}
	}

	// This version uses "precalculated" sampling parameters, can be used to share calculations when sampling from virtual texture with multiple physical textures
	// Not sure if it is actually needed since compiler is pretty good at optimizing
	float4 SampleVirtualTextureLod( Texture2D PhysicalTexture, SVirtualTextureSampleParameters SampleParams )
	{
		float4 Sample;
		Sample = PdxSampleTex2DLod0( PhysicalTexture, PdxVtLinearSampler, SampleParams._PhysicalUV );

		if ( SampleParams._LerpFactor > 0.0 )
		{
			float4 NextLevelSample = PdxSampleTex2DLod0( PhysicalTexture, PdxVtLinearSampler, SampleParams._NextLevelPhysicalUV );
			Sample = lerp( Sample, NextLevelSample, SampleParams._LerpFactor );
		}

		return Sample;
	}

	float4 SampleVirtualTextureLod( float2 VirtualUV, float Lod, Texture2DArray<uint4> IndirectionTexture, Texture2D PhysicalTexture, SVirtualTextureClipmapConstants Constants )
	{
	#ifdef DEBUG_VIRTUAL_PAGES
		return Debug_VirtualPages( VirtualUV, Lod, Constants );
	#endif
	#ifdef DEBUG_VIRTUAL_TEXELS
		return Debug_VirtualTexels( VirtualUV, Lod, Constants );
	#endif

		SVirtualTextureSampleParameters SampleParams;
		CalculateSampleParameters( VirtualUV, Lod, IndirectionTexture, Constants, SampleParams );

	#ifdef DEBUG_FRAC_COORDS
		return float4( SampleParams._PhysicalUV, 0, 1 );
	#endif
	#ifdef DEBUG_PHYSICAL_PAGES
		return Debug_PhysicalPages( SampleParams._IndirectionData, Constants );
	#endif
	#ifdef DEBUG_PHYSICAL_TEXELS
		return Debug_PhysicalTexels( SampleParams._IndirectionData, SampleParams._PhysicalUV, Constants );
	#endif

		return SampleVirtualTextureLod( PhysicalTexture, SampleParams );
	}
]]
