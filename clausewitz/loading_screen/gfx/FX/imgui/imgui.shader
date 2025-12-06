# This is basically just a PDX version of the default ImGui shader

VertexStruct VS_OUTPUT
{
	float4 Position 	: PDX_POSITION;
	float2 UV			: TEXCOORD0;
	float4 Color		: TEXCOORD1;
};

VertexShader =
{
	MainCode VertexShader
	{
		VertexStruct VS_INPUT
		{
			float2 Position  	: POSITION;
			float2 UV  			: TEXCOORD0;
			float4 Color 		: COLOR0;
		};
	
		ConstantBuffer( ImGuiConstants )
		{
			float4x4 ProjectionMatrix;
		};
	
		Input = "VS_INPUT"
		Output = "VS_OUTPUT"
		Code 
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out;

				Out.Position = mul( ProjectionMatrix, float4( Input.Position.xy, 0.0, 1.0 ) );
				Out.UV  = Input.UV;
				Out.Color = Input.Color;

				return Out;
			}
		]]
	}
}

PixelShader =
{
	MainCode PixelShader
	{
		Texture Texture
		{
			Ref = ImGuiTexture
		}

		Sampler DefaultSampler
		{
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Wrap"
			SampleModeV = "Wrap"
		}

		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{
				float4 Ret = Input.Color * PdxSampleTex2D( Texture, DefaultSampler, Input.UV );
				return Ret;
			}
		]]
	}
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"
	SourceAlpha = "one"
	DestAlpha = "inv_src_alpha"
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthFunction = "always"
}

RasterizerState RasterizerState
{
	CullMode = None
	Scissor = yes
}

Effect ImGui
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
