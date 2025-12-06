Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite_base.fxh"
	"cw/pdxgui_sprite_textures.fxh"
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
	}
	
	MainCode PixelShaderApplyModifyTextures
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				return SampleImageSprite( Texture, Input.UV0) * Input.Color;
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

Effect PdxDefaultGUIApplyModifyTextures
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderApplyModifyTextures"
	Defines = { "PDX_GUI_SPRITE_EFFECT" }
}