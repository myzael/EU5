PixelShader = {
	VertexStruct PS_OUTPUT
	{
		float4 _Color		: PDX_COLOR0;	// Final shaded color, RGBA
	@ifdef GBUFFER_ENABLE_SSAO
		float4 _SSAOColor	: PDX_COLOR1;	// Not currently used in caesar
	@endif
	@ifdef GBUFFER_ENABLE_NORM_MAT_SPEC
		@ifdef GBUFFER_ENABLE_SSAO
			float4 _Normal		: PDX_COLOR2;	// Normal XYZ in world-space, Alpha reserved for blending
			float4 _Material 	: PDX_COLOR3;	// RGB = PerceptualRoughness, Roughness, Metalness, Alpha reserved for blending
			float4 _Specular	: PDX_COLOR4;	// Specular color, Alpha reserved for blending
		@else
			float4 _Normal		: PDX_COLOR1;	// Normal XYZ in world-space, Alpha reserved for blending
			float4 _Material 	: PDX_COLOR2;	// RGB = PerceptualRoughness, Roughness, Metalness, Alpha reserved for blending
			float4 _Specular	: PDX_COLOR3;	// Specular color, Alpha reserved for blending
		@endif
	@endif
	};
}
PixelShader = {
	Code 
	[[
		/*
		struct SMaterialProperties
		{
			float 	_PerceptualRoughness;
			float 	_Roughness;
			float	_Metalness;
		
			float3	_DiffuseColor;
			float3	_SpecularColor;
			float3	_Normal;
		};
		*/
		
		PS_OUTPUT PS_Return( float4 Color, in SMaterialProperties Material )
		{
			PS_OUTPUT Out;
			Out._Color = vec4(1.0f);
			Out._Color = Color;
			
			#ifdef GBUFFER_ENABLE_SSAO
			Out._SSAOColor = vec4( 1.0f );
			#endif
			
			#ifdef GBUFFER_ENABLE_NORM_MAT_SPEC
			Out._Normal.rgb = Material._Normal;
			Out._Normal.a 	= Color.a;
			
			Out._Material.r = Material._PerceptualRoughness;
			Out._Material.g = Material._Roughness;
			Out._Material.b = Material._Metalness;
			Out._Material.a = Color.a;
			
			Out._Specular.rgb = Material._SpecularColor;
			Out._Specular.a = Color.a;
			#endif
			
			return Out;
		}
		
		
		PS_OUTPUT PS_Return( float3 Color, float Alpha, in SMaterialProperties Material )
		{
			return PS_Return( float4( Color, Alpha ), Material );
		}
		PS_OUTPUT PS_Return( float4 Color )
		{
			PS_OUTPUT Out;
			Out._Color = vec4(1.0f);
			Out._Color = Color;
			#ifdef GBUFFER_ENABLE_SSAO
			Out._SSAOColor = vec4(1.0f);
			#endif
			#ifdef GBUFFER_ENABLE_NORM_MAT_SPEC
			Out._Normal = vec4(0.0f);
			Out._Material = vec4(0.0f);
			Out._Specular = vec4(0.0f);
			#endif
			return Out;
		}
		PS_OUTPUT PS_Return( float3 Color, float Alpha )
		{
			return PS_Return( float4( Color, Alpha ) );
		}
	]]
}