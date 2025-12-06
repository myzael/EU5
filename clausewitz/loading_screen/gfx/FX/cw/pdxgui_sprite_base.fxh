Includes = {
	"cw/utility.fxh"
}

supports_additional_shader_options = {
	PDX_GUI_SPRITE_EFFECT
	PDX_GUI_FRAME_BLEND_EFFECT
}

Code
[[
	// Previously PDX_GUI_MAX_NUM_SPRITES, however this is just a hard coded constant and is directly reflected here instead. 
	// See NPdxGuiHelpers::MaxSprites in code..
	
	static const int MaxSprites = 11;
]]

PixelShader =
{
	ConstantBuffer( PdxGuiSpriteConstants )
	{
		#TODO [FM]: PSGE-5875
		#All instances of '11' here represent the value in the MaxSprites variable. However, due to our 
		#current shader reordering of code, we can't declare our constant in a way that it appears above the constant buffers. 
		
		float4 SpriteTextureAndFrameUVSize[11];
		float4 SpriteBorder[11];
		float4 SpriteTranslateRotateUVAndAlpha[11];
		float4 SpriteSize;
		float4 SpriteUVRect;
		int4   SpriteFramesTypeBlendMode[11];
		int4   SpriteFrameAndGridSize[11];
		float4 SpriteModifyTexturesColors[11];
		float4 SpriteFrameBlendAlpha[11/4+11%2];
		uint4  MirrorFlags[11/4+11%2];
		int    ModifyTexturesCount;
		float  SamplerBias;
	};

	Code
	[[
		float CalcBorderUV( float UV, float UVEdge, float UVScale )
		{
			float Offset = UV - UVEdge;
			Offset *= UVScale;
			return Offset + UVEdge;
			
			// Could be just multiply and add?
			//return UV * UVScale + UVEdge - UVEdge * UVScale; // 'UVEdge - UVEdge * UVScale' constant
		}
		
		float CalcInternalUV( float UV, float UVCutoff, float UVTileFactor, float UVScale, float UVOffset )
		{
			float Offset = UV - UVCutoff;
			Offset *= UVTileFactor;
			Offset = mod( Offset, 1.0 );
			Offset *= UVScale;
			return Offset + UVOffset;
		}
		
		float4 SampleSpriteTexture(
			in PdxTextureSampler2D SpriteTexture,
			float2 uv,
			float4 UVRect,
			float2 BorderUVScale,
			float4 BorderUVCutoff,
			float2 MiddleUVTileFactor,
			float2 MiddleUVScale,
			float2 MiddleUVOffset,
			float2 TranslateUV,
			float RotateUV,
			float2 Dimension )
		{
#ifdef PDX_GUI_SPRITE_EFFECT
			uv = lerp( UVRect.xy, UVRect.zw, uv );

			float2 texDdx = ddx(uv * BorderUVScale);
			float2 texDdy = ddy(uv * BorderUVScale);

			if ( uv.x <= BorderUVCutoff.x )
			{
				uv.x = CalcBorderUV( uv.x, UVRect.x, BorderUVScale.x );
			}
			else if ( uv.x >= BorderUVCutoff.z )
			{
				uv.x = CalcBorderUV( uv.x, UVRect.z, BorderUVScale.x );
			}
			else
			{
				uv.x = CalcInternalUV( uv.x, BorderUVCutoff.x, MiddleUVTileFactor.x, MiddleUVScale.x, MiddleUVOffset.x );
			}
			
			if ( uv.y <= BorderUVCutoff.y )
			{
				uv.y = CalcBorderUV( uv.y, UVRect.y, BorderUVScale.y );
			}
			else if ( uv.y >= BorderUVCutoff.w )
			{
				uv.y = CalcBorderUV( uv.y, UVRect.w, BorderUVScale.y );
			}
			else
			{
				uv.y = CalcInternalUV( uv.y, BorderUVCutoff.y, MiddleUVTileFactor.y, MiddleUVScale.y, MiddleUVOffset.y );
			}

			uv += TranslateUV;

			{
				float s = sin( RotateUV );
				float c = cos( RotateUV );

				uv.x = uv.x * Dimension.x - Dimension.x * 0.5;
				uv.y = uv.y * Dimension.y - Dimension.y * 0.5;

				float UVx = uv.x;
				float UVy = uv.y;

				uv.x = UVx * c - UVy * s;
				uv.y = UVy * c + UVx * s;

				uv.x = uv.x / Dimension.x + 0.5;
				uv.y = uv.y / Dimension.y + 0.5;
			}

			return PdxTex2DGrad( SpriteTexture, uv, texDdx, texDdy );			
#else			
			return PdxTex2DBias( SpriteTexture, uv, SamplerBias );
#endif
		}

		float4 CalcSpriteUV( int Index, int Frame )
		{
			int2 FrameSize     = SpriteFrameAndGridSize[Index].xy;

			if ( FrameSize.x <= 0 || FrameSize.y <= 0 )
				return float4( 0.0, 0.0, 1.0, 1.0 );

			int2 GridSize = SpriteFrameAndGridSize[Index].zw;
			if ( GridSize.x <= 0 || GridSize.y <= 0 )
				return float4( 0.0, 0.0, 1.0, 1.0 );

			int2 GridPos;
			GridPos.y = min( Frame / GridSize.x, GridSize.y - 1 );
			GridPos.x = min( Frame - GridPos.y * GridSize.x, GridSize.x - 1 );

			float2 FrameUVSize = SpriteTextureAndFrameUVSize[Index].zw;

			float4 UVRect;
			UVRect.xy = GridPos * FrameUVSize;
			UVRect.zw = FrameUVSize;

			return UVRect;
		}

		float4 SampleSpriteTexture( 
			in PdxTextureSampler2D SpriteTexture, 
			float2 UV, 
			int Index, 
			int Frame, 
			int Type )
		{
			float4 UVRect             = float4( 0.0, 0.0, 1.0, 1.0 );
			float4 BorderUVRect       = float4( 0.0, 0.0, 1.0, 1.0 );
			float2 BorderUVScale      = float2( 1.0, 1.0 );
			float2 MiddleUVScale      = float2( 1.0, 1.0 );
			float2 MiddleUVOffset     = float2( 0.0, 0.0 );
			float2 MiddleUVTileFactor = float2( 1.0, 1.0 );
			float4 BorderSize         = float4( 0.0, 0.0, 0.0, 0.0 );
			float4 BorderUV           = float4( 0.0, 0.0, 0.0, 0.0 );
			float4 BorderUVCutoff     = float4( 0.0, 0.0, 1.0, 1.0 );

#ifdef PDX_GUI_SPRITE_EFFECT
			UVRect = CalcSpriteUV( Index, Frame );
			float2 UVRectSize = UVRect.zw;
			float2 UVRectBR   = UVRect.xy + UVRectSize;
			float2 UVRectTL   = UVRect.xy;

			BorderUVRect = float4( UVRectTL, UVRectBR );

			float2 ImageSize = float2( SpriteFrameAndGridSize[Index].xy );
			if ( SpriteFrameAndGridSize[Index].x <= 0 || SpriteFrameAndGridSize[Index].y <= 0 )
			{
				ImageSize = SpriteTextureAndFrameUVSize[Index].xy;
			}

			if ( Type != 0 )
			{
				BorderUVScale = SpriteSize.xy / ImageSize;
				BorderSize    = SpriteBorder[Index];

				float BorderWidth = BorderSize.x + BorderSize.z;
				if ( BorderWidth > SpriteSize.x )
				{
					float ScaleFactor = SpriteSize.x / BorderWidth;
					BorderSize.x = BorderSize.x * ScaleFactor;
					BorderSize.z = SpriteSize.x - BorderSize.x;
				}

				float BorderHeight = BorderSize.y + BorderSize.w;
				if ( BorderHeight > SpriteSize.y )
				{
					float ScaleFactor = SpriteSize.y / BorderHeight;
					BorderSize.y = BorderSize.y * ScaleFactor;
					BorderSize.w = SpriteSize.y - BorderSize.y;
				}

				BorderUV.xy = ( BorderSize.xy / ImageSize ) * UVRectSize.xy;
				BorderUV.zw = ( BorderSize.zw / ImageSize ) * UVRectSize.xy;

				float2 TextureMiddle = ImageSize - BorderSize.xy - BorderSize.zw;
				if ( Type == 1 && TextureMiddle.x > 0.0 && TextureMiddle.x > 0.0 )
				{
					float2 Middle = SpriteSize.xy - BorderSize.xy - BorderSize.zw;
					MiddleUVScale.xy = Middle / TextureMiddle;
				}
			}

			BorderUVCutoff.xy = UVRectTL + BorderUV.xy / BorderUVScale.xy;
			BorderUVCutoff.zw = UVRectBR - BorderUV.zw / BorderUVScale.xy;

			MiddleUVTileFactor = MiddleUVScale;
			MiddleUVTileFactor.x = MiddleUVTileFactor.x / ( BorderUVCutoff.z - BorderUVCutoff.x );
			MiddleUVTileFactor.y = MiddleUVTileFactor.y / ( BorderUVCutoff.w - BorderUVCutoff.y );

			MiddleUVScale = UVRectSize.xy - BorderUV.xy - BorderUV.zw;
			MiddleUVOffset = UVRect.xy + BorderUV.xy;

#endif // PDX_GUI_SPRITE_EFFECT

			float2 TranslateUV = SpriteTranslateRotateUVAndAlpha[Index].xy;
			float  RotateUV    = SpriteTranslateRotateUVAndAlpha[Index].z;

			return SampleSpriteTexture(
				SpriteTexture,
				UV,
				BorderUVRect,
				BorderUVScale,
				BorderUVCutoff,
				MiddleUVTileFactor,
				MiddleUVScale,
				MiddleUVOffset,
				TranslateUV,
				RotateUV,
				SpriteSize.xy );
		}

		float4 SampleSpriteTexture( in PdxTextureSampler2D SpriteTexture, float2 UV, int Index )
		{
			int Frame0 = SpriteFramesTypeBlendMode[Index].x;
			int Type   = SpriteFramesTypeBlendMode[Index].z;
			float4 Color0 = SampleSpriteTexture( SpriteTexture, UV, Index, Frame0, Type );
#if defined(PDX_GUI_FRAME_BLEND_EFFECT)
			int Frame1 = SpriteFramesTypeBlendMode[Index].y;

			float4 Color1 = SampleSpriteTexture( SpriteTexture, UV, Index, Frame1, Type );
			return lerp( Color0, Color1, SpriteFrameBlendAlpha[Index/4][Index%4] );
#else
			return Color0;
#endif
		}

		
		// This needs to be in sync with "CPdxGuiImageSprite::EBlendMode"
		float4 Blend( float4 Base, float4 Blend, float Opacity, inout float BlendMask, int Mode )
		{			
			float4 ReturnBlend = Base;

			int ModeId = Mode & 0xf;

			if ( ModeId == 0 ) // Add 
			{
				ReturnBlend = float4( Add( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 1 ) // Overlay
			{
				ReturnBlend = float4( Overlay( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 2 ) // Multiply
			{
				ReturnBlend = float4( Multiply( Base.rgb, Blend.rgb, Opacity ), Base.a);
			}
			else if ( ModeId == 3 ) // ColorDodge
			{
				ReturnBlend = float4( ColorDodge( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 4 ) // Lighten
			{
				ReturnBlend = float4( Lighten( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 5 ) // Darken
			{
				ReturnBlend = float4( Darken( Base.rgb, Blend.rgb, Opacity ), Base.a );
			}
			else if ( ModeId == 6 ) // Mask
			{
				int ChannelIdx = ( 0xf & ( Mode >> 4 ) );
				BlendMask = Blend[ChannelIdx] * Opacity;
			}
			else if ( ModeId == 7 ) // Normal
			{
				ReturnBlend = float4( lerp( Base, Blend, Opacity * Blend.a ).rgb, Base.a );
			}
			else if ( ModeId == 8 ) // AlphaMultiply
			{				
				int ChannelIdx = ( 0xf & ( Mode >> 4 ) );
				ReturnBlend = float4( Base.rgb, Base.a * lerp( 1.0, Blend[ ChannelIdx ], Opacity ) );
			}
			
			return ReturnBlend;
		}

		float2 GetUVForIndex( int Index, float2 UV )
		{
			// NOTE: The bits *must* correspond to the "PdxGui::MirrorFlags" enum

			uint Flags = MirrorFlags[Index/4][Index%4];

			if ( ( Flags & 1u ) != 0 ) // First bit set is a horizontal flip
			{
				UV.x = 1.0 - UV.x;
			}

			if ( ( Flags & 2u ) != 0 ) // Second bit set is a vertical flip
			{
				UV.y = 1.0 - UV.y;
			}

			return UV;
		}
		
		void ApplyModifyTextures( inout float4 Base, float2 UV )
		{
#ifdef PDX_GUI_SPRITE_EFFECT			
			float4 ModifyTextures[MaxSprites-1];

			float BlendMask = 1.0f;

		if ( MaxSprites > 10 )
		{
			if ( ModifyTexturesCount > 9 )
			{
				ModifyTextures[9] = SampleSpriteTexture( ModifyTexture9, GetUVForIndex( 10, UV ), 10 );
			}
		}
		if ( MaxSprites > 9 )
		{
			if ( ModifyTexturesCount > 8 )
			{
				ModifyTextures[8] = SampleSpriteTexture( ModifyTexture8, GetUVForIndex( 9, UV ), 9 );
			}
		}
		if ( MaxSprites > 8 )
		{
			if ( ModifyTexturesCount > 7 )
			{
				ModifyTextures[7] = SampleSpriteTexture( ModifyTexture7, GetUVForIndex( 8, UV ), 8 );
			}
		}
		if ( MaxSprites > 7 )
		{
			if ( ModifyTexturesCount > 6 )
			{
				ModifyTextures[6] = SampleSpriteTexture( ModifyTexture6, GetUVForIndex( 7, UV ), 7 );
			}
		}
		if ( MaxSprites > 6 )
		{
			if ( ModifyTexturesCount > 5)
			{
				ModifyTextures[5] = SampleSpriteTexture( ModifyTexture5, GetUVForIndex( 6, UV ), 6 );
			}
		}
		if ( MaxSprites > 5 )
		{
			if ( ModifyTexturesCount > 4 )
			{
				ModifyTextures[4] = SampleSpriteTexture( ModifyTexture4, GetUVForIndex( 5, UV ), 5 );
			}
		}
		if ( MaxSprites > 4 )
		{
			if ( ModifyTexturesCount> 3 )
			{
				ModifyTextures[3] = SampleSpriteTexture( ModifyTexture3, GetUVForIndex( 4, UV ), 4 );
			}
		}
		if ( MaxSprites > 3 )
		{
			if ( ModifyTexturesCount > 2 )
			{
				ModifyTextures[2] = SampleSpriteTexture( ModifyTexture2, GetUVForIndex( 3, UV ), 3 );
			}
		}
		if ( MaxSprites > 2 )
		{
			if ( ModifyTexturesCount > 1 )
			{
				ModifyTextures[1] = SampleSpriteTexture( ModifyTexture1, GetUVForIndex( 2, UV ), 2 );
			}
		}
		if ( MaxSprites > 10 )
		{
			if ( ModifyTexturesCount > 0 )
			{
				ModifyTextures[0] = SampleSpriteTexture( ModifyTexture0, GetUVForIndex( 1, UV ), 1 );
			}
		}
				
			for ( int i = 0; i < ModifyTexturesCount; ++i )
			{
				float4 ModifyTextureBase = ModifyTextures[i];
				ModifyTextureBase = ModifyTextureBase * SpriteModifyTexturesColors[i+1];
				
				Base = Blend( 
					Base, 
					ModifyTextureBase, 
					BlendMask * SpriteTranslateRotateUVAndAlpha[i+1].w, 
					BlendMask, 
					SpriteFramesTypeBlendMode[i+1].w );
			}
#endif // PDX_GUI_SPRITE_EFFECT
		}
		
		float4 SampleImageSprite( in PdxTextureSampler2D SpriteTexture, float2 UV )
		{
			float4 Base = SampleSpriteTexture( SpriteTexture, UV, 0 );

			UV = (UV - SpriteUVRect.xy) / SpriteUVRect.zw;

			ApplyModifyTextures( Base, UV );

			return Base;
		}
	]]
}
