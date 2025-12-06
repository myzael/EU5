Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite.fxh"
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
				VS_OUTPUT_PDX_GUI Out;

				float2 Normalised = ( Input.Position.xy + 1.0f ) / 2.0f;
				float2 PixelPos = Normalised * Input.LeftTop_WidthHeight.zw + Input.LeftTop_WidthHeight.xy;

				Out.Position = PixelToScreenSpace( PixelPos );
				Out.UV0      = Normalised;
				Out.Color    = Input.Color;

				return Out;
			}
		]]
	}
	
	MainCode VertexShaderPieChart
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

	TextureSampler MaskTexture
	{
		Ref = PdxTexture1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}

	MainCode PixelShader
	{
		ConstantBuffer( PdxConstantBuffer2 )
		{
			float3 HighlightColor;
		};

		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{			
				float4 Mask  = PdxTex2DLod0( MaskTexture, Input.UV0 );
				float4 Color = SampleImageSprite( Texture, Input.UV0 );

				float4 OutColor = Color * Input.Color * Mask;
				#ifndef NO_HIGHLIGHT
					OutColor.rgb += HighlightColor;
				#endif
				return OutColor;
			}
		]]
	}
	
	MainCode PixelShaderPieChart
	{
		ConstantBuffer( PdxConstantBuffer2 )
		{
			float2 WidgetScreenSize;
			float StartAngle;
			int NumSlices;
		};
		
		ConstantBuffer( PdxConstantBuffer3 )
		{
			# See CPdxGuiGfxTypePieChart::Render, each slice uses 2 float4
			# first float4 contains: x = StartAngle, y = EndAngle, z = highlight
			# second float4 contains the color
			float4 PieSliceData[2048];
		};
		
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code
		[[
			int FindSlice( float Angle, int StartIndex )
			{
				for ( int i = StartIndex; i < NumSlices; ++i )
				{
					int SliceDataIndex = 2 * i;
					if ( Angle > PieSliceData[SliceDataIndex].x && Angle <= PieSliceData[SliceDataIndex].y )
					{
						return i;
					}
				}
				
				return 0;
			}
			
			PDX_MAIN
			{			
				float4 Mask  = PdxTex2DLod0( MaskTexture, Input.UV0 );
				float4 Color = SampleImageSprite( Texture, Input.UV0 );
				
				float2 Direction = Input.UV0 - vec2( 0.5 );
				float2 DirectionNormalized = normalize( Direction );
				
				// Calculate 0.0 - 2 * PI angle
				float Angle = acos( clamp( DirectionNormalized.x, -1.0, 1.0 ) );
				Angle = ( DirectionNormalized.y < 0.0 ) ? Angle : 2.0 * PI - Angle;
				// Offset chart to match StartAngle
				Angle -= StartAngle;
				
				float DistanceFromCenter = length( Direction * WidgetScreenSize );
				
				float ArcLength = 0.5; // Half a pixel in each direction
				float SearchAngle = ArcLength / DistanceFromCenter;
				
				// limit the search angle
				SearchAngle = min( 0.5, SearchAngle );
				
				float StartSearchAngle =  Angle - SearchAngle;
				// We should only need to check for underflow since it is assumed that StartAngle and SearchAngle are positive
				if ( StartSearchAngle < 0.0 )
				{
					StartSearchAngle += 2.0 * PI;
				}
				// Find the start slice
				int StartSlice = FindSlice( StartSearchAngle, 0 );
				
				// We should only need to check for overflow since StartSearchAngle was already checked for underflow and SearchAngle is positive
				float EndSearchAngle = StartSearchAngle + SearchAngle * 2.0;
				int EndSlice = 0;
				if ( EndSearchAngle > 2.0 * PI )
				{
					EndSearchAngle -= 2.0 * PI;
					EndSlice = FindSlice( EndSearchAngle, 0 ); // Need to search from start when wrapping around
				}
				else
				{
					EndSlice = FindSlice( EndSearchAngle, StartSlice );
				}
				#ifndef NO_HIGHLIGHT
					float Highlight = 0.0;
				#endif
				float4 SliceColor = vec4( 0.0 );
				if ( StartSlice != EndSlice )
				{
					// If start and end differ, we need to combine their colors by lerping their search angle coverage
					float FullSearchAngleInv = 0.5 / SearchAngle;
					int CurrentSlice = StartSlice;
					float CurrentAngle = StartSearchAngle;
					for ( int i = 0; i < NumSlices; ++i )
					{
						int SliceDataIndex = 2 * CurrentSlice;
						float EndAngle = ( EndSearchAngle < PieSliceData[SliceDataIndex].x ) ? PieSliceData[SliceDataIndex].y : min( PieSliceData[SliceDataIndex].y, EndSearchAngle );
						float SliceFraction = ( EndAngle - CurrentAngle ) * FullSearchAngleInv;
						#ifndef NO_HIGHLIGHT
							Highlight += PieSliceData[SliceDataIndex].z * SliceFraction;
						#endif
						SliceColor += PieSliceData[SliceDataIndex + 1] * SliceFraction;
						
						if ( CurrentSlice == EndSlice )
						{
							break;
						}
						
						CurrentSlice++;
						CurrentAngle = EndAngle;
						if ( CurrentSlice == NumSlices )
						{
							CurrentSlice = 0;
							CurrentAngle = 0.0;
						}
					}
				}
				else
				{
					// If they are the same just return the slice properties
					int SliceDataIndex = StartSlice * 2;
					#ifndef NO_HIGHLIGHT
						Highlight = PieSliceData[SliceDataIndex].z;
					#endif
					SliceColor = PieSliceData[SliceDataIndex + 1];
				}
				
				float4 OutColor = SliceColor * Color * Input.Color * Mask;
				#ifndef NO_HIGHLIGHT
					OutColor.rgb += vec3( Highlight );
				#endif
				return OutColor;
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


Effect Default 
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect NoHighlightDefault
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	Defines = {"NO_HIGHLIGHT"}
}

Effect PieChartDefault
{
	VertexShader = "VertexShaderPieChart"
	PixelShader = "PixelShaderPieChart"
}

Effect PieChartNoHighlightDefault
{
	VertexShader = "VertexShaderPieChart"
	PixelShader = "PixelShaderPieChart"
	Defines = {"NO_HIGHLIGHT"}
}