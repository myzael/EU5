Includes = {
	"cw/fullscreen_vertexshader.fxh"
	"cw/utility.fxh"
}

PixelShader =
{		
	Texture Texture
	{
		Ref = PdxTexture0
	}

	Sampler Sampler
	{
		Ref = PdxSampler0
	}
		
	ConstantBuffer( PdxConstantBuffer0 )
	{
		uint _ToGamma;
		uint _UseTextureAlpha;
		float _AlphaMultiply;
		float _MipLevel;
	};
	
	Code
	[[
		float4 ApplyBlitModifications( float4 Color )
		{	
			if ( _ToGamma != 0 )
			{
				Color.rgb = ToGamma( Color.rgb );
			}
			if ( _UseTextureAlpha == 0 )
			{
				Color.a = 1.0;
			}
			
			Color.a *= _AlphaMultiply;
			
			return Color;
		}
	]]
}

BlendState DefaultBlitBlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

DepthStencilState DefaultBlitDepthStencilState
{
	DepthEnable = no
	DepthWriteEnable = no
}
