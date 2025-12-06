Includes = {
	"cw/particle2.fxh"
}

PixelShader =
{
	MainCode PixelTexture
	{
		Input = "VS_OUTPUT_PARTICLE"
		Output = "PDX_COLOR"
		Code
		[[
		PDX_MAIN
		{
			#ifdef PDX_USE_MIPLEVELTOOL
				float4 Color = PdxTex2DMipTool( DiffuseMap, Input.UV0 ) * Input.Color;
				float4 NextColor = PdxTex2DMipTool( DiffuseMap, Input.UV1 ) * Input.Color;
			#else
				float4 Color = PdxTex2D( DiffuseMap, Input.UV0 ) * Input.Color;
				float4 NextColor = PdxTex2D( DiffuseMap, Input.UV1 ) * Input.Color;
			#endif // PDX_USE_MIPLEVELTOOL

			Color = Color * ( 1.0f - Input.FrameBlend ) + NextColor * Input.FrameBlend;

			return Color;
		}
		]]
	}

	MainCode AlphaErosion
	{
		Input = "VS_OUTPUT_PARTICLE"
		Output = "PDX_COLOR"
		Code
		[[
		PDX_MAIN
		{
			float minLevel = 1.0 - Input.Color.a;
			float maxLevel = 1.0;

			#ifdef PDX_USE_MIPLEVELTOOL
				float4 Color = PdxTex2DMipTool( DiffuseMap, Input.UV0 ) * Input.Color;
			#else
				float4 Color = PdxTex2D( DiffuseMap, Input.UV0 ) * Input.Color;
			#endif // PDX_USE_MIPLEVELTOOL
			
			Color.a = saturate( ( Color.a - minLevel ) / ( maxLevel - minLevel ) );	

			return Color;
		}
		]]
	}
}

RasterizerState RasterizerStateNoCulling
{
	CullMode = "none"
}

DepthStencilState DepthStencilState
{
	DepthEnable = yes
	DepthWriteEnable = no
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
	WriteMask = "RED|GREEN|BLUE"
}

BlendState AdditiveBlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	SourceAlpha = "SRC_ALPHA"
	DestBlend = "ONE"
	DestAlpha = "ONE"
	WriteMask = "RED|GREEN|BLUE|ALPHA"
}

Effect ErosionT
{
	VertexShader = "VertexParticle"
	PixelShader = "AlphaErosion"
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ErosionTB
{
	VertexShader = "VertexParticle"
	PixelShader = "AlphaErosion"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ErosionTBE
{
	VertexShader = "VertexParticle"
	PixelShader = "AlphaErosion"
	BlendState = "AdditiveBlendState"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTexture
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleColor
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTextureBillboard
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleColorBillboard
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTBE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	BlendState = "AdditiveBlendState"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleCBE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	BlendState = "AdditiveBlendState"
	Defines = { "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	BlendState = "AdditiveBlendState"
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleCE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	BlendState = "AdditiveBlendState"
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleColorFade
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	Defines = { "FADE_STEEP_ANGLES" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTextureFade
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	Defines = { "FADE_STEEP_ANGLES" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleCFE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	BlendState = "AdditiveBlendState"
	Defines = { "FADE_STEEP_ANGLES" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTFE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	BlendState = "AdditiveBlendState"
	Defines = { "FADE_STEEP_ANGLES" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleCFB
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	Defines = { "FADE_STEEP_ANGLES" "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTFB
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelTexture"
	Defines = { "FADE_STEEP_ANGLES" "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleCFBE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	BlendState = "AdditiveBlendState"
	Defines = { "FADE_STEEP_ANGLES" "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}

Effect ParticleTFBE
{
	VertexShader = "VertexParticle"
	PixelShader = "PixelColor"
	BlendState = "AdditiveBlendState"
	Defines = { "FADE_STEEP_ANGLES" "BILLBOARD" }
	RasterizerState = "RasterizerStateNoCulling"
}