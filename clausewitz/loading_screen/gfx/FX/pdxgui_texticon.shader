Includes = {
	"cw/pdxgui.fxh"
}

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
	TextureSampler Texture
	{
		Ref = PdxTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		MipMapLodBias = -1
	}

	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				#ifdef PDX_USE_MIPLEVELTOOL
					float4 Color = PdxTex2DMipTool( Texture, Input.UV0 ) * Input.Color;
				#else
					float4 Color = PdxTex2D( Texture, Input.UV0 ) * Input.Color;
				#endif // PDX_USE_MIPLEVELTOOL
				
				Color.a = Color.a * TextTintColor.a;
				return Color;
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

DepthStencilState DepthStencilState
{
	DepthEnable = no
}

Effect PdxDefaultGUITextIcon
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
