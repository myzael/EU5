Includes = {
	"cw/pdxgui_line.fxh"
}

PixelShader =
{
	MainCode PS_PdxGuiLineOnlyColor
	{
		Input = "VS_PDXGUI_LINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float Alpha = CalcAlpha( Input, FeatherDistance );
				
				return float4( Color.rgb, Color.a * Alpha );
			}
		]]
	}
	
	MainCode PS_PdxGuiLine
	{
		TextureSampler Texture
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Wrap"
			SampleModeV = "Wrap"
		}
		
		TextureSampler MaskTexture
		{
			Ref = PdxTexture1
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}
	
		Input = "VS_PDXGUI_LINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float4 Diffuse = PdxTex2D( Texture, Input.UV );
				Diffuse *= Color;
				
				float4 Mask = SampleMask( Input.MaskUV, MaskTexture );
				Diffuse *= Mask;
				
				float Alpha = CalcAlpha( Input, FeatherDistance );
				return float4( Diffuse.rgb, Diffuse.a * Alpha );
			}
		]]
	}
	
	MainCode PS_PdxGuiLineScreenSpace
	{
		TextureSampler Texture
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Wrap"
			SampleModeV = "Wrap"
		}
		
		TextureSampler MaskTexture
		{
			Ref = PdxTexture1
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}
	
		Input = "VS_PDXGUI_LINE_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 TextureSize;
				PdxTex2DSize( Texture, TextureSize );
		
				float2 UV = UVScale * Input.WidgetLocalPos / TextureSize;
				UV -= UVAnimationSpeed * GuiTime;
				
				float4 Diffuse = PdxTex2D( Texture, UV );
				Diffuse *= Color;
				
				float4 Mask = SampleMask( Input.MaskUV, MaskTexture );
				Diffuse *= Mask;
				
				float Alpha = CalcAlpha( Input, FeatherDistance );
				return float4( Diffuse.rgb, Diffuse.a * Alpha );
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

Effect PdxGuiLineOnlyColor
{
	VertexShader = "VS_PdxGuiLine"
	PixelShader = "PS_PdxGuiLineOnlyColor"
}

Effect PdxGuiLine 
{
	VertexShader = "VS_PdxGuiLine"
	PixelShader = "PS_PdxGuiLine"
}

Effect PdxGuiLineScreenSpace 
{
	VertexShader = "VS_PdxGuiLine"
	PixelShader = "PS_PdxGuiLineScreenSpace"
}
