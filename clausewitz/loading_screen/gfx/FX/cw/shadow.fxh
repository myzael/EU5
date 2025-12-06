Includes = {
	"cw/random.fxh"
}

ConstantBuffer( PdxShadowmap )
{
	float		ShadowFadeFactor;
	float		Bias;
	float		KernelScale;
	float		ShadowScreenSpaceScale;
	int			NumSamples;
	
	float4		DiscSamples[8];
}

Code
[[
	float2 RotateDisc( float2 Disc, float2 Rotate )
	{
		return float2( Disc.x * Rotate.x - Disc.y * Rotate.y, Disc.x * Rotate.y + Disc.y * Rotate.x );
	}
	
	float CalculateShadow( float4 ShadowProj, PdxTextureSampler2DCmp ShadowMap )
	{
		ShadowProj.xyz = ShadowProj.xyz / ShadowProj.w;
		
		float RandomAngle = CalcRandom( round( ShadowScreenSpaceScale * ShadowProj.xy ) ) * 3.14159 * 2.0;
		float2 Rotate = float2( cos( RandomAngle ), sin( RandomAngle ) );

		// Sample each of them checking whether the pixel under test is shadowed or not
		float ShadowTerm = 0.0;
		for( int i = 0; i < NumSamples; i++ )
		{
			float4 Samples = DiscSamples[i] * KernelScale;
			ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + RotateDisc( Samples.xy, Rotate ), ShadowProj.z - Bias );
			ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + RotateDisc( Samples.zw, Rotate ), ShadowProj.z - Bias );
		}
		
		// Get the average
		ShadowTerm *= 0.5; // We have 2 samples per "sample"
		ShadowTerm = ShadowTerm / float(NumSamples);
		
		float3 FadeFactor = saturate( float3( 1.0 - abs( 0.5 - ShadowProj.xy ) * 2.0, 1.0 - ShadowProj.z ) * 32.0 ); // 32 is just a random strength on the fade
		ShadowTerm = lerp( 1.0, ShadowTerm, min( min( FadeFactor.x, FadeFactor.y ), FadeFactor.z ) );
		
		return lerp( 1.0, ShadowTerm, ShadowFadeFactor );
	}
]]
