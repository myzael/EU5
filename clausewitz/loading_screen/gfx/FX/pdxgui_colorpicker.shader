Includes = {
	"cw/pdxgui.fxh"
	"cw/utility.fxh"
}

ConstantBuffer( PdxConstantBuffer2 )
{
	float4 ColorIn;
	float4 OriginalColor; // Original color value. This only changes when the color picker is opened
	float4 CachedColor; // Does not change while updating, only after color has been set
	float2 HueSaturation; // Hue and Saturation values to use when undefined
	int ActiveColor;
	int ColorSpace; // 0 linear, 1 srgb
};

VertexStruct VS_OUTPUT_PDX_GUI2
{
	float4 Position		: PDX_POSITION;
	float2 UV0			: TEXCOORD0;
	float2 Pos			: TEXCOORD1;
	float2 WidthHeight	: TEXCOORD2;
	float4 Color		: COLOR;
};

Code
[[
    float2 CalculateOffset( float2 Pos, float2 WidthHeight )
    {
		return Pos * WidthHeight / ( WidthHeight - vec2( 1.0 ) ) - float2( 0.5, 0.5 ) / WidthHeight;
    }

	float4 TransformColor( float4 LinearColor, int ColorSpace )
	{
		if( ColorSpace == 1 )
		{
			return ToGamma(LinearColor);
		}

		return LinearColor;
	}
]]

VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_GUI"
		Output = "VS_OUTPUT_PDX_GUI2"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_GUI copy = PdxGuiDefaultVertexShader( Input );
				
				VS_OUTPUT_PDX_GUI2 Out;
				Out.Position = copy.Position;
				Out.UV0 = copy.UV0;
				Out.Color = copy.Color;
				Out.Pos = Input.Position;
				Out.WidthHeight = Input.LeftTop_WidthHeight.zw;
	
				return Out;
			}
		]]
	}
}

