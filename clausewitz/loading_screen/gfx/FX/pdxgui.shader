Includes = {
	"cw/pdxgui.fxh"
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

	MainCode VertexShaderGraph
	{
		Input = "VS_INPUT_PDX_GUI_GRAPH"
		Output = "VS_OUTPUT_PDX_GUI"
		Code 
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_GUI Out;

				float2 PixelPos = WidgetLeftTop + Input.LeftTop_WidthHeight.xy + Input.Position * Input.LeftTop_WidthHeight.zw;
				Out.Position    = PixelToScreenSpace( PixelPos );
				Out.UV0         = Input.UV;
				Out.Color       = Input.Color;
				
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
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	
	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				return Input.Color;
			}
		]]
	}

	MainCode PixelShaderTextGlow
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				float2 AtlasSize;
				PdxTex2DSize( Texture, AtlasSize );

				float Offsets[3];
				Offsets[0] = 0.0;
				Offsets[1] = 1.3846153846;
				Offsets[2] = 3.2307692308;

				float Weights[3];
				Weights[0] = 0.2270270270;
				Weights[1] = 0.3162162162;
				Weights[2] = 0.0702702703;

				float Alpha = PdxTex2D( Texture, Input.UV0 ).r * Weights[0];
				for ( int j = 1; j < 3; j++ )
				{
					Alpha += PdxTex2D( 
						Texture, 
						Input.UV0 + float2( 0.0, Offsets[j] / AtlasSize.y ) ).r * Weights[j];

					Alpha += PdxTex2D( 
						Texture, 
						Input.UV0 - float2( 0.0, Offsets[j] / AtlasSize.y ) ).r * Weights[j];
				}

				for ( int j = 1; j < 3; j++ )
				{
					Alpha += PdxTex2D( 
						Texture, 
						Input.UV0 + float2( Offsets[j] / AtlasSize.x, 0.0 ) ).r * Weights[j];

					Alpha += PdxTex2D( 
						Texture, 
						Input.UV0 - float2( Offsets[j] / AtlasSize.x, 0.0 ) ).r * Weights[j];
				}

				return float4( Input.Color.rgb, TextTintColor.a * Input.Color.a * Alpha );
			}
		]]
	}

	MainCode PixelShaderText
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				return TextTintColor * float4( Input.Color.rgb, PdxTex2D( Texture, Input.UV0 ).r * Input.Color.a );
			}
		]]
	}

	MainCode PixelShaderTextOutlined
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{
				// Early returns generates the following warning in hlsl:
				// - warning X4000: use of potentially uninitialized variable
				// Use condition variable instead.
				
				int RenderCondition = 0;

				float TextureAlphaThreshold = 0.3f;
				float SampledAlpha = PdxTex2D( Texture, Input.UV0 ).r;

				// Linearly interplate between the colors of glyph and outline
				float3 Color = 0.0f;
				Color += SampledAlpha * Input.Color.rgb;
				Color += ( 1.0f - SampledAlpha ) * TextOutlineColor.rgb;

				// Is fragment in glyph?
				if (SampledAlpha > TextureAlphaThreshold)
				{
					RenderCondition = 1;
				}
				else // is fragment in outline?
				{
					float2 TexelOffset;
					{
						float2 AtlasSize;
						PdxTex2DSize( Texture, AtlasSize );
						TexelOffset[0] = 1.0f / (float)AtlasSize.x;
						TexelOffset[1] = 1.0f / (float)AtlasSize.y;
					}

					// This loop will search for a glyph in the following pattern,
					// ( in this case with TextOutlineWidth = 3 ) and will check 8
					// spots in each iteration.
					//                             
					//  17          18          19
					//                            
					//       9      10      11    
					//                            
					//           1   2   3        
					//                            
					//  20  12   4       5  13  21
					//                            
					//           6   7   8        
					//                            
					//      14      15      16    
					//                            
					//  22          23          24

					float2 OffsetDirections[8] =
					{
						// Upper row, left to right
						TexelOffset * float2( -1, -1 ),
						TexelOffset * float2( 0, -1 ),
						TexelOffset * float2( 1, -1 ),

						// Middle row, left to right
						TexelOffset * float2( -1, 0 ),
						TexelOffset * float2( 1, 0 ),

						// Lower row, left to right
						TexelOffset * float2( -1, 1 ),
						TexelOffset * float2( 0, 1 ),
						TexelOffset * float2( 1, 1 )
					};

					
					[ unroll( /*maximum of*/ 8 ) ]
					for ( int OutlineIndex = 1; OutlineIndex <= TextOutlineWidth; ++OutlineIndex )
					{
						if( RenderCondition == 0 )
						{
							[ unroll ]
							for (int Direction = 0; Direction < 8; ++Direction )
							{
								float2 UV = Input.UV0 + OutlineIndex * OffsetDirections[Direction];
								if ( PdxTex2D( Texture, UV ).r > TextureAlphaThreshold )
								{
									RenderCondition = 1;
								}
							}
						}
					}
				}

				// If neither glyph or outline, let alpha be 0
				return RenderCondition * TextTintColor * float4( Color, Input.Color.a );
			}
		]]
	}
	
	MainCode PixelShaderTextLine
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				return TextTintColor * Input.Color;
			}
		]]
	}

	MainCode PixelShaderTexture
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code 
		[[
			PDX_MAIN
			{	
				#ifdef PDX_USE_MIPLEVELTOOL
					return PdxTex2DMipTool( Texture, Input.UV0 ) *  Input.Color;
				#else
					return PdxTex2D( Texture, Input.UV0 ) *  Input.Color;
				#endif // PDX_USE_MIPLEVELTOOL
			}
		]]
	}
		
	MainCode PixelShaderOutsideRect
	{
		ConstantBuffer( PdxConstantBuffer2 )
		{
			float4 ParentRect;
			float Time;
		};
		
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		
		Code 
		[[
			PDX_MAIN
			{
				if( Input.Position.x > (ParentRect.x + ParentRect.z) ||
					Input.Position.x < ParentRect.x ||
					Input.Position.y > (ParentRect.y + ParentRect.w) ||
					Input.Position.y < ParentRect.y)
				{
					float inv_e = 1.0 / 2.71828;
					float min_red = 0.5;
					float v = min_red + (1.0 - min_red) * (1.0 - (exp( sin( Time * 2.0 ) ) - inv_e) * 0.42545906412);
					
					return float4( v, 0.0, 0.0, 0.6 );
				}
				else
					return float4( 0.0, 0.0, 0.0, 0.0 );
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


Effect PdxDefaultGUI
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect PdxDefaultGUITexture
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderTexture"
}

Effect PdxDefaultGUIGraph
{
	VertexShader = "VertexShaderGraph"
	PixelShader = "PixelShaderTexture"
}

Effect PdxDefaultGUIText
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderText"
}

Effect PdxDefaultGUITextGlow
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderTextGlow"
}

Effect PdxDefaultGUITextOutlined
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderTextOutlined"
}

Effect PdxDefaultGUITextUnderline
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderTextLine"
}

Effect PdxDefaultGUITextStrikethrough
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderTextLine"
}

Effect PdxDefaultGUIDebug
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect PdxOutsideRect
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderOutsideRect"
}
