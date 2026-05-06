Includes = {
	"coat_of_arms/coat_of_arms.fxh"
}

ConstantBuffer( CoatOfArmsPatternConstants )
{
	float4 	Color1;
	float4	Color2;
	float4	Color3;
	float4	FallbackColor;
}

VertexStruct VS_OUTPUT_COA_ATLAS
{
    float4 position			: PDX_POSITION;
	float2 uvPattern				: TEXCOORD0;
};

VertexShader = {
	VertexStruct VS_INPUT_COA_ATLAS
	{
		float2 position	: POSITION;
	};

	Code
	[[
		VS_OUTPUT_COA_ATLAS COAVertexShader( VS_INPUT_COA_ATLAS Input )
		{
			VS_OUTPUT_COA_ATLAS VertexOut;
			VertexOut.position = float4( Input.position, 0, 1.0 );
			VertexOut.uvPattern.x = VertexOut.position.x > -1 ? 1 : 0;
			VertexOut.uvPattern.y = VertexOut.position.y < 1 ? 1 : 0;
			return VertexOut;
		}
	]]

	MainCode VertexShaderCOAPattern
	{
		Input = "VS_INPUT_COA_ATLAS"
		Output = "VS_OUTPUT_COA_ATLAS"
		Code
		[[
			PDX_MAIN
			{
				return COAVertexShader( Input );
			}
		]]
	}
}

PixelShader =
{
	TextureSampler PatternMap
	{
		Ref = JominiPatternMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	Code
	[[
		float4 Pattern( VS_OUTPUT_COA_ATLAS Input, float4 PatternTex )
		{
			float4 PatternColored = FallbackColor;
			PatternColored = lerp( PatternColored, Color1, PatternTex.r );
			PatternColored = lerp( PatternColored, Color2, PatternTex.g );
			PatternColored = lerp( PatternColored, Color3, PatternTex.b );
			return PatternColored;
		}
		float4 Pattern( VS_OUTPUT_COA_ATLAS Input )
		{
			return Pattern( Input, PdxTex2D( PatternMap, Input.uvPattern ) );
		}
	]]
}

BlendState BlendStateAlphaBlendMax
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
		
	BlendOpAlpha = "max"
	SourceAlpha = "one"	# when using BlendOpAlpha = min or max, source alpha is ignored. Explicitly set to one to avoid warnings
	DestAlpha = "one"	# when using BlendOpAlpha = min or max, dest alpha is ignored. Explicitly set to one to avoid warnings
}