PixelShader =
{
	TextureSampler Texture
	{
		Ref = PdxTexture0
		MagFilter = "Point"
		MinFilter = "Point"
		MipFilter = "Point"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	
	MainCode PixelShaderArea
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				
				float4 ColorBackground = PdxTex2D( Texture, Input.Pos * ( Input.WidthHeight / vec2( 16.0 ) ) );
				float4 ColorOut;

				if ( ActiveColor == 0 ) // Red
				{
					ColorOut = float4( CachedColor.r, 1.0 - Offset.y, Offset.x, 1.0 );
				}
				else if ( ActiveColor == 1 ) // Green
				{
					ColorOut = float4( 1.0 - Offset.y, CachedColor.g, Offset.x, 1.0 );
				}
				else if ( ActiveColor == 2 ) // Blue
				{
					ColorOut = float4( Offset.x, 1.0 - Offset.y, CachedColor.b, 1.0 );
				}
				else if ( ActiveColor == 3 ) // Alpha
				{
					ColorOut = float4( 0.0, 0.0, 0.0, 1.0 );
				}
				else if ( ActiveColor == 4 ) // Hue
				{
					float3 HSV = float3( HueSaturation.x, Offset.x, 1.0 - Offset.y );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}
				else if ( ActiveColor == 5 ) // Saturation
				{
					float3 HSV = float3( Offset.x, 1.0, 1.0 - Offset.y );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}
				else if ( ActiveColor == 6 ) // Value
				{
					float3 HSV = float3( Offset.x, 1.0 - Offset.y, 1.0 );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}

			    return DisableColorReturn( TransformColor( ColorOut * ColorOut.a + ColorBackground * ( 1.0 - ColorOut.a ), ColorSpace ) );
			}
		]]
	}
	
	MainCode PixelShaderSliderActive
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				
				float4 ColorOut;

				if ( ActiveColor == 0 ) // Red
				{
					ColorOut = float4( 1.0 - Offset.y, 0.0, 0.0, 1.0 );
				}
				else if ( ActiveColor == 1 ) // Green
				{
					ColorOut = float4( 0.0, 1.0 - Offset.y, 0.0, 1.0 );
				}
				else if ( ActiveColor == 2 ) // Blue
				{
					ColorOut = float4( 0.0, 0.0, 1.0 - Offset.y, 1.0 );
				}
				else if ( ActiveColor == 3 ) // Alpha
				{
					float4 ColorBackground = PdxTex2D( Texture, Input.Pos * ( Input.WidthHeight / vec2( 16.0 ) ) );
					ColorOut = float4( ColorIn.rgb, 1.0 - Offset.y );
					return ColorOut * ColorOut.a + ColorBackground * ( 1.0 - ColorOut.a );
				}
				else if ( ActiveColor == 4 ) // Hue
				{
					float3 HSV = float3( 1.0 - Offset.y, 1.0, 1.0 );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}
				else if ( ActiveColor == 5 ) // Saturation
				{
					float3 HSV = float3( HueSaturation.x, 1.0 - Offset.y, 1.0 );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}
				else if ( ActiveColor == 6 ) // Value
				{
					float3 HSV = float3( HueSaturation.x, HueSaturation.y, 1.0 - Offset.y );
					ColorOut.rgb = HSVtoRGB( HSV );
					ColorOut.a = 1.0;
				}
				
			    return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}
	
	MainCode PixelShaderSliderRed
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut = float4( Offset.x, 0.0, 0.0, 1.0 );

			    return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}
	
	MainCode PixelShaderSliderGreen
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );	
				float4 ColorOut = float4( 0.0, Offset.x, 0.0, 1.0 );
				
			    return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}
	
	MainCode PixelShaderSliderBlue
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut = float4( 0.0, 0.0, Offset.x, 1.0 );
				
			    return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}
	
	MainCode PixelShaderSliderAlpha
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				
				float4 ColorBackground = PdxTex2D( Texture, Input.Pos * ( Input.WidthHeight / vec2( 16.0 ) ) );
				float4 ColorOut = float4( ColorIn.rgb, Offset.x );
				
				return ColorOut * ColorOut.a + ColorBackground * ( 1.0 - ColorOut.a );
			}
		]]		
	}

	MainCode PixelShaderSliderHue
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut;

				float3 HSV = float3( Offset.x, 1.0, 1.0 );
				ColorOut.rgb = HSVtoRGB( HSV );
				ColorOut.a = 1.0;
				
				return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}

	MainCode PixelShaderSliderSaturation
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut;

				float3 HSV = float3( HueSaturation.x, Offset.x, 1.0 );
				ColorOut.rgb = HSVtoRGB( HSV );
				ColorOut.a = 1.0;
				
				return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}

	MainCode PixelShaderSliderValue
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				
				float4 ColorOut;

				float3 HSV = float3( HueSaturation.x, HueSaturation.y, Offset.x );
				ColorOut.rgb = HSVtoRGB( HSV );
				ColorOut.a = 1.0;
				
				return DisableColorReturn( TransformColor( ColorOut, ColorSpace ) );
			}
		]]		
	}

	MainCode PixelShaderButton
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		
		Code
		[[
			PDX_MAIN
			{
				float4 ColorBackground = PdxTex2D( Texture, Input.Pos * ( Input.WidthHeight / vec2( 16.0 ) ) );
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut = ColorIn;
				ColorOut.a = 1.0;
				float Mask1 = floor( ( Offset.x + Offset.y ) );
				float Mask2 = ( 1.0 - floor( ( Offset.x + Offset.y ) ) );
				return DisableColorReturn( TransformColor( ColorOut * Mask2 + ( ColorBackground * ( 1.0 - ColorIn.a ) + ColorOut * ColorIn.a ) * Mask1, ColorSpace ) );
			}
		]]
	}
	
	MainCode PixelShaderOriginal
	{
		Input = "VS_OUTPUT_PDX_GUI2"
		Output = "PDX_COLOR"
		
		Code
		[[
			PDX_MAIN
			{
				float4 ColorBackground = PdxTex2D( Texture, Input.Pos * ( Input.WidthHeight / vec2( 16.0 ) ) );
				float2 Offset = CalculateOffset( Input.Pos, Input.WidthHeight );
				float4 ColorOut = OriginalColor;
				ColorOut.a = 1.0;
				float Mask1 = floor( ( Offset.x + Offset.y ) );
				float Mask2 = ( 1.0 - floor( ( Offset.x + Offset.y ) ) );
				return DisableColorReturn( TransformColor( ColorOut * Mask2 + ( ColorBackground * ( 1.0 - OriginalColor.a ) + ColorOut * OriginalColor.a ) * Mask1, ColorSpace ) );
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


Effect PdxGuiColorArea
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderArea"
}

Effect PdxGuiColorAreaDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderArea"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderActive
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderActive"
}

Effect PdxGuiColorSliderActiveDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderActive"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderRed
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderRed"
}

Effect PdxGuiColorSliderRedDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderRed"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderGreen
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderGreen"
}

Effect PdxGuiColorSliderGreenDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderGreen"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderBlue
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderBlue"
}

Effect PdxGuiColorSliderBlueDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderBlue"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderAlpha
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderAlpha"
}

Effect PdxGuiColorSliderAlphaDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderAlpha"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderHue
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderHue"
}

Effect PdxGuiColorSliderHueDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderHue"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderSaturation
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderSaturation"
}

Effect PdxGuiColorSliderSaturationDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderSaturation"
	
	Defines = { "DISABLED" }
}


Effect PdxGuiColorSliderValue
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderValue"
}

Effect PdxGuiColorSliderValueDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderSliderValue"
	
	Defines = { "DISABLED" }
}

Effect PdxGuiColorButton
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderButton"
}

Effect PdxGuiColorButtonDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderButton"
	
	Defines = { "DISABLED" }
}

Effect PdxGuiColorOriginal
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderOriginal"
}

Effect PdxGuiColorOriginalDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderOriginal"
	
	Defines = { "DISABLED" }
}
