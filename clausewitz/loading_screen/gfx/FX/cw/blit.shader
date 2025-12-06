Includes = {
	"cw/fullscreen_vertexshader.fxh"
}

PixelShader =
{
	MainCode Blit
	{
		TextureSampler BackBuffer
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				return PdxTex2DLod0( BackBuffer, float2( Input.uv.x, 1.0 - Input.uv.y ) );
			}		
		]]
	}

	MainCode Vulkan_Blit
	{
		TextureSampler BackBuffer
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{				
				return PdxTex2DLod0( BackBuffer, float2( Input.uv.x, Input.uv.y ) );
			}		
		]]
	}

	MainCode Render_Blit
	{
		TextureSampler BackBuffer
		{
			Ref = PdxTexture0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}

		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{				
				return PdxTex2DLod0( BackBuffer, float2( Input.uv.x, Input.uv.y ) );
			}		
		]]
	}
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}

RasterizerState RasterizerState
{
}

Effect blit
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "Blit"
}

Effect vulkan_blit
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "Vulkan_Blit"
}

Effect render_blit
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "Render_Blit"
}
