Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite.fxh"
	"cw/utility.fxh"
	"standardfuncsgfx.fxh"
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
	MainCode PixelShader
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
				float4 OutColor = SampleImageSprite( Texture, Input.UV0 );
				OutColor *= Input.Color;
				// Match the portrait shader's IsGrayscale path so dead-character
				// backgrounds tone-match the dead-character portrait.
				OutColor.rgb = lerp( OutColor.rgb, DisableColor( OutColor.rgb ), 0.8 );
				OutColor.rgb *= 0.8;
				// Camera target may have alpha < 1; the original ecs_scene_viewer
				// shader uses PdxGuiDefaultNoAlpha which forces opaque output.
				OutColor.a = 1.0;
				return OutColor;
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


Effect PdxGuiDesaturate
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
Effect PdxGuiDesaturateDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
