Includes = {
	"cw/fullscreen_vertexshader.fxh"
}

ConstantBuffer( PdxConstantBuffer0 )
{
	int SampleCount;
	int2 Offset;
}

PixelShader =
{
	TextureSampler Texture
	{
		Ref = PdxTexture0
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		MultiSampled = yes		#MultiSampled textures can't be sampled like normal textures. PdxTex2DMultiSampled must be used
	}

	MainCode PixelShader
	{
		Input = "VS_OUTPUT_FULLSCREEN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{	
				float4 Color = vec4(0);
				
				for( int i = 0; i < SampleCount; ++i )
				{
					float4 Sample = PdxTex2DMultiSampled( Texture, int2(Input.position.xy) + Offset, i );
					
					#ifdef NORMALIZE_RGB_AVERAGE_ALPHA
					Sample.rgb *= Sample.a;
					#endif
					Color += Sample;
				}
				
				#if defined( NORMALIZE_RGB_AVERAGE_ALPHA )
				Color.rgb /= Color.a;
				Color.a /= SampleCount;
				#else
				Color /= SampleCount;
				#endif
				
				return Color;
			}
		]]
	}
}


BlendState BlendState
{
	BlendEnable = no
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}

Effect IgnoreTransparent	#This effect will ignore the color of transparent samples. This removes artifacts when the render target is cleared with 0,0,0,0 for instance
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "PixelShader"
	Defines = { "NORMALIZE_RGB_AVERAGE_ALPHA" }
}

Effect Average
{
	VertexShader = "VertexShaderFullscreen"
	PixelShader = "PixelShader"
}
