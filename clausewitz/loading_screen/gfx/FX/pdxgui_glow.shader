Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite.fxh"
}

ConstantBuffer( PdxGuiGlowConstants )
{
	float2 _UVScale;
	float2 _UVOffset;
	float  _RequestedRadiusNorm;
	float  _EdgeValueNorm;
	float  _Alpha;
};

VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_GUI"
		Output = "VS_OUTPUT_PDX_GUI"
		Code
		[[
			PDX_MAIN
			{
				return PdxGuiDefaultVertexShader( Input );
			}
		]]
	}
}

PixelShader =
{
	MainCode DistanceField
	{
		TextureSampler Texture
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		
		Code
		[[
			PDX_MAIN
			{
				float2 UV = Input.UV0 * _UVScale + _UVOffset;
				float Distance = PdxTex2D(Texture, UV).r;
				float Outer = abs(_EdgeValueNorm - Distance) / _RequestedRadiusNorm;
				float DistanceAlpha =  lerp(0.0f, 1.0f, 1.0f - Outer);
				return float4(Input.Color.rgb, _Alpha * DistanceAlpha * Input.Color.a);
			}
		]]
	}
}
BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}
Effect PdxDefaultGlow
{
	VertexShader = "VertexShader"
	PixelShader = "DistanceField"
	Defines = { "PDX_GUI_SPRITE_EFFECT" }
}