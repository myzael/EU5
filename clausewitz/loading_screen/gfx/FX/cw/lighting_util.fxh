Includes = {
	"cw/lighting.fxh"
	"cw/camera.fxh"
}

PixelShader =
{
	Code
	[[
		float4x4 Float4x4Identity()
		{
			return float4x4( 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0 );
		}

		SMaterialProperties GetMaterialProperties( float3 SampledDiffuse, float3 Normal, float SampledRoughness, float SampledSpec, float SampledMetalness )
		{
			SMaterialProperties MaterialProps;
			
			MaterialProps._PerceptualRoughness = SampledRoughness;
			MaterialProps._Roughness = RoughnessFromPerceptualRoughness( MaterialProps._PerceptualRoughness );

			float SpecRemapped = RemapSpec( SampledSpec );
			MaterialProps._Metalness = SampledMetalness;

			MaterialProps._DiffuseColor = MetalnessToDiffuse( MaterialProps._Metalness, SampledDiffuse );
			MaterialProps._SpecularColor = MetalnessToSpec( MaterialProps._Metalness, SampledDiffuse, SpecRemapped );
			
			MaterialProps._Normal = Normal;
			
			return MaterialProps;
		}
	]]
}