Includes = {
	"cw/pdx_blit.fxh"
}

PixelShader =
{		
	MainCode Blit
	{
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float4 Color = PdxSampleTex2DLod( Texture, Sampler, Input.uv, _MipLevel );				
				return ApplyBlitModifications( Color );
			}		
		]]
	}
}

Effect Blit
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "Blit"
	
	BlendState = "DefaultBlitBlendState"
	DepthStencilState = "DefaultBlitDepthStencilState"
}
