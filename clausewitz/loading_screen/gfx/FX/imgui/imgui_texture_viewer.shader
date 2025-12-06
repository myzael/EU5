Includes = {
	"cw/utility.fxh"
}

VertexStruct VS_OUTPUT
{
	float4 Position 	: PDX_POSITION;
	float2 UV			: TEXCOORD0;
	float4 Color		: TEXCOORD1;
};

VertexShader =
{
	MainCode VertexShader
	{
		VertexStruct VS_INPUT
		{
			float2 Position  	: POSITION;
			float2 UV  			: TEXCOORD0;
			float4 Color 		: COLOR0;
		};
	
		ConstantBuffer( ImGuiConstants )
		{
			float4x4 ProjectionMatrix;
		};
	
		Input = "VS_INPUT"
		Output = "VS_OUTPUT"
		Code 
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out;

				Out.Position = mul( ProjectionMatrix, float4( Input.Position.xy, 0.0, 1.0 ) );
				Out.UV  = Input.UV;
				Out.Color = Input.Color;

				return Out;
			}
		]]
	}
}

PixelShader =
{
	MainCode PixelShader
	{
		Texture Texture
		{
			Ref = PdxTexture0
		}
		
		Texture ArrayTexture
		{
			Ref = PdxTexture1
			type = "2darray"
		}

		Sampler ImageSampler
		{
			Ref = PdxSampler0
			MagFilter = "Linear"
			MinFilter = "Linear"
			MipFilter = "Linear"
			SampleModeU = "Clamp"
			SampleModeV = "Clamp"
		}
		
		ConstantBuffer( PdxConstantBuffer0 )
		{
			float4x4 _ColorMatrix;
			float4 _ColorAdd;
			float _ToGamma;
			float _FlipU;
			float _FlipV;
			float _IsArrayTexture;
			int _Mip;
			int _ArrayIndex;
		}

		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code 
		[[
			float GetTextureBorder( float2 UV, float2 TextureSize, float BorderSize )
			{
				float2 FracScaledUV = frac( UV * TextureSize );
				if ( FracScaledUV.x < BorderSize || FracScaledUV.x > (1.0 - BorderSize) || FracScaledUV.y < BorderSize || FracScaledUV.y > (1.0 - BorderSize) )
				{
					return 1.0;
				}
				else
				{
					return 0.0;
				}
			}
			
			PDX_MAIN
			{
				float2 UV = Input.UV;
				if( _FlipU > 0.0 )
				{
					UV.x = 1.0 - UV.x;
				}
				if( _FlipV > 0.0 )
				{
					UV.y = 1.0 - UV.y;
				}
			
			#ifdef ARRAY_TEXTURE
				float4 Sample = PdxSampleTex2DLod( ArrayTexture, ImageSampler, float3( UV, _ArrayIndex ), _Mip );
			#else
				float4 Sample = PdxSampleTex2DLod( Texture, ImageSampler, UV, _Mip );
			#endif
				
				float4 Color = mul( _ColorMatrix, Sample ) + _ColorAdd;
				
				if ( _ToGamma > 0.0 )
				{
					Color.rgb = ToGamma( Color.rgb );
				}
				
			//#define BORDER
			#ifdef BORDER
				float2 TextureSize;
				#ifdef ARRAY_TEXTURE
					float Elements;
					PdxTexture2DArraySize( ArrayTexture, TextureSize, Elements );
				#else
					PdxTexture2DSize( Texture, TextureSize );
				#endif
				
				float TexelBorder = GetTextureBorder( UV, TextureSize, 0.05 );
				float3 HSV = RGBtoHSV( Color.rgb );
				Color.rgb = lerp( Color.rgb, HSVtoRGB( HSV.x + 0.5, 1.0 - HSV.y, 1.0 - HSV.z ), TexelBorder );
			#endif
			
				float4 Ret = Input.Color * Color;
				return Ret;
			}
		]]
	}
}

BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "src_alpha"
	DestBlend = "inv_src_alpha"
	SourceAlpha = "one"
	DestAlpha = "inv_src_alpha"
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
	DepthFunction = "always"
}

RasterizerState RasterizerState
{
	CullMode = None
	Scissor = yes
}

Effect TextureViewer
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
