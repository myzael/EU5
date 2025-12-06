Includes = {
	"jomini/jomini_lighting.fxh"
}

PixelShader = {
	Code [[			
		void ApplySpecularBackLight( inout float3 FinalColor, in SMaterialProperties MaterialProps, in SLightingProperties LightingProps )
		{
			float SpecularBackLightIntensity = RemapClamped( MaterialProps._Roughness, GetSpecularBacklightRoughnessMin(), GetSpecularBacklightRoughnessMax(), GetSpecularBacklightIntensityMin(), GetSpecularBacklightIntensityMax() );
			if( SpecularBackLightIntensity > 0.0f )
			{
				float3 BackLightDiffuse;
				float3 BackLightSpecular;
				LightingProps._LightIntensity = GetSpecularBackLightDiffuse() * SpecularBackLightIntensity;
				LightingProps._ToLightDir = reflect( -LightingProps._ToCameraDir, float3( 0, 1, 0 ) );
				//LightingProps._ToLightDir = reflect( CameraLookAtDir, float3( 0, 1, 0 ) );
				CalculateLightingFromLight( MaterialProps, LightingProps, BackLightDiffuse, BackLightSpecular );
				FinalColor += BackLightSpecular;
			}
		}
	]]
}