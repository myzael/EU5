Includes = {
	"cw/shadow.fxh"
}

ConstantBuffer( PdxShadowmapAtlas )
{
	uint4 _ShadowData[4]; # This buffer is usually larger than "4" but setting it to large values increases shader compilation times by at least an order of magnitude :(
}

TextureSampler ShadowMapAtlas
{
	Ref = PdxShadowmapAtlas
	MagFilter = "Linear"
	MinFilter = "Linear"
	MipFilter = "Linear"
	SampleModeU = "Clamp"
	SampleModeV = "Clamp"
	CompareFunction = less_equal
	SamplerType = "Compare"
}

Code
[[
	#define PDX_NO_SHADOW_INDEX UINT32_MAX
	
	struct SDirectionalShadowData
	{
		uint _DataOffset;
		float _KernelScale;
	};
	
	struct SProjectorShadowData
	{
		uint _DataOffset;
		float _KernelScale;
	};
	
	struct SCubeShadowData
	{
		uint _DataOffset;
		float _KernelScale;
		float2 _ProjectionFactors;
	};
	
	SDirectionalShadowData GetDirectionalShadowData( uint ShadowIndex )
	{
		SDirectionalShadowData DirectionalShadowData;
		DirectionalShadowData._DataOffset = _ShadowData[ ShadowIndex ].x;
		DirectionalShadowData._KernelScale = asfloat( _ShadowData[ ShadowIndex ].y );
		return DirectionalShadowData;
	}
	
	SProjectorShadowData GetProjectorShadowData( uint ShadowIndex )
	{
		SProjectorShadowData ProjectorShadowData;
		ProjectorShadowData._DataOffset = _ShadowData[ ShadowIndex ].x;
		ProjectorShadowData._KernelScale = asfloat( _ShadowData[ ShadowIndex ].y );
		return ProjectorShadowData;
	}
	
	SCubeShadowData GetCubeShadowData( uint ShadowIndex )
	{
		SCubeShadowData CubeShadowData;
		CubeShadowData._DataOffset = _ShadowData[ ShadowIndex ].x;
		CubeShadowData._KernelScale = asfloat( _ShadowData[ ShadowIndex ].y );
		CubeShadowData._ProjectionFactors = asfloat( _ShadowData[ ShadowIndex ].zw );
		return CubeShadowData;
	}
	
	float4 GetOffsetAndScale( uint DataIndex )
	{
		return asfloat( _ShadowData[ DataIndex ] );
	}
	
	float4x4 GetShadowMapTextureMatrix( uint StartIndex )
	{
		return Create4x4( 
			asfloat( _ShadowData[ StartIndex ] ), 
			asfloat( _ShadowData[ StartIndex + 1 ] ), 
			asfloat( _ShadowData[ StartIndex + 2 ] ), 
			asfloat( _ShadowData[ StartIndex + 3 ] ) 
		);
	}
	
	float4 GetOffsetAndScale( SCubeShadowData CubeShadowData, uint FaceIndex )
	{
		return GetOffsetAndScale( CubeShadowData._DataOffset + FaceIndex );
	}
	
	float SampleShadowMapAtlas( float2 UV, float Depth, float2 Offset, float2 Scale, float KernelScale )
	{
		//return PdxTex2DCmpLod0( ShadowMapAtlas, UV * Scale + Offset, Depth - Bias );
		
		float RandomAngle = CalcRandom( round( ShadowScreenSpaceScale * UV ) ) * 3.14159 * 2.0;
		float2 Rotate = float2( cos( RandomAngle ), sin( RandomAngle ) );
		
		// Sample each of them checking whether the pixel under test is shadowed or not
		float ShadowTerm = 0.0;
		for( int i = 0; i < NumSamples; i++ )
		{
			float4 Samples = DiscSamples[i] * KernelScale;
			
			float2 OffsetUV = saturate( UV + RotateDisc( Samples.xy, Rotate ) );
			float2 SampleUV = OffsetUV * Scale + Offset;
			ShadowTerm += PdxTex2DCmpLod0( ShadowMapAtlas, SampleUV, Depth - Bias );
			
			OffsetUV = saturate( UV + RotateDisc( Samples.zw, Rotate ) );
			SampleUV = OffsetUV * Scale + Offset;
			ShadowTerm += PdxTex2DCmpLod0( ShadowMapAtlas, SampleUV, Depth - Bias );
		}
		
		// Get the average
		ShadowTerm *= 0.5; // We have 2 samples per "sample"
		ShadowTerm = ShadowTerm / float( NumSamples );
		
		return lerp( 1.0, ShadowTerm, ShadowFadeFactor );
	}
	
	// This will calculate the UV and FaceIndex for a Cube face from LightSpacePosition (https://www.gamedev.net/forums/topic/687535-implementing-a-cube-map-lookup-function/5337472/)
	float2 SampleCube( float3 LightSpacePosition, out uint FaceIndex )
	{
		float3 AbsPosition = abs( LightSpacePosition );
		float2 UV;
		if ( AbsPosition.z >= AbsPosition.x && AbsPosition.z >= AbsPosition.y )
		{
			FaceIndex = LightSpacePosition.z < 0.0 ? 5 : 4;
			UV = float2( LightSpacePosition.z < 0.0 ? -LightSpacePosition.x : LightSpacePosition.x, -LightSpacePosition.y ) * ( 0.5 / AbsPosition.z );
		}
		else if ( AbsPosition.y >= AbsPosition.x )
		{
			FaceIndex = LightSpacePosition.y < 0.0 ? 3 : 2;
			UV = float2( LightSpacePosition.x, LightSpacePosition.y < 0.0 ? -LightSpacePosition.z : LightSpacePosition.z ) * ( 0.5 / AbsPosition.y );
		}
		else
		{
			FaceIndex = LightSpacePosition.x < 0.0 ? 1 : 0;
			UV = float2( LightSpacePosition.x < 0.0 ? LightSpacePosition.z : -LightSpacePosition.z, -LightSpacePosition.y ) * ( 0.5 / AbsPosition.x );
		}
		return UV + 0.5;
	}
	
	// Calculate shadow map space projected depth (https://community.khronos.org/t/glsl-cube-shadows-projecting/64080/14)
	float CalcCubeShadowDepth( float3 LightSpacePosition, float2 ProjectionFactors )
	{
		float3 AbsPosition = abs( LightSpacePosition );
		float MaxZ = max( AbsPosition.x, max( AbsPosition.y, AbsPosition.z ) );

		// This is equivalent with - float4 ClipPos = "ProjectionMatrix" * float4( AbsPosition, 1.0 ); return ClipPos.z / ClipPos.w;
		return ( ProjectionFactors.x + ProjectionFactors.y / MaxZ );
	}
	
	float CalcDepthFadeFactor( float Depth )
	{
		return ( 1.0 - Depth );
	}
	
	float CalculateDirectionalShadow( float3 WorldSpacePos, uint ShadowIndex )
	{
	#ifdef PDX_LIGHTSOURCE_SHADOWS_ENABLED
		if ( ShadowIndex != PDX_NO_SHADOW_INDEX )
		{
			SDirectionalShadowData DirectionalShadowData = GetDirectionalShadowData( ShadowIndex );
			
			float4 OffsetAndScale = GetOffsetAndScale( DirectionalShadowData._DataOffset );	
			float4x4 ShadowMapTextureMatrix = GetShadowMapTextureMatrix( DirectionalShadowData._DataOffset + 1 ); // +1 since first data is offset and scale
			
			float4 ShadowProj = mul( ShadowMapTextureMatrix, float4( WorldSpacePos, 1.0 ) );
			float ShadowTerm = SampleShadowMapAtlas( ShadowProj.xy, ShadowProj.z, OffsetAndScale.xy, OffsetAndScale.zw, DirectionalShadowData._KernelScale );
			
			float3 FadeFactor = saturate( float3( ( 1.0 - abs( 0.5 - ShadowProj.xy ) * 2.0 ), 1.0 - ShadowProj.z ) * 32.0 ); // 32 is just a random strength on the fade
			ShadowTerm = lerp( 1.0, ShadowTerm, min( min( FadeFactor.x, FadeFactor.y ), FadeFactor.z ) );
		
			return ShadowTerm;
		}
	#endif
	
		return 1.0;
	}
	
	float CalculateProjectorShadow( float3 WorldSpacePos, uint ShadowIndex )
	{
	#ifdef PDX_LIGHTSOURCE_SHADOWS_ENABLED
		if ( ShadowIndex != PDX_NO_SHADOW_INDEX )
		{
			SProjectorShadowData ProjectorShadowData = GetProjectorShadowData( ShadowIndex );
			
			float4 OffsetAndScale = GetOffsetAndScale( ProjectorShadowData._DataOffset );	
			float4x4 ShadowMapTextureMatrix = GetShadowMapTextureMatrix( ProjectorShadowData._DataOffset + 1 ); // +1 since first data is offset and scale
	
			float4 ShadowProj = mul( ShadowMapTextureMatrix, float4( WorldSpacePos, 1.0 ) );
			ShadowProj.xyz /= ShadowProj.w;
			
			float ShadowTerm = SampleShadowMapAtlas( ShadowProj.xy, ShadowProj.z, OffsetAndScale.xy, OffsetAndScale.zw, ProjectorShadowData._KernelScale );
			
			float2 FadeFactor = saturate( ( 1.0 - abs( 0.5 - ShadowProj.xy ) * 2.0 ) * 32.0 ); // 32 is just a random strength on the fade
			ShadowTerm = lerp( 1.0, ShadowTerm, min( FadeFactor.x, FadeFactor.y ) );

			return ShadowTerm;
		}
	#endif
	
		return 1.0;
	}
	
	float CalculateCubeShadow( float3 WorldSpacePos, float3 LightPosition, uint ShadowIndex )
	{
	#ifdef PDX_LIGHTSOURCE_SHADOWS_ENABLED
		if ( ShadowIndex != PDX_NO_SHADOW_INDEX )
		{
			SCubeShadowData CubeShadowData = GetCubeShadowData( ShadowIndex );
			
			float3 LightSpacePosition = WorldSpacePos - LightPosition;
			
			uint FaceIndex = 0;
			float2 UV = SampleCube( LightSpacePosition, FaceIndex );
			float Depth = CalcCubeShadowDepth( LightSpacePosition, CubeShadowData._ProjectionFactors );

			float4 OffsetAndScale = GetOffsetAndScale( CubeShadowData, FaceIndex );
			float ShadowTerm = SampleShadowMapAtlas( UV, Depth, OffsetAndScale.xy, OffsetAndScale.zw, CubeShadowData._KernelScale );
			
			return ShadowTerm;
		}
	#endif
	
		return 1.0;
	}
]]
