# Very simple shader used by the texture atlas to draw frames on to the larger atlas texture

Includes = {
	"cw/fullscreen_vertexshader.fxh"
}

PixelShader =
{
	TextureSampler SourceTexture
	{
		Ref = PdxTextureAtlasFrame
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}

	MainCode PSTextureAtlas
	{
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{	
				 return PdxTex2D( SourceTexture, Input.uv );
			}
		]]
	}
}

Effect TextureAtlasEffect
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "PSTextureAtlas"
}